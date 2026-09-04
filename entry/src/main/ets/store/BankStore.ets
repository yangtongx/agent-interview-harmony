import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../common/AppConfig';
import { AppContextHolder } from '../common/AppContextHolder';
import { Emitter } from '../common/Emitter';
import { errorMessage } from '../common/JsonUtil';
import { parseBank } from '../model/Parse';
import { AilianIntro, BankStats, CandidateProfile, Question, Topic } from '../model/Types';
import { ApiClient } from '../network/ApiClient';
import { flattenQuestions } from '../utils/QuestionTree';

export class BankStore {
  static loading: boolean = true;
  static error: string = '';
  static fromCache: boolean = false;
  static topics: Topic[] = [];
  static questions: Question[] = [];
  static ailianIntro: AilianIntro = new AilianIntro();
  static candidate: CandidateProfile | null = null;
  static stats: BankStats = new BankStats();
  static byId: Map<string, Question> = new Map();
  static topicById: Map<string, Topic> = new Map();
  private static bus: Emitter = new Emitter();

  static subscribe(fn: () => void): () => void {
    return BankStore.bus.subscribe(fn);
  }

  static emit(): void {
    BankStore.bus.emit();
  }

  static findQuestion(id: string): Question {
    return BankStore.byId.get(id) ?? new Question();
  }

  static findTopic(id: string): Topic {
    return BankStore.topicById.get(id) ?? new Topic();
  }

  private static inflight: Promise<void> | null = null;

  static async load(): Promise<void> {
    if (BankStore.inflight) {
      await BankStore.inflight;
      return;
    }
    BankStore.inflight = BankStore.loadInner();
    try {
      await BankStore.inflight;
    } finally {
      BankStore.inflight = null;
    }
  }

  private static async loadInner(): Promise<void> {
    BankStore.loading = true;
    BankStore.error = '';
    BankStore.emit();
    try {
      const text = await ApiClient.fetchBank();
      BankStore.applyJson(text, false);
      await BankStore.writeCache(text);
    } catch (e) {
      const cached = await BankStore.readCache();
      if (cached) {
        try {
          BankStore.applyJson(cached, true);
          BankStore.error = '';
          return;
        } catch (err) {
          hilog.error(0x0000, 'Interview', 'bank cache parse %{public}s', (err as Error).message);
        }
      }
      BankStore.error = errorMessage(e as Object);
    } finally {
      BankStore.loading = false;
      BankStore.emit();
    }
  }

  private static applyJson(text: string, cached: boolean): void {
    const parsed = parseBank(text);
    BankStore.topics = parsed.topics;
    BankStore.questions = parsed.questions;
    BankStore.ailianIntro = parsed.ailianIntro;
    BankStore.candidate = parsed.candidate;
    BankStore.stats = parsed.stats;
    BankStore.fromCache = cached;
    BankStore.byId = new Map();
    BankStore.topicById = new Map();
    const all = flattenQuestions(parsed.questions);
    for (let i = 0; i < all.length; i++) {
      BankStore.byId.set(all[i].id, all[i]);
    }
    for (let i = 0; i < parsed.topics.length; i++) {
      BankStore.topicById.set(parsed.topics[i].id, parsed.topics[i]);
    }
  }

  private static cachePath(): string {
    const dir = AppContextHolder.filesDir();
    if (!dir) {
      return '';
    }
    return `${dir}/${AppConfig.BANK_CACHE}`;
  }

  private static async writeCache(text: string): Promise<void> {
    const path = BankStore.cachePath();
    if (!path) {
      return;
    }
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'bank cache write %{public}s', (e as Error).message);
    }
  }

  private static async readCache(): Promise<string> {
    const path = BankStore.cachePath();
    if (!path) {
      return '';
    }
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (_e) {
      return '';
    }
  }
}
