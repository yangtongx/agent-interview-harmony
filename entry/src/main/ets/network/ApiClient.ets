import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppConfig } from '../common/AppConfig';
import { asBool, asRecord, asString } from '../common/JsonUtil';
import { JudgeResult, LlmSettings, Question, Topic } from '../model/Types';
import { parseJudge } from '../model/Parse';
import { fullAnswerText } from '../utils/QuestionTree';

export class ApiClient {
  static baseUrl(): string {
    return AppConfig.currentBase || AppConfig.DEFAULT_BASE;
  }

  static join(path: string): string {
    const root = ApiClient.baseUrl().replace(/\/+$/, '');
    if (path.startsWith('/')) {
      return `${root}${path}`;
    }
    return `${root}/${path}`;
  }

  private static jsonHeaders(): Record<string, string> {
    const header: Record<string, string> = {
      'Accept': 'application/json'
    };
    if (AppConfig.sessionToken) {
      header['Authorization'] = `Bearer ${AppConfig.sessionToken}`;
    }
    return header;
  }

  private static ttsHeaders(): Record<string, string> {
    const header: Record<string, string> = {
      'Accept': '*/*',
      'Content-Type': 'application/json'
    };
    if (AppConfig.sessionToken) {
      header['Authorization'] = `Bearer ${AppConfig.sessionToken}`;
    }
    return header;
  }

