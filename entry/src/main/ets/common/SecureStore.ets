import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesStore } from './PreferencesStore';

const ALIAS: string = 'ali_agent_interview_aes';
const PREFIX: string = 'huks1.';
const HEX: string = '0123456789abcdef';

function storageLevel(): huks.HuksParam {
  return {
    tag: huks.HuksTag.HUKS_TAG_AUTH_STORAGE_LEVEL,
    value: huks.HuksAuthStorageLevel.HUKS_AUTH_STORAGE_LEVEL_CE
  };
}

function aesParams(purpose: number, nonce?: Uint8Array): Array<huks.HuksParam> {
  const props: Array<huks.HuksParam> = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    storageLevel()
  ];
  if (nonce) {
    props.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    props.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new Uint8Array([1, 2, 3, 4]) });
  }
  return props;
}

function toHex(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += HEX.charAt((bytes[i] >> 4) & 15);
    out += HEX.charAt(bytes[i] & 15);
  }
  return out;
}

function fromHex(text: string): Uint8Array {
  const out = new Uint8Array(text.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(text.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function copyBytes(src: Uint8Array): Uint8Array {
  const out = new Uint8Array(src.length);
  out.set(src);
  return out;
}

function randomBytes(n: number): Uint8Array {
  const blob = cryptoFramework.createRandom().generateRandomSync(n);
  return copyBytes(blob.data);
}

function encodeUtf8(value: string): Uint8Array {
  const encoder = new util.TextEncoder();
  const dest = new Uint8Array(value.length * 4 + 8);
  const info = encoder.encodeIntoUint8Array(value, dest);
  return copyBytes(dest.subarray(0, info.written));
}

async function runCipher(purpose: number, nonce: Uint8Array, input: Uint8Array): Promise<Uint8Array> {
  const options: huks.HuksOptions = {
    properties: aesParams(purpose, nonce),
    inData: input
  };
  const handle = (await huks.initSession(ALIAS, options)).handle;
  try {
    const finished = await huks.finishSession(handle, options);
    const out = finished.outData;
    if (!out || out.length === 0) {
      throw new Error('huks empty');
    }
    return copyBytes(out);
  } catch (e) {
    try {
      await huks.abortSession(handle, { properties: [] });
    } catch (_abort) {
    }
    throw e instanceof Error ? e : new Error(String(e));
  }
}

export class SecureStore {
  private static ready: boolean = false;

  static async ensureKey(): Promise<void> {
    if (SecureStore.ready) {
      return;
    }
    const purpose = huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT;
    const genOpts: huks.HuksOptions = { properties: aesParams(purpose) };
    const exists = await huks.hasKeyItem(ALIAS, { properties: [storageLevel()] });
    if (!exists) {
      await huks.generateKeyItem(ALIAS, genOpts);
    }
    SecureStore.ready = true;
  }

  static async set(key: string, value: string): Promise<void> {
    if (!value) {
      await PreferencesStore.set(key, '');
      return;
    }
    await SecureStore.ensureKey();
    const nonce = randomBytes(12);
    const cipher = await runCipher(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce, encodeUtf8(value));
    await PreferencesStore.set(key, `${PREFIX}${toHex(nonce)}.${toHex(cipher)}`);
  }

  static async get(key: string, def: string = ''): Promise<string> {
    const stored = await PreferencesStore.get(key, '');
    if (!stored) {
      return def;
    }
    if (!stored.startsWith(PREFIX)) {
      try {
        await SecureStore.set(key, stored);
      } catch (e) {
        hilog.error(0x0000, 'Interview', 'huks migrate %{public}s', (e as Error).message);
      }
      return stored;
    }
    try {
      await SecureStore.ensureKey();
      const body = stored.slice(PREFIX.length);
      const dot = body.indexOf('.');
      if (dot <= 0) {
        return def;
      }
      const nonce = fromHex(body.slice(0, dot));
      const cipher = fromHex(body.slice(dot + 1));
      const plain = await runCipher(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, cipher);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(plain);
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'huks decrypt %{public}s', (e as Error).message);
      return def;
    }
  }
}
