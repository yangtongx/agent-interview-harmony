import { Theme } from '../common/AppConfig';
import { errorMessage, joinSpokenText } from '../common/JsonUtil';
import { AnswerBlock, JudgeResult } from '../model/Types';
import { ApiClient } from '../network/ApiClient';
import { asrService } from '../speech/AsrService';
import { BankStore } from '../store/BankStore';
import { LlmStore } from '../store/LlmStore';
import { ProgressStore } from '../store/ProgressStore';

@Component
export struct AnswerCoach {
  @Prop @Watch('onQuestionId') questionId: string = '';
  @Prop topicId: string = '';
  @Prop mode: string = 'bank';
  @Prop @Watch('onPrompt') prompt: string = '';
  @Prop gist: string = '';
  @Prop points: AnswerBlock[] = [];
  @State draft: string = '';
  @State busy: boolean = false;
  @State listening: boolean = false;
  @State notice: string = '';
  @State error: string = '';
  @State result: JudgeResult | null = null;
  @State loadedFor: string = '';
  onDraftChange: (text: string) => void = (_text: string) => {
  };

  aboutToAppear(): void {
    void this.ensureDraft();
  }

  aboutToDisappear(): void {
    if (this.listening) {
      void asrService.stop();
      this.listening = false;
    }
  }

  onQuestionId(): void {
    this.resetCoach();
  }

  onPrompt(): void {
    this.resetCoach();
  }

  private resetCoach(): void {
    this.result = null;
    this.error = '';
    this.notice = '';
    this.listening = false;
    void this.ensureDraft();
  }

  private draftKey(): string {
    return this.mode === 'resume' ? `resume:${this.questionId}` : this.questionId;
  }

  private placeholder(): string {
    if (this.mode === 'resume') {
      return '先讲你本人做了哪一段，再讲怎么验收。';
    }
    const question = BankStore.findQuestion(this.questionId);
    if (question.level === 1) {
      return '点麦克风口述，或自己打字。先给结论，再讲机制、失败和兜底。';
    }
    return '这是追问。口述或补两句就行，要落到字段、数字或失败路径。';
  }

  private async ensureDraft(): Promise<void> {
    const key = this.draftKey();
    if (this.loadedFor === key) {
      return;
    }
    this.draft = await ProgressStore.readDraft(key);
    this.loadedFor = key;
    this.onDraftChange(this.draft);
  }

  private async onDraft(value: string): Promise<void> {
    this.draft = value;
    this.onDraftChange(value);
    await ProgressStore.writeDraft(this.draftKey(), value);
  }

  private async toggleMic(): Promise<void> {
    this.error = '';
    if (this.listening) {
      this.listening = false;
      this.notice = '正在转写…';
      try {
        const extra = await asrService.stop();
        if (extra) {
          await this.onDraft(joinSpokenText(this.draft, extra));
        }
        this.notice = '';
      } catch (e) {
        this.notice = '';
        this.error = errorMessage(e as Object);
      }
      return;
    }
    this.listening = true;
    this.notice = '正在听，再说一次停止';
    try {
      await asrService.start((text: string, isFinal: boolean) => {
        if (isFinal) {
          void this.onDraft(joinSpokenText(this.draft, text));
        } else {
          this.notice = text ? text : '正在听…';
        }
      });
      if (asrService.usingCloudUpload()) {
        this.notice = '正在录音，点停止后发给通义转写';
      }
    } catch (e) {
      this.listening = false;
      this.notice = '';
      this.error = errorMessage(e as Object);
    }
  }

  private async submit(): Promise<void> {
    const userAnswer = this.draft.trim();
    if (!userAnswer) {
      this.error = '先说或写一段你的口述，再让面试官听。';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      if (this.mode === 'resume') {
        const payload: Record<string, Object> = {
          'question': this.prompt,
          'gist': this.gist,
          'points': this.points as Object,
          'topicName': '简历项目'
        };
        this.result = await ApiClient.judgeAnswer(payload, userAnswer, LlmStore.settings);
      } else {
        const question = BankStore.findQuestion(this.questionId);
        const topic = BankStore.findTopic(this.topicId);
        this.result = await ApiClient.judge(question, topic, userAnswer, LlmStore.settings);
      }
    } catch (e) {
      this.result = null;
      this.error = errorMessage(e as Object);
    } finally {
      this.busy = false;
    }
  }

