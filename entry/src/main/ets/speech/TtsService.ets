import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { AppConfig } from '../common/AppConfig';
import { AppContextHolder } from '../common/AppContextHolder';
import { errorMessage } from '../common/JsonUtil';
import { ApiClient } from '../network/ApiClient';
import { LlmStore } from '../store/LlmStore';
import { splitForSpeech } from '../utils/QuestionTree';

export type SpeakRole = 'interviewer' | 'coach';
export type TtsEngineKind = 'cloud' | 'system' | '';

export interface SpeakCallbacks {
  onChunk?: (text: string) => void;
  onEngine?: (engine: TtsEngineKind) => void;
  onCloudModel?: (model: string) => void;
  onError?: (message: string) => void;
}

export class TtsService {
  private stopped: boolean = false;
  private token: number = 0;
  private player: media.AVPlayer | undefined = undefined;
  private sysEngine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private sysResolve: (() => void) | undefined = undefined;
  private sysReject: ((e: Error) => void) | undefined = undefined;

  stop(): void {
    this.stopped = true;
    this.token += 1;
    this.releasePlayer();
    try {
      this.sysEngine?.stop();
    } catch (_e) {
    }
    if (this.sysResolve) {
      this.sysResolve();
      this.sysResolve = undefined;
      this.sysReject = undefined;
    }
  }

  async speak(text: string, role: SpeakRole, rate: number, cb: SpeakCallbacks = {}, allowSystemFallback: boolean = true): Promise<boolean> {
    this.stopped = false;
    const myToken = ++this.token;
    const settings = LlmStore.settings;
    const canCloud = settings.provider !== 'deepseek' &&
      (settings.apiKey.trim().length > 0 || LlmStore.serverConfigured);
    if (canCloud) {
      cb.onEngine?.('cloud');
      try {
        await this.speakCloud(text, role, rate, cb, myToken);
        return !this.stopped && myToken === this.token;
      } catch (e) {
        if (this.stopped || myToken !== this.token) {
          return false;
        }
        const message = errorMessage(e as Object);
        cb.onError?.(message);
        if (!allowSystemFallback) {
          throw e instanceof Error ? e : new Error(message);
        }
        cb.onEngine?.('system');
      }
    } else {
      cb.onEngine?.('system');
    }
    if (this.stopped || myToken !== this.token) {
      return false;
    }
    await this.speakSystem(text, role, rate, cb, myToken);
    return !this.stopped && myToken === this.token;
  }

  private async speakCloud(text: string, role: SpeakRole, rate: number, cb: SpeakCallbacks, myToken: number): Promise<void> {
    const chunks = splitForSpeech(text, AppConfig.MAX_TTS_CHARS - 20);
    for (let i = 0; i < chunks.length; i++) {
      if (this.stopped || myToken !== this.token) {
        return;
      }
      const piece = chunks[i];
      cb.onChunk?.(piece);
      const binary = await ApiClient.tts(piece, role, LlmStore.settings);
      if (this.stopped || myToken !== this.token) {
        return;
      }
      cb.onCloudModel?.(binary.engine);
      await this.playBytes(binary.bytes, rate, myToken);
    }
  }

  private async playBytes(bytes: Uint8Array, rate: number, myToken: number): Promise<void> {
    const dir = AppContextHolder.filesDir();
    if (!dir) {
      throw new Error('无法写入语音文件');
    }
    const path = `${dir}/tts-chunk.mp3`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    fs.closeSync(file);
    await this.playPath(path, rate, myToken);
  }

  private playbackSpeed(rate: number): media.PlaybackSpeed {
    if (rate <= 0.9) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    }
    if (rate <= 1.05) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
    if (rate <= 1.2) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    }
    return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
  }

  private async playPath(path: string, rate: number, myToken: number): Promise<void> {
    this.releasePlayer();
    const player = await media.createAVPlayer();
    this.player = player;
    const uri = fileUri.getUriFromPath(path);
    await new Promise<void>((resolve, reject) => {
      player.on('stateChange', (state: string) => {
        if (this.stopped || myToken !== this.token) {
          resolve();
          return;
        }
        if (state === 'initialized') {
          player.prepare();
        } else if (state === 'prepared') {
          try {
            player.setSpeed(this.playbackSpeed(rate));
          } catch (_e) {
          }
          player.play();
        } else if (state === 'completed' || state === 'stopped') {
          resolve();
        } else if (state === 'error') {
          reject(new Error('音频播放失败'));
        }
      });
      player.on('error', () => {
        reject(new Error('音频播放失败'));
      });
      player.url = uri;
    });
  }

  private releasePlayer(): void {
    const player = this.player;
    this.player = undefined;
    if (!player) {
      return;
    }
    try {
      player.stop();
    } catch (_e) {
    }
    try {
      player.release();
    } catch (_e) {
    }
  }

  private async ensureSysEngine(): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.sysEngine) {
      return this.sysEngine;
    }
    const engine = await textToSpeech.createEngine({
      language: 'zh-CN',
      person: 0,
      online: 1
    });
    engine.setListener({
      onStart: (_id: string, _res: textToSpeech.StartResponse) => {
      },
      onComplete: (_id: string, _res: textToSpeech.CompleteResponse) => {
        if (this.sysResolve) {
          this.sysResolve();
        }
        this.sysResolve = undefined;
        this.sysReject = undefined;
      },
      onStop: (_id: string, _res: textToSpeech.StopResponse) => {
        if (this.sysResolve) {
          this.sysResolve();
        }
        this.sysResolve = undefined;
        this.sysReject = undefined;
      },
      onError: (_id: string, _errorCode: number, errorMessage: string) => {
        const err = new Error(errorMessage || '系统朗读失败');
        if (this.sysReject) {
          this.sysReject(err);
        }
        this.sysResolve = undefined;
        this.sysReject = undefined;
      }
    });
    this.sysEngine = engine;
    return engine;
  }

  private async speakSystem(text: string, _role: SpeakRole, _rate: number, cb: SpeakCallbacks, myToken: number): Promise<void> {
    const chunks = splitForSpeech(text, 180);
    const engine = await this.ensureSysEngine();
    for (let i = 0; i < chunks.length; i++) {
      if (this.stopped || myToken !== this.token) {
        return;
      }
      const piece = chunks[i];
      cb.onChunk?.(piece);
      await new Promise<void>((resolve, reject) => {
        this.sysResolve = resolve;
        this.sysReject = reject;
        try {
          engine.speak(piece, {
            requestId: `tts-${myToken}-${i}`
          });
        } catch (e) {
          reject(e instanceof Error ? e : new Error(errorMessage(e as Object)));
        }
      });
    }
  }
}

export const ttsService: TtsService = new TtsService();
