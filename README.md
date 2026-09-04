# Agent 面试舱 · HarmonyOS NEXT

独立的 ArkTS 原生客户端。题库、点评、朗读走 HTTP 接口，默认 `https://www.xiaoyangtx.cloud`。

配套目录（都在 `D:\work` 下，互不嵌套）：

- 网页：`agent-interview`
- 服务端：`agent-interview-server`
- 本工程：`agent-interview-harmony`

## 你需要准备

1. [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（HarmonyOS NEXT / API 20+）
2. 华为开发者账号，用于调试签名
3. HarmonyOS NEXT 真机（系统听写在模拟器上经常不可用）

## 打开工程

1. DevEco Studio → Open → 选本目录（`agent-interview-harmony` 根目录）
2. 等 SDK 与 `oh_modules` 同步
3. File → Project Structure 里给 `default` 配调试签名（本仓库不提交证书）
4. 连真机，Run `entry`

首次打开如果提示 `compatibleSdkVersion 6.0.0(20)` 与本机 SDK 不一致，在 `build-profile.json5` 里改成你安装的版本即可。

## 功能

底部三个页：

- **题库**：主题、搜索、难度、已掌握、完整作答 / 分步 / 追问、口述 + 面试官点评
- **模拟**：抽 5 个不同主题父题，再随机下探追问
- **听记**：面试官提问 + 学长作答；有 Key 时走现网 `/api/tts`（Ethan / Cherry）

设置（顶栏「接入」）：

- 通义 / DeepSeek / OpenAI / 自定义 Key（只存在本机）
- 点评模型
- **题库站点**：本机联调可改成 `http://电脑局域网IP:43180`（已允许明文 HTTP）

听写：先走系统 Speech Kit；不行则录音成 wav，POST `/api/transcribe`。

## 接口

- `GET /api/bank`
- `GET|POST /api/judge`
- `POST /api/tts`
- `POST /api/transcribe`

现网 Nginx 已允许最大 12MB 上传。鸿蒙录音会打成 wav。

## 本机联调

在 `agent-interview-server` 里启动 Python 服务（默认 `:43180`）：

```bash
python -m server
```

手机与电脑同一 Wi-Fi。在 App 设置里把题库站点改成 `http://<电脑IP>:43180`，点保存，再点刷新。

Windows 上看 IP：`ipconfig`。防火墙需放行 43180。