  private verdictColor(): string {
    const v = this.result?.verdict ?? '';
    if (v === '过') {
      return Theme.emerald;
    }
    if (v === '挂') {
      return Theme.danger;
    }
    return Theme.accent;
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('你来答，面试官点评')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
        Blank()
        if (this.result) {
          Text(`${this.result.mode === 'mock' ? '离线规则' : (this.result.model || '大模型')} · ${this.result.verdict} ${this.result.score}/10`)
            .fontSize(11)
            .fontColor(this.verdictColor())
        }
      }
      .width('100%')

      TextArea({
        placeholder: this.placeholder(),
        text: this.draft
      })
        .height(120)
        .backgroundColor(Theme.paper)
        .onChange((v: string) => {
          void this.onDraft(v);
        })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Button(this.listening ? '停止听写' : '麦克风')
          .backgroundColor(this.listening ? Theme.danger : Theme.card)
          .fontColor(this.listening ? Color.White : Theme.ink)
          .enabled(!this.busy)
          .onClick(() => {
            void this.toggleMic();
          })
        Button(this.busy ? '面试官正在听…' : '请面试官点评')
          .backgroundColor(Theme.accent)
          .enabled(!this.busy && !this.listening)
          .margin({ left: 8, top: 6 })
          .onClick(() => {
            void this.submit();
          })
        if (this.draft) {
          Button('清空')
            .backgroundColor(Theme.card)
            .fontColor(Theme.muted)
            .margin({ left: 8, top: 6 })
            .onClick(() => {
              void this.onDraft('');
              this.result = null;
              this.error = '';
            })
        }
      }
      .width('100%')

      if (this.notice) {
        Text(this.notice).fontSize(12).fontColor(Theme.muted)
      }
      if (this.error) {
        Text(this.error).fontSize(13).fontColor(Theme.danger)
      }
      if (this.result) {
        this.JudgeBlock()
      }
    }
    .width('100%')
    .padding(12)
    .border({ width: 1, color: Theme.line })
    .borderRadius(14)
    .backgroundColor(Theme.card)
  }

  @Builder
  JudgeBlock() {
    Column({ space: 8 }) {
      Divider().color(Theme.line)
      Text(this.result?.summary ?? '')
        .fontSize(15)
        .lineHeight(24)
        .fontColor(Theme.ink)
      if ((this.result?.strengths.length ?? 0) > 0) {
        Text('讲对了').fontSize(13).fontColor(Theme.emerald).fontWeight(FontWeight.Medium)
        ForEach(this.result?.strengths ?? [], (item: string) => {
          Text(`· ${item}`).fontSize(13).lineHeight(20).fontColor(Theme.ink)
        }, (item: string) => item)
      }
      if ((this.result?.gaps.length ?? 0) > 0) {
        Text('面试官会追').fontSize(13).fontColor(Theme.accent).fontWeight(FontWeight.Medium)
        ForEach(this.result?.gaps ?? [], (item: string) => {
          Text(`· ${item}`).fontSize(13).lineHeight(20).fontColor(Theme.ink)
        }, (item: string) => item)
      }
      if ((this.result?.redFlagsHit.length ?? 0) > 0) {
        Text('这些说法容易挂').fontSize(13).fontColor(Theme.danger).fontWeight(FontWeight.Medium)
        ForEach(this.result?.redFlagsHit ?? [], (item: string) => {
          Text(`· ${item}`).fontSize(13).lineHeight(20).fontColor(Theme.ink)
        }, (item: string) => item)
      }
      if (this.result?.nextAsk) {
        Text(`下一问：${this.result.nextAsk}`).fontSize(13).lineHeight(20)
      }
      if (this.result?.betterOpening) {
        Column({ space: 4 }) {
          Text('可以这样开口').fontSize(11).fontColor(Theme.muted)
          Text(this.result.betterOpening).fontSize(15).lineHeight(24)
        }
        .width('100%')
        .padding(10)
        .backgroundColor(Theme.paper)
        .borderRadius(10)
      }
      if (this.result?.mode === 'mock') {
        Text('这是没配 Key 时的规则点评。点右上角接入通义后，会按参考口径真评。')
          .fontSize(11)
          .fontColor(Theme.muted)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
