import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppContextHolder } from '../common/AppContextHolder';
import { errorMessage } from '../common/JsonUtil';
import { ApiClient } from '../network/ApiClient';
import { LlmStore } from '../store/LlmStore';
import { concatBytes, pcm16LeToWav } from '../utils/Wav';

export type AsrPartial = (text: string, isFinal: boolean) => void;

export class AsrService {
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private sessionId: string = '';
  private running: boolean = false;
  private pcmChunks: Uint8Array[] = [];
  private pcmBytes: number = 0;
  private static readonly MAX_PCM_BYTES: number = 16000 * 2 * 90;
  private mode: 'system' | 'record' = 'record';
  private onPartial: AsrPartial | undefined = undefined;
  private finals: string = '';

  async start(onPartial: AsrPartial): Promise<void> {
    await this.stopInternal(false);
    this.onPartial = onPartial;
    this.finals = '';
    this.pcmChunks = [];
    this.pcmBytes = 0;
    const ok = await AsrService.ensureMic();
    if (!ok) {
      throw new Error('需要麦克风权限才能口述。');
    }
    try {
      await this.startSystem();
      this.mode = 'system';
    } catch (_e) {
      await this.startRecordOnly();
      this.mode = 'record';
    }
    this.running = true;
  }

  async stop(): Promise<string> {
    return this.stopInternal(true);
  }

  isRunning(): boolean {
    return this.running;
  }

  usingCloudUpload(): boolean {
    return this.mode === 'record';
  }

  private async startSystem(): Promise<void> {
    const engine = await speechRecognizer.createEngine({
      language: 'zh-CN',
      online: 1
    });
    this.engine = engine;
    this.sessionId = `asr-${Date.now()}`;
    engine.setListener({
      onStart: (_id: string, _msg: string) => {
      },
      onEvent: (_id: string, _eventCode: number, _eventMessage: string) => {
      },
      onResult: (_id: string, result: speechRecognizer.SpeechRecognitionResult) => {
        const text = result.result ?? '';
        if (result.isLast) {
          this.finals = `${this.finals}${text}`;
          this.onPartial?.(this.finals, true);
        } else {
          this.onPartial?.(`${this.finals}${text}`, false);
        }
      },
      onComplete: (_id: string, _msg: string) => {
      },
      onError: (_id: string, _code: number, message: string) => {
        this.onPartial?.(message, true);
      }
    });
    engine.startListening({
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      }
    });
    await this.startCapturer(true);
  }

  private async startRecordOnly(): Promise<void> {
    await this.startCapturer(false);
  }

  private async startCapturer(feedEngine: boolean): Promise<void> {
    const capturer = await audio.createAudioCapturer({
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    });
    this.capturer = capturer;
    capturer.on('readData', (buffer: ArrayBuffer) => {
      const bytes = new Uint8Array(buffer);
      this.pcmChunks.push(bytes);
      this.pcmBytes += bytes.length;
      if (this.pcmBytes > AsrService.MAX_PCM_BYTES) {
        void this.stopInternal(true);
        return;
      }
      if (feedEngine && this.engine && this.sessionId) {
        this.writeEngine(bytes);
      }
    });
    await capturer.start();
  }

  private writeEngine(bytes: Uint8Array): void {
    const engine = this.engine;
    if (!engine) {
      return;
    }
    const chunkSize = 1280;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      const end = Math.min(offset + chunkSize, bytes.length);
      const slice = bytes.slice(offset, end);
      if (slice.length === 640 || slice.length === 1280) {
        engine.writeAudio(this.sessionId, slice);
      } else if (slice.length > 0) {
        const padded = new Uint8Array(slice.length > 640 ? 1280 : 640);
        padded.set(slice);
        engine.writeAudio(this.sessionId, padded);
      }
    }
  }

  private async stopInternal(upload: boolean): Promise<string> {
    this.running = false;
    try {
      this.capturer?.off('readData');
    } catch (_e) {
    }
    try {
      await this.capturer?.stop();
    } catch (_e) {
    }
    try {
      await this.capturer?.release();
    } catch (_e) {
    }
    this.capturer = undefined;
    if (this.engine && this.sessionId) {
      try {
        this.engine.finish(this.sessionId);
      } catch (_e) {
      }
      try {
        this.engine.shutdown();
      } catch (_e) {
      }
    }
    this.engine = undefined;
    const chunks = this.pcmChunks;
    this.pcmChunks = [];
    if (!upload) {
      return this.finals.trim();
    }
    if (this.mode === 'system') {
      return this.finals.trim();
    }
    if (chunks.length === 0) {
      return this.finals.trim();
    }
    if (!LlmStore.ready()) {
      throw new Error('系统听写不可用。接入通义后可以把录音转成文字。');
    }
    const pcm = concatBytes(chunks);
    const wav = pcm16LeToWav(pcm, 16000);
    const dir = AppContextHolder.filesDir();
    const path = `${dir}/answer.wav`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, wav.buffer.slice(wav.byteOffset, wav.byteOffset + wav.byteLength));
    fs.closeSync(file);
    const spoken = await ApiClient.transcribe(path, LlmStore.settings);
    this.onPartial?.(spoken, true);
    return spoken;
  }

  static async ensureMic(): Promise<boolean> {
    const ctx = AppContextHolder.context;
    if (!ctx) {
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const result = await atManager.requestPermissionsFromUser(ctx, perms);
      return result.authResults[0] === 0;
    } catch (e) {
      throw new Error(errorMessage(e as Object));
    }
  }
}

export const asrService: AsrService = new AsrService();
