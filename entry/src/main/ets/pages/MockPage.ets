import { Theme } from '../common/AppConfig';
import { asRecord, asString, errorMessage, shuffleCopy } from '../common/JsonUtil';
import { parseMockTurn } from '../model/Parse';
import { AnswerBlock, MockTurn, Question, ResumeProject, Topic } from '../model/Types';
import { ApiClient } from '../network/ApiClient';
import { AnswerCoach } from '../components/AnswerCoach';
import { FilterChip } from '../components/FilterChip';
import { QuestionCard } from '../components/QuestionCard';
import { ResumeArchivePane } from '../components/ResumeArchivePane';
import { AuthStore } from '../store/AuthStore';
import { BankStore } from '../store/BankStore';
import { ProgressStore } from '../store/ProgressStore';
import { ResumeStore } from '../store/ResumeStore';
import { displayQuestionCode } from '../utils/QuestionTree';

@Component
export struct MockPage {
  @State bank: string = 'mixed';
  @State roundIds: string[] = [];
  @State index: number = 0;
  @State currentId: string = '';
  @State finished: boolean = false;
  @State tick: number = 0;
  @State track: string = 'bank';
  @State resumePlaying: boolean = false;
  @State resumeDone: boolean = false;
  @State sessionId: string = '';
  @State turn: MockTurn | null = null;
  @State lastAnswer: string = '';
  @State resumeBusy: boolean = false;
  @State resumeError: string = '';
  @State editingArchive: boolean = false;
  private lastResumeUserId: string = '';
  private unsubs: Array<() => void> = [];

