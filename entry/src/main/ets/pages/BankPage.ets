import { Theme } from '../common/AppConfig';
import { FilterChip } from '../components/FilterChip';
import { QuestionCard } from '../components/QuestionCard';
import { DIFFICULTIES, Question, Topic } from '../model/Types';
import { BankStore } from '../store/BankStore';
import { HomeStore } from '../store/HomeStore';
import { LlmStore } from '../store/LlmStore';
import { ProgressStore } from '../store/ProgressStore';
import { countQuestions, treeMatches } from '../utils/QuestionTree';

@Component
export struct BankPage {
  @State bank: string = 'all';
  @State topicId: string = 'all';
  @State query: string = '';
  @State difficulty: string = '全部';
  @State onlyTodo: boolean = false;
  @State introOpen: boolean = false;
  @State tick: number = 0;
  private unsubs: Array<() => void> = [];

  aboutToAppear(): void {
    this.unsubs.push(BankStore.subscribe(() => {
      this.tick++;
    }));
    this.unsubs.push(ProgressStore.subscribe(() => {
      this.tick++;
    }));
    this.unsubs.push(LlmStore.subscribe(() => {
      this.tick++;
    }));
    this.unsubs.push(HomeStore.subscribe(() => {
      this.tick++;
    }));
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.unsubs.length; i++) {
      this.unsubs[i]();
    }
    this.unsubs = [];
  }

  private visibleTopics(): Topic[] {
    if (this.bank === 'all') {
      return BankStore.topics;
    }
    return BankStore.topics.filter((t: Topic) => t.bank === this.bank);
  }

  private filtered(): Question[] {
    const q = this.query.trim().toLowerCase();
    return BankStore.questions.filter((item: Question) => {
      const topic = BankStore.findTopic(item.topicId);
      if (!topic.id) {
        return false;
      }
      if (this.topicId !== 'all' && item.topicId !== this.topicId) {
        return false;
      }
      if (this.topicId === 'all' && this.bank !== 'all' && topic.bank !== this.bank) {
        return false;
      }
      if (this.difficulty !== '全部' && item.difficulty !== this.difficulty) {
        return false;
      }
      return treeMatches(item, q, this.onlyTodo, ProgressStore.ids);
    });
  }

  private showCatalog(): boolean {
    return this.topicId === 'all' && !this.query.trim() && this.difficulty === '全部' && !this.onlyTodo;
  }

  private javaTopics(): Topic[] {
    return this.showCatalog() ? this.visibleTopics().filter((t: Topic) => t.id === 'java-agent') : [];
  }

  private alibabaTopics(): Topic[] {
    return this.showCatalog() ?
      this.visibleTopics().filter((t: Topic) => t.bank === 'alibaba' && t.id !== 'java-agent') : [];
  }

  private ailianTopics(): Topic[] {
    return this.showCatalog() ? this.visibleTopics().filter((t: Topic) => t.bank === 'ailian') : [];
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        this.Intro()
        if (this.showCatalog()) {
          this.HomeStrip()
        }
        this.Filters()
        if (this.showCatalog()) {
          this.Catalog()
        } else if (this.filtered().length === 0) {
          Column({ space: 8 }) {
            Text('没有匹配的题目').fontSize(16).fontWeight(FontWeight.Medium)
            Text('试试更短的关键词，或清掉难度和主题筛选。').fontSize(13).fontColor(Theme.muted)
            Button('重置筛选')
              .backgroundColor(Theme.card)
              .fontColor(Theme.ink)
              .onClick(() => {
                this.query = '';
                this.difficulty = '全部';
                this.onlyTodo = false;
                this.topicId = 'all';
              })
          }
          .width('100%')
          .padding(24)
          .border({ width: 1, color: Theme.line, style: BorderStyle.Dashed })
          .borderRadius(16)
        } else {
          Column({ space: 12 }) {
            ForEach(this.filtered(), (item: Question) => {
              QuestionCard({ questionId: item.id, showFollowups: true })
            }, (item: Question) => `${item.id}-${this.tick}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 32 })
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.paper)
  }

  @Builder
  Intro() {
    Column({ space: 8 }) {
      if (this.topicId !== 'all') {
        Text(`${BankStore.findTopic(this.topicId).bank === 'ailian' ? '爱连健康现网' : '通用口径'} · ${BankStore.findTopic(this.topicId).english}`)
          .fontSize(12)
          .fontColor(Theme.muted)
        Text(BankStore.findTopic(this.topicId).name)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
        Text(BankStore.findTopic(this.topicId).summary)
          .fontSize(15)
          .lineHeight(24)
        Text(BankStore.findTopic(this.topicId).interviewerNote)
          .fontSize(13)
          .lineHeight(20)
          .fontColor(Theme.muted)
          .border({ width: { left: 2 }, color: Theme.accent })
          .padding({ left: 10 })
        Button('返回全部主题')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => {
            this.topicId = 'all';
          })
      } else {
        Text('先完整答完，再看追问')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
        Text(BankStore.candidate?.oneLiner ||
          '按 Java 转 Agent 来练：把不确定的生成收进可运营的系统。通用口径已按这个背景改过问法。')
          .fontSize(15)
          .lineHeight(24)
          .fontColor(Theme.ink)
        Text(LlmStore.ready()
          ? '点评走大模型。参考口径只给面试官看，不会先弹给你。'
          : '还没填 API Key：现在是离线规则点评。点右上角接入大模型换成真面试官。')
          .fontSize(13)
          .fontColor(Theme.muted)
          .lineHeight(20)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HomeStrip() {
    if (HomeStore.home && HomeStore.home.pathName) {
      Column({ space: 8 }) {
        Text(HomeStore.home.pathName).fontSize(12).fontColor(Theme.accent).fontWeight(FontWeight.Medium)
        Text(HomeStore.home.pathSummary).fontSize(13).lineHeight(20).fontColor(Theme.muted)
        Text(`本路线已掌握 ${HomeStore.home.doneOnPath}/${HomeStore.home.onPath} 道核心题`)
          .fontSize(13)
        if (HomeStore.home.next) {
          Column({ space: 4 }) {
            Text(`${HomeStore.home.next.reason} · ${HomeStore.home.next.topicName}`)
              .fontSize(11)
              .fontColor(Theme.muted)
            Text(HomeStore.home.next.title).fontSize(16).fontWeight(FontWeight.Medium)
            Text(HomeStore.home.next.question)
              .fontSize(13)
              .fontColor(Theme.muted)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(Theme.paper)
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => {
            const next = HomeStore.home?.next;
            if (next) {
              this.topicId = next.topicId;
            }
          })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.accentSoft)
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  Filters() {
    Column({ space: 10 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        FilterChip({
          label: '全部题库',
          active: this.bank === 'all' && this.topicId === 'all',
          onSelect: () => {
            this.bank = 'all';
            this.topicId = 'all';
          }
        })
        FilterChip({
          label: `通用口径 · ${BankStore.stats.alibabaParents} 父题`,
          active: this.bank === 'alibaba' && this.topicId === 'all',
          onSelect: () => {
            this.bank = 'alibaba';
            this.topicId = 'all';
          }
        })
        FilterChip({
          label: `爱连现网 · ${BankStore.stats.ailianParents} 父题`,
          active: this.bank === 'ailian' && this.topicId === 'all',
          onSelect: () => {
            this.bank = 'ailian';
            this.topicId = 'all';
          }
        })
      }

      TextInput({ placeholder: '搜索题干、完整作答或关键词', text: this.query })
        .onChange((v: string) => {
          this.query = v;
        })

      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.onlyTodo })
          .selectedColor(Theme.accent)
          .onChange((v: boolean) => {
            this.onlyTodo = v;
          })
        Text('只看未掌握').fontSize(13).fontColor(Theme.ink)
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(DIFFICULTIES, (item: string) => {
          FilterChip({
            label: item === '全部' ? '全部难度' : item,
            active: this.difficulty === item,
            onSelect: () => {
              this.difficulty = item;
            }
          })
        }, (item: string) => item)
      }

      Text(this.summaryLine())
        .fontSize(12)
        .fontColor(Theme.muted)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private summaryLine(): string {
    if (this.showCatalog()) {
      const mastered = ProgressStore.ids.length > 0
        ? ` · 已掌握 ${ProgressStore.ids.length}/${BankStore.stats.totalQuestions}`
        : '';
      return `通用 ${BankStore.stats.alibabaParents} 道 + 爱连 ${BankStore.stats.ailianParents} 道 · ${BankStore.stats.totalParents} 道核心题 + ${BankStore.stats.totalQuestions - BankStore.stats.totalParents} 道分层追问${mastered}`;
    }
    const list = this.filtered();
    let follow = 0;
    for (let i = 0; i < list.length; i++) {
      follow += countQuestions([list[i]]) - 1;
    }
    return `当前 ${list.length} 道核心题 · ${follow} 道追问`;
  }

  @Builder
  Catalog() {
    Column({ space: 18 }) {
      if (this.javaTopics().length > 0) {
        Text('Java 转 Agent · 转岗专题').fontSize(13).fontColor(Theme.accent).fontWeight(FontWeight.Medium)
        Text(BankStore.candidate?.interviewerFrame ||
          '面试官会按 Java 转岗来问：事务、幂等、鉴权还在不在，会不会把 Agent 做成 Controller 调 LLM。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor(Theme.muted)
        this.TopicGrid(this.javaTopics())
      }
      if (this.alibabaTopics().length > 0) {
        Text('通用口径 · 阿里面试官').fontSize(13).fontColor(Theme.muted).fontWeight(FontWeight.Medium)
        this.TopicGrid(this.alibabaTopics())
      }
      if (this.ailianTopics().length > 0) {
        Text('爱连健康 · 现网多 Agent').fontSize(13).fontColor(Theme.muted).fontWeight(FontWeight.Medium)
        Column({ space: 8 }) {
          Text(`${BankStore.ailianIntro.title} · ${BankStore.ailianIntro.candidate}`)
            .fontSize(12)
            .fontColor(Theme.emerald)
          Text(this.introOpen ? BankStore.ailianIntro.body : BankStore.ailianIntro.body.split('\n')[0])
            .fontSize(13)
            .lineHeight(22)
          Button(this.introOpen ? '收起自我介绍' : '展开一分钟自我介绍')
            .backgroundColor(Theme.card)
            .fontColor(Theme.ink)
            .onClick(() => {
              this.introOpen = !this.introOpen;
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(Theme.emeraldSoft)
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start)
        this.TopicGrid(this.ailianTopics())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TopicGrid(topics: Topic[]) {
    Column({ space: 10 }) {
      ForEach(topics, (topic: Topic) => {
        Column({ space: 6 }) {
          Text(`${String(topic.index).padStart(2, '0')} · ${topic.english}`)
            .fontSize(11)
            .fontColor(Theme.accent)
          Text(topic.name).fontSize(16).fontWeight(FontWeight.Medium)
          Text(topic.summary)
            .fontSize(13)
            .fontColor(Theme.muted)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(14)
        .border({ width: 1, color: Theme.line })
        .borderRadius(14)
        .backgroundColor(Theme.card)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.topicId = topic.id;
          this.bank = topic.bank;
        })
      }, (topic: Topic) => topic.id)
    }
    .width('100%')
  }
}