  static async getText(path: string): Promise<string> {
    const client = http.createHttp();
    try {
      const res = await client.request(ApiClient.join(path), {
        method: http.RequestMethod.GET,
        header: ApiClient.jsonHeaders(),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AppConfig.CONNECT_TIMEOUT,
        readTimeout: AppConfig.READ_TIMEOUT
      });
      const text = `${res.result ?? ''}`;
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(ApiClient.errorFromBody(text, res.responseCode));
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  static async postJson(path: string, body: Record<string, Object>): Promise<string> {
    return ApiClient.sendJson(http.RequestMethod.POST, path, body);
  }

  static async putJson(path: string, body: Record<string, Object>): Promise<string> {
    return ApiClient.sendJson(http.RequestMethod.PUT, path, body);
  }

  static async patchJson(path: string, body: Record<string, Object>): Promise<string> {
    return ApiClient.sendJson(http.RequestMethod.PUT, path, body);
  }

  private static async sendJson(
    method: http.RequestMethod,
    path: string,
    body: Record<string, Object>
  ): Promise<string> {
    const client = http.createHttp();
    try {
      const header = ApiClient.jsonHeaders();
      header['Content-Type'] = 'application/json';
      const res = await client.request(ApiClient.join(path), {
        method: method,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AppConfig.CONNECT_TIMEOUT,
        readTimeout: AppConfig.READ_TIMEOUT
      });
      const text = `${res.result ?? ''}`;
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(ApiClient.errorFromBody(text, res.responseCode));
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  static async getJudgeConfigured(): Promise<boolean> {
    try {
      const text = await ApiClient.getText('/api/judge');
      const row = asRecord(JSON.parse(text) as Object);
      return asBool(row['serverConfigured']);
    } catch (_e) {
      return false;
    }
  }

  static async fetchBank(): Promise<string> {
    return ApiClient.getText('/api/bank');
  }

  static async judge(question: Question, topic: Topic, userAnswer: string, settings: LlmSettings): Promise<JudgeResult> {
    const payload: Record<string, Object> = {
      'questionId': question.id,
      'question': question.question,
      'topicName': topic.name,
      'bank': topic.bank,
      'gist': question.gist,
      'points': question.points,
      'bonus': question.bonus,
      'redFlags': question.redFlags,
      'fullAnswer': fullAnswerText(question)
    };
    return ApiClient.judgeAnswer(payload, userAnswer, settings);
  }

  static async judgeAnswer(payload: Record<string, Object>, userAnswer: string, settings: LlmSettings): Promise<JudgeResult> {
    const body: Record<string, Object> = {
      'question': payload['question'],
      'gist': payload['gist'],
      'points': payload['points'],
      'topicName': payload['topicName'] ?? '简历项目',
      'bank': payload['bank'] ?? 'alibaba',
      'userAnswer': userAnswer,
      'inputMode': 'text',
      'baseUrl': settings.baseUrl,
      'model': settings.model
    };
    const qid = `${payload['questionId'] ?? ''}`;
    if (qid) {
      body['questionId'] = qid;
    }
    if (payload['bonus'] !== undefined) {
      body['bonus'] = payload['bonus'];
    }
    if (payload['redFlags'] !== undefined) {
      body['redFlags'] = payload['redFlags'];
    }
    if (payload['fullAnswer'] !== undefined) {
      body['fullAnswer'] = payload['fullAnswer'];
    }
    if (settings.apiKey.trim()) {
      body['apiKey'] = settings.apiKey.trim();
    }
    const text = await ApiClient.postJson('/api/judge', body);
    const result = parseJudge(text);
    if (result.error) {
      throw new Error(result.error);
    }
    return result;
  }

  static async uploadResume(filePath: string, mime: string, fileName: string): Promise<string> {
    const client = http.createHttp();
    try {
      const forms: Array<http.MultiFormData> = [
        {
          name: 'file',
          contentType: mime,
          filePath: filePath,
          remoteFileName: fileName
        }
      ];
      const res = await client.request(ApiClient.join('/api/resumes'), {
        method: http.RequestMethod.POST,
        header: ApiClient.jsonHeaders(),
        multiFormDataList: forms,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AppConfig.CONNECT_TIMEOUT,
        readTimeout: AppConfig.READ_TIMEOUT
      });
      const text = `${res.result ?? ''}`;
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(ApiClient.errorFromBody(text, res.responseCode));
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  static async getResumes(): Promise<string> {
    return ApiClient.getText('/api/resumes');
  }

  static async getResume(id: string): Promise<string> {
    return ApiClient.getText(`/api/resumes/${id}`);
  }

  static async putResume(id: string, body: Record<string, Object>): Promise<string> {
    return ApiClient.putJson(`/api/resumes/${id}`, body);
  }

  static async confirmResume(id: string): Promise<string> {
    return ApiClient.postJson(`/api/resumes/${id}/confirm`, {});
  }

  static async createMockSession(resumeId: string, projectId: string): Promise<string> {
    const body: Record<string, Object> = { 'kind': 'resume', 'resumeId': resumeId };
    if (projectId) {
      body['projectId'] = projectId;
    }
    return ApiClient.postJson('/api/mock/sessions', body);
  }

  static async mockTurn(sessionId: string, answerText: string, inputMode: string): Promise<string> {
    const body: Record<string, Object> = {
      'answerText': answerText,
      'inputMode': inputMode
    };
    return ApiClient.postJson(`/api/mock/sessions/${sessionId}/turn`, body);
  }

  static async finishMock(sessionId: string): Promise<string> {
    return ApiClient.postJson(`/api/mock/sessions/${sessionId}/finish`, {});
  }

  static async tts(text: string, role: string, settings: LlmSettings): Promise<TtsBinary> {
    const client = http.createHttp();
    try {
      const body: Record<string, string> = {
        'text': text,
        'role': role,
        'baseUrl': settings.baseUrl,
        'provider': settings.provider
      };
      if (settings.apiKey.trim()) {
        body['apiKey'] = settings.apiKey.trim();
      }
      const res = await client.request(ApiClient.join('/api/tts'), {
        method: http.RequestMethod.POST,
        header: ApiClient.ttsHeaders(),
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: AppConfig.CONNECT_TIMEOUT,
        readTimeout: AppConfig.READ_TIMEOUT
      });
      const mime = ApiClient.headerValue(res, 'content-type').toLowerCase();
      if (mime.includes('application/json')) {
        const raw = bufferToString(res.result as ArrayBuffer);
        throw new Error(ApiClient.errorFromBody(raw, res.responseCode));
      }
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(`语音合成失败 HTTP ${res.responseCode}`);
      }
      const bytes = new Uint8Array(res.result as ArrayBuffer);
      if (bytes.byteLength < 64) {
        throw new Error('语音合成返回的音频是空的。');
      }
      const out = new TtsBinary();
      out.bytes = bytes;
      out.mime = mime ? mime : 'audio/mpeg';
      out.engine = ApiClient.headerValue(res, 'x-tts-engine') || 'qwen-tts';
      return out;
    } finally {
      client.destroy();
    }
  }

  static async transcribe(filePath: string, settings: LlmSettings): Promise<string> {
    const client = http.createHttp();
    try {
      const forms: Array<http.MultiFormData> = [
        {
          name: 'audio',
          contentType: 'audio/wav',
          filePath: filePath,
          remoteFileName: 'answer.wav'
        },
        {
          name: 'mime',
          data: 'audio/wav',
          contentType: 'text/plain'
        },
        {
          name: 'provider',
          data: settings.provider,
          contentType: 'text/plain'
        },
        {
          name: 'baseUrl',
          data: settings.baseUrl,
          contentType: 'text/plain'
        }
      ];
      if (settings.apiKey.trim()) {
        forms.push({
          name: 'apiKey',
          data: settings.apiKey.trim(),
          contentType: 'text/plain'
        });
      }
      const res = await client.request(ApiClient.join('/api/transcribe'), {
        method: http.RequestMethod.POST,
        header: ApiClient.jsonHeaders(),
        multiFormDataList: forms,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AppConfig.CONNECT_TIMEOUT,
        readTimeout: AppConfig.READ_TIMEOUT
      });
      const text = `${res.result ?? ''}`;
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw new Error(ApiClient.errorFromBody(text, res.responseCode));
      }
      const row = asRecord(JSON.parse(text) as Object);
      const err = asString(row['error']);
      if (err) {
        throw new Error(err);
      }
      const spoken = asString(row['text']);
      if (!spoken) {
        throw new Error('没有听出文字。');
      }
      return spoken;
    } finally {
      client.destroy();
    }
  }

  private static headerValue(res: http.HttpResponse, key: string): string {
    const header = res.header as Record<string, string>;
    const keys = Object.keys(header);
    const want = key.toLowerCase();
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === want) {
        return `${header[keys[i]] ?? ''}`;
      }
    }
    return '';
  }

  private static errorFromBody(text: string, status: number): string {
    try {
      const row = asRecord(JSON.parse(text) as Object);
      const err = asString(row['error']);
      if (err && err !== 'cloud-unconfigured') {
        return err;
      }
      if (err === 'cloud-unconfigured') {
        return 'cloud-unconfigured';
      }
    } catch (_e) {
    }
    return `请求失败 HTTP ${status}`;
  }
}

export class TtsBinary {
  bytes: Uint8Array = new Uint8Array();
  mime: string = 'audio/mpeg';
  engine: string = '';
}

function bufferToString(buf: ArrayBuffer): string {
  const decoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(new Uint8Array(buf));
}