  aboutToAppear(): void {
    this.unsubs.push(ProgressStore.subscribe(() => {
      this.tick++;
    }));
    this.unsubs.push(BankStore.subscribe(() => {
      this.tick++;
    }));
    this.unsubs.push(ResumeStore.subscribe(() => {
      this.tick++;
    }));
    this.lastResumeUserId = AuthStore.user?.id ?? '';
    this.unsubs.push(AuthStore.subscribe(() => {
      this.tick++;
      this.syncResumeForAuth();
    }));
    void ResumeStore.refresh();
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.unsubs.length; i++) {
      this.unsubs[i]();
    }
    this.unsubs = [];
  }

  private syncResumeForAuth(): void {
    const uid = AuthStore.user?.id ?? '';
    if (uid === this.lastResumeUserId) {
      return;
    }
    this.lastResumeUserId = uid;
    if (uid) {
      void ResumeStore.refresh();
      return;
    }
    ResumeStore.clear();
  }

  private start(nextBank: string = this.bank): void {
    this.bank = nextBank;
    const parents = this.pickParents(nextBank);
    this.roundIds = parents.map((q: Question) => q.id);
    this.index = 0;
    this.currentId = this.roundIds[0] ?? '';
    this.finished = false;
  }

  private pickParents(bank: string): Question[] {
    const poolTopics = bank === 'mixed'
      ? BankStore.topics
      : BankStore.topics.filter((topic: Topic) => topic.bank === bank);
    const shuffled = shuffleCopy(poolTopics).slice(0, 5);
    const chosen: Question[] = [];
    for (let i = 0; i < shuffled.length; i++) {
      const topic = shuffled[i];
      const pool = BankStore.questions.filter((q: Question) => q.topicId === topic.id && q.level === 1);
      if (pool.length > 0) {
        chosen.push(pool[Math.floor(Math.random() * pool.length)]);
      }
    }
    return chosen;
  }

  private pickChild(node: Question): Question | null {
    if (node.children.length === 0) {
      return null;
    }
    return node.children[Math.floor(Math.random() * node.children.length)];
  }

  private topicNames(): string {
    const names: string[] = [];
    for (let i = 0; i < this.roundIds.length; i++) {
      const q = BankStore.findQuestion(this.roundIds[i]);
      const topic = BankStore.findTopic(q.topicId);
      if (topic.name) {
        names.push(topic.name);
      }
    }
    return names.join('、');
  }

  private goDeeper(): void {
    const next = this.pickChild(BankStore.findQuestion(this.currentId));
    if (next) {
      this.currentId = next.id;
    }
  }

  private goNextParent(): void {
    if (this.index < this.roundIds.length - 1) {
      this.index++;
      this.currentId = this.roundIds[this.index];
    } else {
      this.finished = true;
    }
  }

  private setTrack(next: string): void {
    this.track = next;
    if (next === 'bank') {
      this.resumePlaying = false;
      this.resumeDone = false;
    }
  }

  private showResumeArchive(): boolean {
    return !ResumeStore.hasConfirmed() || this.editingArchive;
  }

  private resumeProjects(): ResumeProject[] {
    return ResumeStore.archive?.projects ?? [];
  }

  private resumeFullName(): string {
    return ResumeStore.archive?.profile.fullName ?? '';
  }

  private resumeProjectNames(): string {
    const names: string[] = [];
    const projects = this.resumeProjects();
    for (let i = 0; i < projects.length; i++) {
      if (projects[i].name) {
        names.push(projects[i].name);
      }
    }
    return names.join('、');
  }

  private resumePoints(): AnswerBlock[] {
    return this.turn?.points ?? [];
  }

  private resumeProgressText(): string {
    const phase = this.turn?.phase ?? '';
    if (phase === 'project') {
      return `项目深挖 · 第 ${this.turn?.projectIndex ?? 0}/${this.turn?.projectCount ?? 0} 个 · 第 ${this.turn?.questionInProject ?? 0}/3 问`;
    }
    if (phase === 'bank') {
      return '题库补题';
    }
    return '按简历模拟';
  }

  private applyTurn(raw: string): void {
    this.turn = parseMockTurn(JSON.parse(raw) as Object);
    this.resumeDone = (this.turn?.itemKind ?? '') === 'done';
  }

  private async startResume(): Promise<void> {
    const archive = ResumeStore.archive;
    if (!archive) {
      this.resumeError = '没有可开面的档案。';
      return;
    }
    this.resumeBusy = true;
    this.resumeError = '';
    try {
      const sessionText = await ApiClient.createMockSession(archive.id, ResumeStore.selectedProjectId);
      const sessionId = asString(asRecord(JSON.parse(sessionText) as Object)['id']);
      if (!sessionId) {
        throw new Error('开面未返回会话编号。');
      }
      this.sessionId = sessionId;
      const turnText = await ApiClient.mockTurn(sessionId, '', 'text');
      this.applyTurn(turnText);
      this.lastAnswer = '';
      this.resumePlaying = true;
      if (this.resumeDone) {
        try {
          await ApiClient.finishMock(sessionId);
        } catch (_e) {
        }
      }
    } catch (e) {
      this.resumeError = errorMessage(e as Object);
    } finally {
      this.resumeBusy = false;
    }
  }

  private async continueResume(): Promise<void> {
    if (this.turn?.itemKind === 'bank' && this.turn?.questionId) {
      const draft = await ProgressStore.readDraft(this.turn?.questionId ?? '');
      if (draft.trim()) {
        this.lastAnswer = draft;
      }
    }
    const answer = this.lastAnswer.trim();
    if (!answer) {
      this.resumeError = '先答完本题';
      return;
    }
    this.resumeBusy = true;
    this.resumeError = '';
    try {
      const turnText = await ApiClient.mockTurn(this.sessionId, answer, 'text');
      this.applyTurn(turnText);
      this.lastAnswer = '';
      if (this.resumeDone) {
        try {
          await ApiClient.finishMock(this.sessionId);
        } catch (_e) {
        }
      }
    } catch (e) {
      this.resumeError = errorMessage(e as Object);
    } finally {
      this.resumeBusy = false;
    }
  }

  private async abortResume(): Promise<void> {
    const sid = this.sessionId;
    if (sid) {
      try {
        await ApiClient.finishMock(sid);
      } catch (_e) {
      }
    }
    this.resumePlaying = false;
    this.resumeDone = false;
    this.sessionId = '';
    this.turn = null;
    this.lastAnswer = '';
    this.resumeError = '';
  }

  private resetResumeRound(): void {
    this.resumePlaying = false;
    this.resumeDone = false;
    this.sessionId = '';
    this.turn = null;
    this.lastAnswer = '';
    this.resumeError = '';
  }

  build() {
    if (this.resumePlaying && this.resumeDone) {
      this.ResumeDonePane()
    } else if (this.resumePlaying) {
      this.ResumePlayPane()
    } else if (this.roundIds.length === 0) {
      this.StartPane()
    } else if (this.finished) {
      this.DonePane()
    } else {
      this.PlayPane()
    }
  }

  @Builder
  StartPane() {
    Column({ space: 14 }) {
      Text('Agent 面试舱').fontSize(12).fontColor(Theme.accent)
      Text('模拟面试 · 先完整答，再追问')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
      Text(this.track === 'resume'
        ? '用已确认的简历项目开面，再补几道题库。'
        : '抽 5 道互不重复主题的父题。先自己写答案让面试官点评，再随机下探补充追问。')
        .fontSize(15)
        .lineHeight(24)
        .fontColor(Theme.muted)
      Flex({ wrap: FlexWrap.Wrap }) {
        FilterChip({
          label: '普通抽题',
          active: this.track === 'bank',
          onSelect: () => {
            this.setTrack('bank');
          }
        })
        FilterChip({
          label: '按简历',
          active: this.track === 'resume',
          onSelect: () => {
            this.setTrack('resume');
          }
        })
      }
      if (this.track === 'bank') {
        Column({ space: 14 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            FilterChip({
              label: '混合抽题',
              active: this.bank === 'mixed',
              onSelect: () => {
                this.bank = 'mixed';
              }
            })
            FilterChip({
              label: '只抽通用口径',
              active: this.bank === 'alibaba',
              onSelect: () => {
                this.bank = 'alibaba';
              }
            })
            FilterChip({
              label: '只抽爱连现网',
              active: this.bank === 'ailian',
              onSelect: () => {
                this.bank = 'ailian';
              }
            })
          }
          Button('开始本轮')
            .backgroundColor(Theme.accent)
            .onClick(() => this.start())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        this.ResumeStartBody()
      }
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(this.track === 'resume' && AuthStore.user !== null && this.showResumeArchive()
      ? FlexAlign.Start
      : FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Theme.paper)
  }

  @Builder
  ResumeStartBody() {
    Column({ space: 12 }) {
      if (AuthStore.user === null) {
        Text('先到右上角设置完成登录')
          .fontSize(15)
          .lineHeight(24)
          .fontColor(Theme.muted)
      } else if (this.showResumeArchive()) {
        Column({ space: 10 }) {
          if (this.editingArchive && ResumeStore.hasConfirmed()) {
            Button('返回开面')
              .backgroundColor(Theme.card)
              .fontColor(Theme.ink)
              .onClick(() => {
                this.editingArchive = false;
              })
          }
          ResumeArchivePane()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      } else {
        Column({ space: 12 }) {
          Text(this.resumeFullName()
            ? `${this.resumeFullName()} 的档案已确认`
            : '档案已确认')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.ink)
          Text(this.resumeProjects().length > 0
            ? `项目：${this.resumeProjectNames()}`
            : '还没有项目，请先修改档案')
            .fontSize(14)
            .lineHeight(22)
            .fontColor(Theme.muted)
          Text('选择开场项目').fontSize(12).fontColor(Theme.muted)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.resumeProjects(), (project: ResumeProject) => {
              FilterChip({
                label: project.name ? project.name : '未命名项目',
                active: ResumeStore.selectedProjectId === project.id,
                onSelect: () => {
                  ResumeStore.selectedProjectId = project.id;
                  ResumeStore.emit();
                }
              })
            }, (project: ResumeProject) => project.id)
          }
          if (this.resumeError) {
            Text(this.resumeError).fontSize(13).lineHeight(20).fontColor(Theme.danger)
          }
          Button(this.resumeBusy ? '正在开面…' : '用这份开面')
            .backgroundColor(Theme.accent)
            .enabled(!this.resumeBusy && this.resumeProjects().length > 0)
            .onClick(() => {
              void this.startResume();
            })
          Button('修改档案')
            .backgroundColor(Theme.card)
            .fontColor(Theme.ink)
            .enabled(!this.resumeBusy)
            .onClick(() => {
              this.editingArchive = true;
            })
          Button('重新上传')
            .backgroundColor(Theme.card)
            .fontColor(Theme.ink)
            .enabled(!this.resumeBusy)
            .onClick(() => {
              this.editingArchive = true;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .layoutWeight(AuthStore.user !== null && this.showResumeArchive() ? 1 : 0)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ResumePlayPane() {
    Column({ space: 12 }) {
      Row() {
        Column() {
          Text('模拟面试 · 按简历')
            .fontSize(12)
            .fontColor(Theme.muted)
          Text(this.resumeProgressText())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('换一轮')
          .fontSize(12)
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .enabled(!this.resumeBusy)
          .onClick(() => {
            void this.abortResume();
          })
      }
      .width('100%')

      if (this.resumeError) {
        Text(this.resumeError).fontSize(13).lineHeight(20).fontColor(Theme.danger)
      }

      Scroll() {
        Column({ space: 12 }) {
          if (this.turn?.itemKind === 'resume') {
            Column({ space: 12 }) {
              Text(this.turn?.question ?? '')
                .fontSize(16)
                .lineHeight(26)
                .fontColor(Theme.ink)
              AnswerCoach({
                mode: 'resume',
                questionId: this.turn?.resumeQuestionId ?? '',
                prompt: this.turn?.question ?? '',
                gist: this.turn?.gist ?? '',
                points: this.resumePoints(),
                onDraftChange: (text: string) => {
                  this.lastAnswer = text;
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          if (this.turn?.itemKind === 'bank') {
            QuestionCard({
              questionId: this.turn?.questionId ?? '',
              showFollowups: false
            })
          }
          Row({ space: 8 }) {
            Button('换一轮')
              .backgroundColor(Theme.card)
              .fontColor(Theme.ink)
              .enabled(!this.resumeBusy)
              .onClick(() => {
                void this.abortResume();
              })
            Blank()
            Button(this.resumeBusy ? '正在出下一题…' : '继续')
              .backgroundColor(Theme.accent)
              .enabled(!this.resumeBusy)
              .onClick(() => {
                void this.continueResume();
              })
          }
          .width('100%')
        }
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12 })
    .backgroundColor(Theme.paper)
  }

  @Builder
  ResumeDonePane() {
    Column({ space: 14 }) {
      Text('本轮结束').fontSize(12).fontColor(Theme.accent)
      Text('按简历这一轮结束').fontSize(22).fontWeight(FontWeight.Medium)
      Text('回去把没讲完整的项目补上，或再开一轮。')
        .fontSize(15)
        .lineHeight(24)
        .fontColor(Theme.muted)
      Button('再来一轮')
        .backgroundColor(Theme.accent)
        .onClick(() => this.resetResumeRound())
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Theme.paper)
  }

  @Builder
  DonePane() {
    Column({ space: 14 }) {
      Text('本轮结束').fontSize(12).fontColor(Theme.accent)
      Text('五道父题已经过完').fontSize(22).fontWeight(FontWeight.Medium)
      Text(`本轮覆盖：${this.topicNames()}。回去把没讲完整的父题补上，再看补充追问。`)
        .fontSize(15)
        .lineHeight(24)
        .fontColor(Theme.muted)
      Button('再抽一轮')
        .backgroundColor(Theme.accent)
        .onClick(() => this.start())
      Button('返回题库')
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .onClick(() => {
          this.roundIds = [];
          this.finished = false;
        })
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
    Column({ space: 12 }) {
      Row() {
        Column() {
          Text(`模拟面试 · 第 ${this.index + 1} / 5 道父题 · 当前第 ${BankStore.findQuestion(this.currentId).level} 层`)
            .fontSize(12)
            .fontColor(Theme.muted)
          Text(`${displayQuestionCode(this.currentId)} · ${BankStore.findTopic(BankStore.findQuestion(this.currentId).topicId).name}`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('换一轮')
          .fontSize(12)
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .onClick(() => this.start())
      }
      .width('100%')

      Row({ space: 4 }) {
        ForEach(this.roundIds, (id: string, i: number) => {
          Column()
            .height(4)
            .layoutWeight(1)
            .borderRadius(999)
            .backgroundColor(i <= this.index ? Theme.accent : Theme.line)
        }, (id: string) => id)
      }
      .width('100%')

      Text(BankStore.findQuestion(this.currentId).level === 1
        ? '先写下你的口述，让面试官点评。站得住了再往下追。'
        : (BankStore.findQuestion(this.currentId).children.length > 0
          ? '这是补充追问。还可以再追一层。'
          : '这道题的追问到这里。答完去下一道父题。'))
        .fontSize(13)
        .fontColor(Theme.muted)
        .lineHeight(20)

      Scroll() {
        Column({ space: 12 }) {
          QuestionCard({
            questionId: this.currentId,
            showFollowups: false
          })
          Row({ space: 8 }) {
            if (BankStore.findQuestion(this.currentId).children.length > 0) {
              Button('随机追问一层')
                .backgroundColor(Theme.card)
                .fontColor(Theme.ink)
                .onClick(() => this.goDeeper())
            }
            if (this.currentId !== this.roundIds[this.index]) {
              Button('回到父题')
                .backgroundColor(Theme.card)
                .fontColor(Theme.ink)
                .onClick(() => {
                  this.currentId = this.roundIds[this.index];
                })
            }
            Blank()
            Button(this.index < this.roundIds.length - 1 ? '下一道父题' : '结束本轮')
              .backgroundColor(Theme.accent)
              .onClick(() => this.goNextParent())
          }
          .width('100%')
        }
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12 })
    .backgroundColor(Theme.paper)
  }
}
