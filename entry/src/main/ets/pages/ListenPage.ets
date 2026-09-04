import { AppContextHolder } from '../common/AppContextHolder';
import { Theme } from '../common/AppConfig';
import { errorMessage, shuffleCopy } from '../common/JsonUtil';
import { Question } from '../model/Types';
import { ttsService, TtsEngineKind } from '../speech/TtsService';
import { BankStore } from '../store/BankStore';
import { LlmStore } from '../store/LlmStore';
import { displayQuestionCode, fullAnswerText } from '../utils/QuestionTree';
import { FilterChip } from '../components/FilterChip';

class ListenTrack {
  parentId: string = '';
  topicId: string = '';
  followupId: string = '';
}

const RATES: number[] = [0.85, 1, 1.15, 1.3];
const GAP_MS: number[] = [0, 3000, 8000];
const GAP_LABELS: string[] = ['不停', '停 3 秒', '停 8 秒'];

@Component
export struct ListenPage {
  @State bank: string = 'mixed';
  @State withFollowup: boolean = true;
  @State gapMs: number = 0;
  @State rate: number = 1;
  @State autoNext: boolean = true;
  @State playlist: ListenTrack[] = [];
  @State index: number = 0;
  @State phase: string = 'question';
  @State playing: boolean = false;
  @State chunk: string = '';
  @State error: string = '';
  @State engine: string = '';
  @State cloudModel: string = '';
  @State tick: number = 0;
  private skip: number = 0;
  private unsubs: Array<() => void> = [];

