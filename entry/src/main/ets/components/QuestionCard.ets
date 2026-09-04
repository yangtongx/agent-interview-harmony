import { Theme } from '../common/AppConfig';
import { splitTips } from '../common/JsonUtil';
import { AnswerBlock, Question, Topic } from '../model/Types';
import { ttsService } from '../speech/TtsService';
import { BankStore } from '../store/BankStore';
import { ProgressStore } from '../store/ProgressStore';
import { displayQuestionCode, fullAnswerText, levelChip, levelLabel } from '../utils/QuestionTree';
import { AnswerCoach } from './AnswerCoach';
import { DiffBadge } from './FilterChip';

@Component
export struct QuestionCard {
  @Prop questionId: string = '';
  @Prop showFollowups: boolean = true;
  @Prop defaultOpen: boolean = false;
  @State open: boolean = false;
  @State followupsOpen: boolean = false;
  @State speaking: boolean = false;
  @State inited: boolean = false;

  aboutToAppear(): void {
    if (!this.inited) {
      this.open = this.defaultOpen;
      this.inited = true;
    }
  }

  private question(): Question {
    return BankStore.findQuestion(this.questionId);
  }

  private topic(): Topic {
    return BankStore.findTopic(this.question().topicId);
  }

  private async speakThis(): Promise<void> {
    if (this.speaking) {
      ttsService.stop();
      this.speaking = false;
      return;
    }
    const q = this.question();
    this.speaking = true;
    try {
      await ttsService.speak(`${q.question}\n\n${fullAnswerText(q)}`, 'coach', 1);
    } finally {
      this.speaking = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      this.Header()
      Column({ space: 4 }) {
        Text(levelLabel(this.question().level))
          .fontSize(11)
          .fontColor(Theme.accent)
        Text(this.question().question)
          .fontSize(16)
          .lineHeight(26)
          .fontColor(Theme.ink)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.accentSoft)
      .borderRadius(12)

      AnswerCoach({ questionId: this.questionId, topicId: this.question().topicId })

      Row({ space: 8 }) {
        Button(this.open ? '收起参考答案' : '查看完整作答')
          .layoutWeight(1)
          .backgroundColor(this.question().level === 1 ? Theme.accent : Theme.card)
          .fontColor(this.question().level === 1 ? Color.White : Theme.ink)
          .onClick(() => {
            this.open = !this.open;
          })
        Button(this.speaking ? '停止朗读' : '朗读本题')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => {
            void this.speakThis();
          })
      }
      .width('100%')

      if (this.open) {
        this.AnswerGuide()
      } else {
        Text(this.question().level === 1
          ? '先自己写完再让面试官评。打开参考答案后是「完整作答 + 分步」，追问是补充。'
          : '这是面试官听完完整作答之后才追的。先自己补两句，再对照或继续点评。')
          .fontSize(13)
          .fontColor(Theme.muted)
          .lineHeight(20)
      }

      if (this.showFollowups && this.question().children.length > 0) {
        Button(`${this.followupsOpen ? '收起' : '展开'} ${this.question().children.length} 道${this.question().level === 1 ? '补充追问' : '再追问'}`)
          .width('100%')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => {
            this.followupsOpen = !this.followupsOpen;
          })
        if (this.followupsOpen) {
          Column({ space: 10 }) {
            ForEach(this.question().children, (child: Question) => {
              QuestionCard({
                questionId: child.id,
                showFollowups: this.showFollowups
              })
            }, (child: Question) => child.id)
          }
          .width('100%')
          .padding({ left: 8 })
        }
      }
    }
    .width('100%')
    .padding(14)
    .border({
      width: {
        left: this.question().level === 1 ? 4 : 2,
        right: 1,
        top: 1,
        bottom: 1
      },
      color: {
        left: ProgressStore.has(this.questionId) ? Theme.emerald : Theme.accent,
        right: Theme.line,
        top: Theme.line,
        bottom: Theme.line
      }
    })
    .borderRadius(16)
    .backgroundColor(Theme.card)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Header() {
    Column({ space: 8 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        Text(displayQuestionCode(this.questionId))
          .fontSize(11)
          .fontColor(Theme.accent)
          .fontWeight(FontWeight.Medium)
          .margin({ right: 6, bottom: 4 })
        Text(levelChip(this.question().level))
          .fontSize(11)
          .fontColor(Theme.accent)
          .backgroundColor(Theme.accentSoft)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(999)
          .margin({ right: 6, bottom: 4 })
        if (this.topic().bank === 'ailian') {
          Text('爱连现网')
            .fontSize(11)
            .fontColor(Theme.emerald)
            .margin({ right: 6, bottom: 4 })
        }
        DiffBadge({ difficulty: this.question().difficulty })
        Text(`角度 · ${this.question().angle}`)
          .fontSize(11)
          .fontColor(Theme.muted)
          .margin({ left: 6, bottom: 4 })
      }
      .width('100%')

      Row() {
        Text(this.question().title)
          .fontSize(this.question().level === 1 ? 18 : 16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
          .layoutWeight(1)
        Button(ProgressStore.has(this.questionId) ? '已掌握' : '标为掌握')
          .fontSize(12)
          .height(32)
          .backgroundColor(ProgressStore.has(this.questionId) ? Theme.emeraldSoft : Theme.card)
          .fontColor(ProgressStore.has(this.questionId) ? Theme.emerald : Theme.ink)
          .onClick(() => {
            void ProgressStore.toggle(this.questionId);
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AnswerGuide() {
    Column({ space: 12 }) {
      Text('先把下面这段完整讲完。分步只是对照，补充追问是听完这段之后才问的。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Theme.accent)
        .padding(10)
        .backgroundColor(Theme.accentSoft)
        .borderRadius(10)
        .width('100%')

      Text('1. 完整作答').fontSize(12).fontColor(Theme.muted)
      Column({ space: 6 }) {
        Text('对着讲 2–3 分钟').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.accent)
        Text(fullAnswerText(this.question()))
          .fontSize(15)
          .lineHeight(26)
          .fontColor(Theme.ink)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.paper)
      .borderRadius(12)

      Text('2. 分步对照（面试时不用按标题念）').fontSize(12).fontColor(Theme.muted)
      Column({ space: 8 }) {
        ForEach(this.question().points, (point: AnswerBlock, index: number) => {
          Column({ space: 6 }) {
            Text(`${index + 1}. ${point.heading}`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
            Text(point.body).fontSize(15).lineHeight(24)
          }
          .width('100%')
          .padding(12)
          .border({ width: 1, color: Theme.line })
          .borderRadius(12)
        }, (point: AnswerBlock, index: number) => `${point.heading}-${index}`)
      }

      Column({ space: 4 }) {
        Text('3. 还有时间，再补这句（加分）')
          .fontSize(13)
          .fontColor(Theme.emerald)
          .fontWeight(FontWeight.Medium)
        Text(this.question().bonus).fontSize(15).lineHeight(24)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.emeraldSoft)
      .borderRadius(12)

      Column({ space: 4 }) {
        Text('4. 这些说法容易挂，别往外蹦')
          .fontSize(13)
          .fontColor(Theme.danger)
          .fontWeight(FontWeight.Medium)
        ForEach(splitTips(this.question().redFlags), (tip: string) => {
          Text(`· ${tip}`).fontSize(14).lineHeight(22)
        }, (tip: string) => tip)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.dangerSoft)
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
