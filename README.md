# Anime Aggregator

XPath（CSS selector）驱动的动漫聚合客户端。应用本身**不内置任何视频源或版权内容**，所有内容来自用户自行导入的规则所指向的外部网站。

## 最低系统要求

**本应用最低支持 Android 7.0（API 24）。**

- Flutter 版本锁定为 **3.35.0**（`environment.flutter: '>=3.35.0 <3.36.0'`）。
- `android/app/build.gradle` 中 **显式硬编码 `minSdk = 24`**。
- 所有直接 pub 依赖均已核对 minSdk ≤ 24，见下方依赖表。

## 经过验证 minSdk ≤ 24 的依赖

| 包 | 锁定版本 | Android minSdk 依据 |
|---|---|---|
| `http` | 1.2.2 | 纯 Dart 包，无原生代码 |
| `html` | 0.15.4 | 纯 Dart 包，无原生代码 |
| `shared_preferences` | 2.5.3 | 官方声明 SDK 24+ |
| `path_provider` | 2.1.5 | 官方声明 SDK 24+ |
| `url_launcher` | 6.3.1 | 最新 android impl 已剥离低版本代码，SDK 24+ |
| `video_player` | 2.9.5 | ExoPlayer 回退兼容，官方声明 SDK 24+ |
| `flutter_inappwebview` | 6.1.5 | 锁定版本，官方验证 SDK 24+ |
| `flutter_local_notifications` | 18.0.1 | 锁定版本，配合脱糖支持 24+ |
| `webdav_client` | 1.2.1 | 纯 Dart 网络库 |
| `gbk_codec` | 0.4.0 | 纯 Dart 编解码 |
| `synchronized` | 3.1.0+1 | 纯 Dart 并发锁 |

> `sqflite` **未使用**。规则存储走 JSON 文件 + `path_provider`，完全绕开原生 SQLite 依赖，避免 sqflite_android 版本线中 minSdk 声明抖动带来的构建风险。

## Android 7.0（API 24）已知限制

1. **TLS / WebView 版本**：Android 7 设备的系统 WebView 可能停留在较旧版本（Chrome 51–70 区间），部分现代动漫源使用 TLS 1.3 或较新的 cipher suite，可能导致请求在 TLS 握手阶段失败。部分源在 API 24 设备上无法解析属于已知风险。
2. **`video_player` 与 HLS**：`video_player` 在 Android 上底层是 ExoPlayer。API 24 下 HLS（`.m3u8`）的支持取决于流本身的编码参数。部分 fMP4 + 特定加密的 HLS 流可能在旧设备上无法播放，此时会回退到“外部打开”路径。
3. **`android:usesCleartextTraffic="true"`**：为了兼容仍使用 HTTP 的老旧源而开启。如果你只使用 HTTPS 源，建议移除。
4. **CSS selector 而非完整 XPath**：v1 规则编辑器接收的是 CSS selector。从 Kazumi 的 XPath 规则迁移时，需要把 `//div[@class="x"]` 手动转换为 `.x`。包含绝对数字索引（如 `div[2]`）的 XPath 会被转换器拦截，需手动精简。

## 在 Termux 中本地构建（概要）

- 使用 `proot-distro` 登录 Debian，**不要在 Termux 原生 shell 中直接跑 Flutter Android 构建**。
- Flutter 固定克隆到 `/opt/flutter` 并 checkout `3.35.0`。
- 安装 `openjdk-17-jdk` 以及 Android cmdline-tools。
- 本地构建命令：
  ```bash
  flutter pub get
  flutter analyze
  flutter test
  flutter build apk --release