  aboutToAppear(): void {
    this.unsubs.push(LlmStore.subscribe(() => {
      this.tick++;
    }));
    this.unsubs.push(BankStore.subscribe(() => {
      this.tick++;
    }));
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.unsubs.length; i++) {
      this.unsubs[i]();
    }
    this.unsubs = [];
    this.pause();
  }

  private track(): ListenTrack | null {
    return this.playlist.length > 0 ? this.playlist[this.index] : null;
  }

  private parentOf(item: ListenTrack): Question {
    return BankStore.findQuestion(item.parentId);
  }

  private followOf(item: ListenTrack): Question | null {
    if (!item.followupId) {
      return null;
    }
    return BankStore.findQuestion(item.followupId);
  }

  private phaseLabel(): string {
    if (this.phase === 'question') {
      return '面试官正在提问';
    }
    if (this.phase === 'gap') {
      return '你可以先在脑子里过一遍';
    }
    if (this.phase === 'answer') {
      return '正在朗读参考作答';
    }
    if (this.phase === 'followup-q') {
      return '面试官追问';
    }
    return '正在朗读追问作答';
  }

  private nowText(): string {
    const item = this.track();
    if (!item) {
      return '';
    }
    if (this.phase === 'question') {
      return this.parentOf(item).question;
    }
    if (this.phase === 'gap') {
      return '先自己在脑子里答一轮，接着听参考作答。';
    }
    if (this.phase === 'answer') {
      return fullAnswerText(this.parentOf(item));
    }
    const follow = this.followOf(item);
    if (this.phase === 'followup-q') {
      return follow?.question ?? '';
    }
    return follow ? fullAnswerText(follow) : '';
  }

  private buildPlaylist(nextBank: string, nextFollowup: boolean): ListenTrack[] {
    const pool = BankStore.questions.filter((q: Question) => {
      const topic = BankStore.findTopic(q.topicId);
      if (!topic.id) {
        return false;
      }
      if (nextBank !== 'mixed' && topic.bank !== nextBank) {
        return false;
      }
      return q.level === 1;
    });
    const shuffled = shuffleCopy(pool);
    const list: ListenTrack[] = [];
    for (let i = 0; i < shuffled.length; i++) {
      const parent = shuffled[i];
      const item = new ListenTrack();
      item.parentId = parent.id;
      item.topicId = parent.topicId;
      if (nextFollowup && parent.children.length > 0) {
        item.followupId = parent.children[Math.floor(Math.random() * parent.children.length)].id;
      }
      list.push(item);
    }
    return list;
  }

  private start(nextBank: string = this.bank, nextFollowup: boolean = this.withFollowup): void {
    const list = this.buildPlaylist(nextBank, nextFollowup);
    this.bank = nextBank;
    this.withFollowup = nextFollowup;
    this.playlist = list;
    this.index = 0;
    this.phase = 'question';
    void this.playFrom(list, 0, 'question');
  }

  private pause(): void {
    this.skip += 1;
    ttsService.stop();
    this.playing = false;
    this.chunk = '';
    void AppContextHolder.setKeepScreenOn(false);
  }

  private endRound(): void {
    this.pause();
    this.playlist = [];
  }

  private resume(): void {
    if (!this.track()) {
      this.start();
      return;
    }
    void this.playFrom(this.playlist, this.index, this.phase === 'gap' ? 'answer' : this.phase);
  }

  private go(delta: number): void {
    if (!this.playlist.length) {
      return;
    }
    const next = (this.index + delta + this.playlist.length) % this.playlist.length;
    this.index = next;
    this.phase = 'question';
    if (this.playing) {
      void this.playFrom(this.playlist, next, 'question');
    }
  }

  private async waitGap(ms: number, token: number): Promise<string> {
    if (ms <= 0) {
      return 'ok';
    }
    const until = Date.now() + ms;
    while (Date.now() < until) {
      if (this.skip !== token) {
        return 'skipped';
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 200));
    }
    return this.skip === token ? 'ok' : 'skipped';
  }

  private async speak(text: string, role: 'interviewer' | 'coach', token: number): Promise<string> {
    const finished = await ttsService.speak(text, role, this.rate, {
      onChunk: (part: string) => {
        if (this.skip === token) {
          this.chunk = part;
        }
      },
      onEngine: (next: TtsEngineKind) => {
        if (this.skip === token) {
          this.engine = next;
        }
      },
      onCloudModel: (model: string) => {
        if (this.skip === token) {
          this.cloudModel = model;
        }
      },
      onError: (message: string) => {
        if (this.skip === token) {
          this.error = message;
        }
      }
    });
    if (!finished || this.skip !== token) {
      return 'skipped';
    }
    return 'ok';
  }

  private async playFrom(list: ListenTrack[], startIndex: number, startPhase: string): Promise<void> {
    this.skip += 1;
    const token = this.skip;
    ttsService.stop();
    this.playing = true;
    this.error = '';
    this.chunk = '';
    await AppContextHolder.setKeepScreenOn(true);
    let i = startIndex;
    let p = startPhase;
    try {
      while (this.skip === token) {
        const item = list[i];
        if (!item) {
          break;
        }
        this.index = i;
        this.phase = p;
        const parent = this.parentOf(item);
        const follow = this.followOf(item);
        const topic = BankStore.findTopic(item.topicId);
        let result = 'ok';
        if (p === 'question') {
          result = await this.speak(`下一题，${topic.name}。我问你：${parent.question}`, 'interviewer', token);
        } else if (p === 'gap') {
          result = await this.waitGap(this.gapMs, token);
        } else if (p === 'answer') {
          result = await this.speak(`我按面试现场讲一遍。${fullAnswerText(parent)}`, 'coach', token);
        } else if (p === 'followup-q' && follow) {
          result = await this.speak(`我再追一句：${follow.question}`, 'interviewer', token);
        } else if (p === 'followup-a' && follow) {
          result = await this.speak(`可以这样接。${fullAnswerText(follow)}`, 'coach', token);
        }
        if (result === 'skipped' || this.skip !== token) {
          this.playing = false;
          this.chunk = '';
          return;
        }
        let nextPhase = 'done';
        if (p === 'question') {
          nextPhase = this.gapMs > 0 ? 'gap' : 'answer';
        } else if (p === 'gap') {
          nextPhase = 'answer';
        } else if (p === 'answer') {
          nextPhase = item.followupId ? 'followup-q' : 'done';
        } else if (p === 'followup-q') {
          nextPhase = 'followup-a';
        }
        if (nextPhase !== 'done') {
          p = nextPhase;
          continue;
        }
        if (!this.autoNext) {
          this.playing = false;
          this.chunk = '';
          return;
        }
        i = (i + 1) % list.length;
        p = 'question';
      }
    } catch (e) {
      if (this.skip !== token) {
        return;
      }
      this.error = errorMessage(e as Object);
      this.playing = false;
    }
  }

  build() {
    if (this.playlist.length === 0) {
      this.StartPane()
    } else {
      this.PlayPane()
    }
  }

  @Builder
  StartPane() {
    Column({ space: 14 }) {
      Text('边听边记').fontSize(12).fontColor(Theme.accent)
      Text('随机提问，再朗读作答')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
      Text('适合挂着耳机：先听面试官问，再听一段完整口述。接入通义后提问用面试官声，作答用学长声。没填 Key 时走系统朗读。')
        .fontSize(15)
        .lineHeight(24)
        .fontColor(Theme.muted)
      Flex({ wrap: FlexWrap.Wrap }) {
        FilterChip({
          label: '混合',
          active: this.bank === 'mixed',
          onSelect: () => {
            this.bank = 'mixed';
          }
        })
        FilterChip({
          label: '通用口径',
          active: this.bank === 'alibaba',
          onSelect: () => {
            this.bank = 'alibaba';
          }
        })
        FilterChip({
          label: '爱连现网',
          active: this.bank === 'ailian',
          onSelect: () => {
            this.bank = 'ailian';
          }
        })
      }
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.withFollowup })
          .selectedColor(Theme.accent)
          .onChange((v: boolean) => {
            this.withFollowup = v;
          })
        Text('听完父题再随机追问一题').fontSize(13)
      }
      Text(LlmStore.ready()
        ? '已接大模型：提问用面试官声，作答用学长声。可在右上角试听通义语音。'
        : '还没接通义：先用系统朗读。点右上角接入后语气会活很多。')
        .fontSize(13)
        .fontColor(Theme.muted)
        .lineHeight(20)
      Button('开始随机听')
        .backgroundColor(Theme.accent)
        .onClick(() => this.start())
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Theme.paper)
  }

  @Builder
  PlayPane() {
    Column({ space: 14 }) {
      Row() {
        Column() {
          Text('边听边记').fontSize(12).fontColor(Theme.accent)
          Text(`${this.index + 1} / ${this.playlist.length} · ${BankStore.findTopic(this.track()?.topicId ?? '').name}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('结束本轮')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => this.endRound())
      }
      .width('100%')

      Column({ space: 8 }) {
        Text(`${this.track() ? displayQuestionCode(this.parentOf(this.track() as ListenTrack).id) : ''} · ${this.phaseLabel()}${this.engine === 'cloud' ? ` · 通义语音 ${this.cloudModel}` : (this.engine === 'system' ? ' · 系统朗读' : '')}`)
          .fontSize(12)
          .fontColor(Theme.accent)
        Text(this.phase.startsWith('followup')
          ? (this.followOf(this.track() as ListenTrack)?.title ?? '')
          : (this.track() ? this.parentOf(this.track() as ListenTrack).title : ''))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .lineHeight(28)
        Scroll() {
          Text(this.nowText())
            .fontSize(17)
            .lineHeight(28)
        }
        .height(220)
        if (this.chunk && this.playing) {
          Text(`正在读：${this.chunk}`)
            .fontSize(13)
            .lineHeight(20)
            .padding(8)
            .backgroundColor(Theme.accentSoft)
            .borderRadius(8)
        }
        if (this.error) {
          Text(this.error).fontSize(13).fontColor(Theme.danger)
        }
      }
      .width('100%')
      .padding(16)
      .border({ width: 1, color: Theme.line })
      .borderRadius(18)
      .backgroundColor(Theme.card)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 16 }) {
        Button('上一题')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => this.go(-1))
        Button(this.playing ? '暂停' : '继续')
          .backgroundColor(Theme.accent)
          .onClick(() => {
            if (this.playing) {
              this.pause();
            } else {
              this.resume();
            }
          })
        Button('下一题')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => this.go(1))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text('语速').fontSize(12).fontColor(Theme.muted)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(RATES, (value: number) => {
          FilterChip({
            label: `${value}x`,
            active: this.rate === value,
            onSelect: () => {
              this.rate = value;
            }
          })
        }, (value: number) => `${value}`)
      }
      Text('提问后').fontSize(12).fontColor(Theme.muted)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(GAP_MS, (ms: number, i: number) => {
          FilterChip({
            label: GAP_LABELS[i],
            active: this.gapMs === ms,
            onSelect: () => {
              this.gapMs = ms;
            }
          })
        }, (ms: number) => `${ms}`)
      }
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.autoNext })
          .selectedColor(Theme.accent)
          .onChange((v: boolean) => {
            this.autoNext = v;
          })
        Text('听完自动下一题').fontSize(13)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Theme.paper)
  }
}
