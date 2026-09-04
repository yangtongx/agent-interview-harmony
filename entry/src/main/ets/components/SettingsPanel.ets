import { AppConfig, Theme } from '../common/AppConfig';
import { BuildFlags } from '../common/BuildFlags';
import { errorMessage } from '../common/JsonUtil';
import { DEEPSEEK_PRESET, LlmSettings, OPENAI_PRESET, ProviderPreset, QWEN_PRESET, presetFor } from '../model/Types';
import { ttsService } from '../speech/TtsService';
import { AuthStore } from '../store/AuthStore';
import { LlmStore } from '../store/LlmStore';
import { FilterChip } from './FilterChip';

@Component
export struct SettingsPanel {
  @State provider: string = LlmStore.settings.provider;
  @State apiKey: string = LlmStore.settings.apiKey;
  @State modelUrl: string = LlmStore.settings.baseUrl;
  @State model: string = LlmStore.settings.model;
  @State siteBase: string = LlmStore.apiBase;
  @State probe: string = '';
  @State busy: boolean = false;
  @State uid: string = '';
  @State password: string = '';
  @State displayName: string = AuthStore.user?.displayName ?? '';
  @State authProvider: string = 'local';
  @State authNotice: string = '';
  @State tick: number = 0;
  private unsub: () => void = () => {
  };

