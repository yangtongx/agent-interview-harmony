import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../common/AppConfig';
import { Emitter } from '../common/Emitter';
import { PreferencesStore } from '../common/PreferencesStore';
import { SecureStore } from '../common/SecureStore';
import { parseAuthUser, parseMasteredPayload, parseSession } from '../model/Parse';
import { AuthUser } from '../model/Types';
import { ApiClient } from '../network/ApiClient';
import { ProgressStore } from './ProgressStore';
import { HomeStore } from './HomeStore';

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export class AuthStore {
  static user: AuthUser | null = null;
  static notice: string = '';
  static ready: boolean = false;
  static entered: boolean = false;
  private static bus: Emitter = new Emitter();

  static subscribe(fn: () => void): () => void {
    return AuthStore.bus.subscribe(fn);
  }

  static emit(): void {
    AuthStore.bus.emit();
  }

  static needsAudience(): boolean {
    return AuthStore.ready && AuthStore.user !== null && AuthStore.user.audience === 'unset';
  }

  static isGuest(): boolean {
    if (!AuthStore.user) {
      return true;
    }
    return AuthStore.user.isGuest;
  }

  static needsLogin(): boolean {
    return AuthStore.ready && !AuthStore.entered;
  }

  static async markEntered(): Promise<void> {
    AuthStore.entered = true;
    await PreferencesStore.set(AppConfig.AUTH_ENTERED_PREF, '1');
    AuthStore.emit();
  }

  private static async forgetEntered(): Promise<void> {
    AuthStore.entered = false;
    await PreferencesStore.set(AppConfig.AUTH_ENTERED_PREF, '');
  }

  static async deviceId(): Promise<string> {
    let id = await PreferencesStore.get(AppConfig.DEVICE_PREF, '');
    if (UUID_RE.test(id)) {
      return id;
    }
    id = `${util.generateRandomUUID()}`;
    await PreferencesStore.set(AppConfig.DEVICE_PREF, id);
    return id;
  }

  static async rotateDevice(): Promise<string> {
    const id = `${util.generateRandomUUID()}`;
    await PreferencesStore.set(AppConfig.DEVICE_PREF, id);
    return id;
  }

  private static async persist(token: string, user: AuthUser): Promise<void> {
    AppConfig.sessionToken = token;
    AuthStore.user = user;
    await SecureStore.set(AppConfig.TOKEN_PREF, token);
    await PreferencesStore.set(AppConfig.USER_PREF, JSON.stringify({
      'id': user.id,
      'displayName': user.displayName,
      'audience': user.audience,
      'status': user.status,
      'isGuest': user.isGuest
    }));
    AuthStore.emit();
  }

  private static async clearSession(): Promise<void> {
    AppConfig.sessionToken = '';
    AuthStore.user = null;
    await SecureStore.set(AppConfig.TOKEN_PREF, '');
    await PreferencesStore.set(AppConfig.USER_PREF, '');
    AuthStore.emit();
  }

  static async bootstrap(): Promise<void> {
    AuthStore.entered = (await PreferencesStore.get(AppConfig.AUTH_ENTERED_PREF, '')) === '1';
    if (!AuthStore.entered) {
      AuthStore.ready = true;
      AuthStore.emit();
      return;
    }
    const token = await SecureStore.get(AppConfig.TOKEN_PREF, '');
    const cached = await PreferencesStore.get(AppConfig.USER_PREF, '');
    let cachedUser: AuthUser | null = null;
    if (cached) {
      try {
        cachedUser = parseAuthUser(JSON.parse(cached) as Object);
      } catch (e) {
        hilog.error(0x0000, 'Interview', 'auth cache %{public}s', (e as Error).message);
      }
    }
    AppConfig.sessionToken = '';
    try {
      if (!token) {
        await AuthStore.forgetEntered();
        return;
      }
      AppConfig.sessionToken = token;
      try {
        const text = await ApiClient.getText('/api/me');
        const me = parseAuthUser(JSON.parse(text) as Object);
        await AuthStore.persist(token, me);
        await AuthStore.syncProgress();
        await HomeStore.load(me.audience);
        return;
      } catch (e) {
        hilog.error(0x0000, 'Interview', 'auth me %{public}s', (e as Error).message);
        if (cachedUser) {
          await AuthStore.persist(token, cachedUser);
          await HomeStore.load(cachedUser.audience);
          return;
        }
        await AuthStore.clearSession();
        await AuthStore.forgetEntered();
      }
    } catch (e) {
      AuthStore.notice = (e as Error).message;
    } finally {
      AuthStore.ready = true;
      AuthStore.emit();
    }
  }

  static async deviceLogin(audience: string): Promise<void> {
    const deviceId = await AuthStore.deviceId();
    const text = await ApiClient.postJson('/api/auth/device', {
      'deviceId': deviceId,
      'platform': 'harmony',
      'deviceName': 'HarmonyOS',
      'audience': audience
    });
    const session = parseSession(text);
    await AuthStore.persist(session.token, session.user);
    await AuthStore.syncProgress();
    await HomeStore.load(session.user.audience);
    await AuthStore.markEntered();
  }

  static async syncProgress(): Promise<void> {
    try {
      const text = await ApiClient.getText('/api/progress');
      const remote = parseMasteredPayload(text);
      const merged = ProgressStore.merge(ProgressStore.ids, remote);
      await ProgressStore.replace(merged);
      await ProgressStore.pushRemote();
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'progress sync %{public}s', (e as Error).message);
    }
  }

  static async setAudience(audience: string): Promise<void> {
    const text = await ApiClient.patchJson('/api/me', { 'audience': audience });
    const me = parseAuthUser(JSON.parse(text) as Object);
    await AuthStore.persist(AppConfig.sessionToken, me);
    await HomeStore.load(me.audience);
  }

  static async register(provider: string, uid: string, password: string, displayName: string): Promise<void> {
    const deviceId = await AuthStore.deviceId();
    const text = await ApiClient.postJson('/api/auth/register', {
      'provider': provider,
      'uid': uid,
      'password': password,
      'displayName': displayName,
      'platform': 'harmony',
      'deviceId': deviceId,
      'audience': AuthStore.user?.audience ?? 'unset'
    });
    const session = parseSession(text);
    await AuthStore.persist(session.token, session.user);
    await AuthStore.syncProgress();
    await HomeStore.load(session.user.audience);
    await AuthStore.markEntered();
  }

  static async login(provider: string, uid: string, password: string): Promise<void> {
    const deviceId = await AuthStore.deviceId();
    const text = await ApiClient.postJson('/api/auth/login', {
      'provider': provider,
      'uid': uid,
      'password': password,
      'platform': 'harmony',
      'deviceId': deviceId
    });
    const session = parseSession(text);
    await AuthStore.persist(session.token, session.user);
    await AuthStore.syncProgress();
    await HomeStore.load(session.user.audience);
    await AuthStore.markEntered();
  }

  static async logout(): Promise<void> {
    try {
      await ApiClient.postJson('/api/auth/logout', {});
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'logout %{public}s', (e as Error).message);
    }
    await AuthStore.clearSession();
    await AuthStore.forgetEntered();
    await AuthStore.rotateDevice();
    await HomeStore.load('unset');
    AuthStore.emit();
  }
}
