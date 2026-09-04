import { Theme } from '../common/AppConfig';
import { asrService } from '../speech/AsrService';
import { ttsService } from '../speech/TtsService';
import { AuthStore } from '../store/AuthStore';
import { BankStore } from '../store/BankStore';
import { HomeStore } from '../store/HomeStore';
import { LlmStore } from '../store/LlmStore';
import { ProgressStore } from '../store/ProgressStore';
import { ResumeStore } from '../store/ResumeStore';
import { SettingsPanel } from '../components/SettingsPanel';
import { BankPage } from './BankPage';
import { ListenPage } from './ListenPage';
import { MockPage } from './MockPage';

@Entry
@Component
struct Index {
  @State selectedTab: number = 0;
  @State showSettings: boolean = false;
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
    this.unsubs.push(AuthStore.subscribe(() => {
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
    ttsService.stop();
    void asrService.stop();
  }

  build() {
    Stack() {
      Column() {
        this.Header()
        if (BankStore.loading && BankStore.topics.length === 0) {
          Column({ space: 8 }) {
            LoadingProgress().color(Theme.accent).width(36)
            Text('正在从服务器加载题目…').fontSize(14).fontColor(Theme.muted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (BankStore.error && BankStore.topics.length === 0) {
          Column({ space: 12 }) {
            Text('服务器上的题目没读到')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
            Text(BankStore.error)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(Theme.muted)
            Button('再试一次')
              .backgroundColor(Theme.accent)
              .onClick(() => {
                void BankStore.load();
              })
          }
          .width('100%')
          .padding(24)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (BankStore.fromCache) {
            Text('当前用的是上次缓存的题库。连上网后点右上角刷新。')
              .fontSize(12)
              .fontColor(Theme.accent)
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          }
          Tabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
            TabContent() {
              BankPage()
            }
            .tabBar(this.TabItem('题库', this.selectedTab === 0))

            TabContent() {
              MockPage()
            }
            .tabBar(this.TabItem('模拟', this.selectedTab === 1))

            TabContent() {
              ListenPage()
            }
            .tabBar(this.TabItem('听记', this.selectedTab === 2))
          }
          .barMode(BarMode.Fixed)
          .barHeight(56)
          .barBackgroundColor(Theme.card)
          .onChange((i: number) => {
            this.selectedTab = i;
            ttsService.stop();
            void asrService.stop();
          })
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.paper)

      if (AuthStore.needsAudience()) {
        this.AudienceMask()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSettings, this.SettingsBuilder(), {
      height: SheetSize.LARGE,
      dragBar: true,
      title: { title: '设置' }
    })
  }

  @Builder
  AudienceMask() {
    Column({ space: 12 }) {
      Text('选一条路线')
        .fontSize(12)
        .fontColor(Theme.accent)
      Text('你现在更像哪一种准备状态？')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.ink)
      Text('题库是同一套。路线只决定先练哪一章。')
        .fontSize(14)
        .fontColor(Theme.muted)
        .lineHeight(22)
      Button('Java 转 Agent')
        .backgroundColor(Theme.accent)
        .onClick(() => {
          void AuthStore.setAudience('transition');
        })
      Button('已有 Agent 项目经验')
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .onClick(() => {
          void AuthStore.setAudience('experienced');
        })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#E6F6F0E6')
  }

  @Builder
  Header() {
    Row() {
      Column() {
        Text('Agent 面试舱 · Java 转 Agent')
          .fontSize(11)
          .fontColor(Theme.accent)
        Text('Agent 专项 · 完整作答 + 追问')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button('设置')
        .height(32)
        .fontSize(12)
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .onClick(() => {
          this.showSettings = true;
        })
      Button('刷新')
        .height(32)
        .fontSize(12)
        .margin({ left: 8 })
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .onClick(() => {
          void BankStore.load();
          void LlmStore.refreshServer();
          void HomeStore.load(AuthStore.user?.audience ?? '');
          void ResumeStore.refresh();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: Theme.line })
  }

  @Builder
  TabItem(title: string, selected: boolean) {
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor(selected ? Theme.accent : Theme.muted)
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  SettingsBuilder() {
    SettingsPanel()
  }
}