  aboutToAppear(): void {
    this.syncFromStore();
    this.unsub = AuthStore.subscribe(() => {
      this.tick++;
      this.displayName = AuthStore.user?.displayName ?? '';
    });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  private syncFromStore(): void {
    this.provider = LlmStore.settings.provider;
    this.apiKey = LlmStore.settings.apiKey;
    this.modelUrl = LlmStore.settings.baseUrl;
    this.model = LlmStore.settings.model;
    this.siteBase = LlmStore.apiBase;
  }

  private applyProvider(id: string): void {
    this.provider = id;
    const preset: ProviderPreset | null = presetFor(id);
    if (preset) {
      this.modelUrl = preset.baseUrl;
      this.model = preset.model;
    }
  }

  private draft(): LlmSettings {
    const next = new LlmSettings();
    next.provider = this.provider;
    next.apiKey = this.apiKey;
    next.baseUrl = this.modelUrl;
    next.model = this.model;
    return next;
  }

  private async doLogin(): Promise<void> {
    this.authNotice = '';
    try {
      await AuthStore.login(this.authProvider, this.uid, this.password);
      this.password = '';
      this.authNotice = '已登录。';
    } catch (e) {
      this.authNotice = errorMessage(e as Object);
    }
  }

  private async doRegister(): Promise<void> {
    this.authNotice = '';
    try {
      await AuthStore.register(this.authProvider, this.uid, this.password, this.displayName);
      this.password = '';
      this.authNotice = '已注册。';
    } catch (e) {
      this.authNotice = errorMessage(e as Object);
    }
  }

  private async save(): Promise<void> {
    this.probe = '';
    try {
      AppConfig.normalizeApiBase(this.siteBase);
      await LlmStore.save(this.draft());
      await LlmStore.saveBase(this.siteBase);
    } catch (e) {
      this.probe = errorMessage(e as Object);
    }
  }

  private async probeTts(): Promise<void> {
    if (!this.apiKey.trim() && !LlmStore.serverConfigured) {
      this.probe = '先填通义 API Key 再试听。';
      return;
    }
    if (this.provider === 'deepseek') {
      this.probe = 'DeepSeek 没有语音合成，请改用通义。';
      return;
    }
    this.busy = true;
    this.probe = '正在向通义要一段语音…';
    try {
      await this.save();
      await ttsService.speak('这是通义语音试听。后面边听边记会用这个声音，不会再是系统那种平的朗读。', 'coach', 1, {}, false);
      this.probe = '通义语音正常。朗读会用这个声音。';
    } catch (e) {
      this.probe = errorMessage(e as Object);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('账号与路线')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
        Text(AuthStore.isGuest()
          ? '当前是这台手机的访客进度。注册后可和网页同步。'
          : `已登录 ${AuthStore.user?.displayName ?? ''}`)
          .fontSize(13)
          .fontColor(Theme.muted)
          .lineHeight(20)
        Flex({ wrap: FlexWrap.Wrap }) {
          FilterChip({
            label: 'Java 转 Agent',
            active: AuthStore.user?.audience === 'transition',
            onSelect: () => {
              void AuthStore.setAudience('transition');
            }
          })
          FilterChip({
            label: '已有 Agent 经验',
            active: AuthStore.user?.audience === 'experienced',
            onSelect: () => {
              void AuthStore.setAudience('experienced');
            }
          })
        }
        .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          FilterChip({
            label: '用户名',
            active: this.authProvider === 'local',
            onSelect: () => {
              this.authProvider = 'local';
            }
          })
          FilterChip({
            label: '手机号',
            active: this.authProvider === 'phone',
            onSelect: () => {
              this.authProvider = 'phone';
            }
          })
        }
        .width('100%')
        TextInput({ placeholder: this.authProvider === 'phone' ? '11 位手机号' : '用户名', text: this.uid })
          .onChange((v: string) => {
            this.uid = v;
          })
        TextInput({ placeholder: '密码至少 6 位', text: this.password })
          .type(InputType.Password)
          .onChange((v: string) => {
            this.password = v;
          })
        TextInput({ placeholder: '显示名', text: this.displayName })
          .onChange((v: string) => {
            this.displayName = v;
          })
        if (this.authNotice) {
          Text(this.authNotice).fontSize(12).fontColor(Theme.muted)
        }
        Row({ space: 8 }) {
          Button('登录')
            .backgroundColor(Theme.accent)
            .onClick(() => {
              void this.doLogin();
            })
          Button('注册')
            .backgroundColor(Theme.card)
            .fontColor(Theme.ink)
            .onClick(() => {
              void this.doRegister();
            })
          if (!AuthStore.isGuest()) {
            Button('退出')
              .backgroundColor(Theme.card)
              .fontColor(Theme.ink)
              .onClick(() => {
                void AuthStore.logout();
              })
          }
        }
        .width('100%')

        Text('接入大模型点评')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ink)
        Text('Key 只存在这台手机里。点评、听写、朗读都由现网站点转发。服务器配了 Key 也可以不填。')
          .fontSize(13)
          .fontColor(Theme.muted)
          .lineHeight(20)
        Flex({ wrap: FlexWrap.Wrap }) {
          FilterChip({
            label: QWEN_PRESET.label,
            active: this.provider === 'qwen',
            onSelect: () => this.applyProvider('qwen')
          })
          FilterChip({
            label: DEEPSEEK_PRESET.label,
            active: this.provider === 'deepseek',
            onSelect: () => this.applyProvider('deepseek')
          })
          FilterChip({
            label: OPENAI_PRESET.label,
            active: this.provider === 'openai',
            onSelect: () => this.applyProvider('openai')
          })
          FilterChip({
            label: '自定义',
            active: this.provider === 'custom',
            onSelect: () => this.applyProvider('custom')
          })
        }
        .width('100%')

        if (this.provider !== 'custom' && presetFor(this.provider)) {
          Text(presetFor(this.provider)?.hint ?? '')
            .fontSize(12)
            .fontColor(Theme.muted)
            .lineHeight(18)
        }

        Text('API Key').fontSize(12).fontColor(Theme.muted)
        TextInput({
          placeholder: LlmStore.serverConfigured ? '服务器已配置，可留空' : 'sk-...',
          text: this.apiKey
        })
          .type(InputType.Password)
          .onChange((v: string) => {
            this.apiKey = v;
          })

        Text('接口地址').fontSize(12).fontColor(Theme.muted)
        TextInput({ placeholder: 'https://api.example.com/v1', text: this.modelUrl })
          .onChange((v: string) => {
            this.modelUrl = v;
          })

        Text('点评模型').fontSize(12).fontColor(Theme.muted)
        TextInput({ placeholder: 'qwen-plus', text: this.model })
          .onChange((v: string) => {
            this.model = v;
          })

        Text(BuildFlags.allowCleartext()
          ? '题库站点（本机联调可改成 http://电脑IP:43180）'
          : '题库站点（正式版仅支持 https://）').fontSize(12).fontColor(Theme.muted)
        TextInput({ placeholder: AppConfig.DEFAULT_BASE, text: this.siteBase })
          .onChange((v: string) => {
            this.siteBase = v;
          })

        if (this.probe) {
          Text(this.probe).fontSize(12).fontColor(Theme.muted).lineHeight(18)
        }

        Row({ space: 8 }) {
          Button(this.busy ? '试听中…' : '试听通义语音')
            .backgroundColor(Theme.card)
            .fontColor(Theme.ink)
            .enabled(!this.busy)
            .onClick(() => {
              void this.probeTts();
            })
          Button('清空')
            .backgroundColor(Theme.card)
            .fontColor(Theme.ink)
            .onClick(() => {
              const empty = new LlmSettings();
              this.provider = empty.provider;
              this.apiKey = '';
              this.modelUrl = empty.baseUrl;
              this.model = empty.model;
              this.probe = '';
              void LlmStore.save(empty);
            })
          Blank()
          Button('保存')
            .backgroundColor(Theme.accent)
            .onClick(() => {
              void this.save();
            })
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%')
      .padding(16)
    }
    .height('100%')
  }
}
