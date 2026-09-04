import { Theme } from '../common/AppConfig';
import { errorMessage } from '../common/JsonUtil';
import { ApiClient } from '../network/ApiClient';
import { AuthStore } from '../store/AuthStore';
import { FilterChip } from './FilterChip';

@Component
export struct LoginGate {
  @State mode: string = 'login';
  @State uid: string = '';
  @State password: string = '';
  @State displayName: string = '';
  @State notice: string = '';
  @State busy: boolean = false;

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    const uid = this.uid.trim();
    const password = this.password;
    if (!uid) {
      this.notice = this.mode === 'register' ? '先填一个用户名。' : '先填用户名。';
      return;
    }
    if (password.length < 6) {
      this.notice = '密码至少 6 位。';
      return;
    }
    this.busy = true;
    this.notice = '';
    try {
      if (this.mode === 'register') {
        await AuthStore.register('local', uid, password, this.displayName.trim() || uid);
      } else {
        await AuthStore.login('local', uid, password);
      }
      this.password = '';
    } catch (e) {
      this.notice = errorMessage(e as Object);
    } finally {
      this.busy = false;
    }
  }

  private async skip(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.notice = '';
    try {
      await AuthStore.deviceLogin('unset');
    } catch (e) {
      this.notice = errorMessage(e as Object);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        Text('Agent 面试舱')
          .fontSize(12)
          .fontColor(Theme.accent)
        Text(this.mode === 'register' ? '注册账号' : '登录后继续')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
        Text('登录后进度可以和网页同步。想先看题，也可以跳过，用这台手机的访客进度。')
          .fontSize(14)
          .fontColor(Theme.muted)
          .lineHeight(22)
        Text(`当前站点 ${ApiClient.baseUrl()}`)
          .fontSize(12)
          .fontColor(Theme.muted)
          .lineHeight(18)

        Flex({ wrap: FlexWrap.Wrap }) {
          FilterChip({
            label: '登录',
            active: this.mode === 'login',
            onSelect: () => {
              this.mode = 'login';
              this.notice = '';
            }
          })
          FilterChip({
            label: '注册',
            active: this.mode === 'register',
            onSelect: () => {
              this.mode = 'register';
              this.notice = '';
            }
          })
        }
        .width('100%')

        TextInput({ placeholder: '用户名', text: this.uid })
          .width('100%')
          .backgroundColor(Theme.card)
          .onChange((v: string) => {
            this.uid = v;
          })
        TextInput({ placeholder: '密码至少 6 位', text: this.password })
          .width('100%')
          .backgroundColor(Theme.card)
          .type(InputType.Password)
          .onChange((v: string) => {
            this.password = v;
          })
        if (this.mode === 'register') {
          TextInput({ placeholder: '显示名（可留空）', text: this.displayName })
            .width('100%')
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              this.displayName = v;
            })
        }

        if (this.notice) {
          Text(this.notice)
            .fontSize(13)
            .fontColor(Theme.danger)
            .lineHeight(20)
            .width('100%')
        }

        Button(this.busy ? '请稍等…' : (this.mode === 'register' ? '注册并进入' : '登录'))
          .width('100%')
          .backgroundColor(Theme.accent)
          .enabled(!this.busy)
          .onClick(() => {
            void this.submit();
          })
        Button('跳过登录，先看题')
          .width('100%')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .enabled(!this.busy)
          .onClick(() => {
            void this.skip();
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
    }
    .width('100%')
    .height('100%')
    .padding(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Theme.paper)
  }
}
