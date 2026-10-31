# Anime Aggregator

XPath（CSS selector）驱动的动漫聚合客户端。应用本身**不内置任何视频源或版权内容**，所有内容来自用户自行导入的规则所指向的外部网站。

## 最低系统要求

**本应用最低支持 Android 7.0（API 24）。**

- Flutter 版本锁定为 **3.35.0**（`environment.flutter: '>=3.35.0 <3.36.0'`）。
- `android/app/build.gradle` 中 **显式硬编码 `minSdk = 24`**，不依赖 `flutter.minSdkVersion` 隐式继承。
- 所有直接 pub 依赖均已核对 minSdk ≤ 24，见下方依赖表。

## 经过验证 minSdk ≤ 24 的依赖

| 包 | 版本 | Android minSdk 依据 |
|---|---|---|
| `http` | ^1.2.2 | 纯 Dart 包，无 Android 原生代码 |
| `html` | ^0.15.4 | 纯 Dart 包，无 Android 原生代码 |
| `shared_preferences` | ^2.5.3 | pub.dev 声明 **Support: SDK 24+**[reference:3] |
| `path_provider` | ^2.1.5 | Flutter 官方插件，Support: SDK 24+ |
| `url_launcher` | ^6.3.1 | 最新 android 实现已移除 SDK<24 代码，minSdk 24[reference:4] |
| `video_player` | ^2.9.5 | pub.dev 声明 **Support: SDK 24+**，底层 ExoPlayer 在 API 24 可用[reference:5] |

> `sqflite` **未使用**。规则存储走 JSON 文件 + `path_provider`，完全绕开原生 SQLite 依赖，避免 sqflite_android 版本线中 minSdk 声明抖动带来的构建风险。

## Android 7.0（API 24）已知限制

1. **TLS / WebView 版本**：Android 7 设备的系统 WebView 可能停留在较旧版本（Chrome 51–70 区间），部分现代动漫源使用 TLS 1.3 或较新的 cipher suite，可能导致 `http` 请求在 TLS 握手阶段失败。这不是本应用代码能完全修复的，**部分源在 API 24 设备上无法解析属于已知风险**。
2. **`video_player` 与 HLS**：`video_player` 在 Android 上底层是 ExoPlayer，API 24 下 HLS（`.m3u8`）的支持取决于 ExoPlayer 版本和流本身的编码参数。部分使用 fMP4 + 特定加密的 HLS 流可能在旧设备上无法播放，此时会自动回退到“外部打开”路径。
3. **`android:usesCleartextTraffic="true"`**：为了兼容仍使用 HTTP 的老旧源而开启。如果你只使用 HTTPS 源，建议移除以收紧安全策略。
4. **CSS selector 而非完整 XPath**：v1 规则编辑器接收的是 CSS selector（例如 `.item`、`.episode-list a`）。从 Kazumi 的 XPath 规则迁移时，需要把 `//div[@class="x"]` 手动转换为 `.x`。完整的 XPath 1.0 求值引擎不在 v1 范围内。

## 在 Termux 中本地构建（概要）

完整命令见项目根目录的 `TERMUX_SETUP.md`（或本文档第一节）。核心要点：

- 使用 `proot-distro` 登录 Debian，**不要在 Termux 原生 shell 中直接跑 Flutter Android 构建**。
- Flutter 固定克隆到 `/opt/flutter` 并 checkout `3.35.0`。
- 安装 `openjdk-17-jdk`，以及 Android cmdline-tools。
- 本地构建命令：
  ```bash
  flutter pub get
  flutter analyze
  flutter build apk --release
  ```
- **Termux 中的构建速度可能非常慢**，建议将 GitHub Actions 作为主要构建通道，本地仅用于语法和 UI 快速验证。

## GitHub Actions 配置

### 1. 在本地生成 release keystore

```bash
keytool -genkey -v -keystore release.keystore \
  -alias anime_aggregator -keyalg RSA -keysize 2048 -validity 10000
base64 -w 0 release.keystore > keystore.b64
```

`keystore.b64` 的内容就是 `KEYSTORE_BASE64` Secret 的值。**不要把 `release.keystore` 或 `key.properties` 提交到仓库**（`.gitignore` 已覆盖）。

### 2. 在 GitHub 仓库 Settings → Secrets and variables → Actions 中创建

| Secret 名称 | 值 |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w 0 release.keystore` 的输出 |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | `anime_aggregator`（或你实际使用的 alias） |
| `KEY_PASSWORD` | key 密码 |

### 3. 触发构建

推送到 `main` 或手动 **Actions → Build Release APK → Run workflow**。构建完成后在 workflow run 的 Artifacts 中下载 `release-apks`。

## 如何编写第一条规则

以虚构站点 `https://example-anime.test` 为例：

1. 在浏览器中打开搜索页，按 F12，找到搜索结果列表的容器元素，例如 `<ul class="result-list">`。填入 **搜索结果容器选择器**：`.result-list`。
2. 容器内每个番剧是一个 `<li class="item">`，内含 `<a href="/anime/123">。填入 **番剧条目选择器**：`li.item`。
3. 进入任意番剧详情页，找到剧集链接列表，例如 `<div class="episode-list"><a href="/watch/123-1">第1话</a></div>`。填入 **剧集列表选择器**：`.episode-list a`。
4. 进入任意剧集播放页，找到实际视频元素或播放按钮，例如 `<video><source src="..."></video>` 或 `<a class="play-btn" href="...">`。填入 **剧集链接选择器**：`video source, a.play-btn`（v1 取第一个匹配节点的 `href` 或 `src`）。
5. `baseUrl` 填写搜索页模板，例如 `https://example-anime.test/search?q={keyword}`。

保存后在首页选择该规则，搜索关键词即可走通“搜索 → 详情 → 剧集 → 播放/外部打开”闭环。

## Roadmap（v1 不实现）

- 弹幕系统
- Anime4K 超分辨率
- BitTorrent 边下边播
- Bangumi 同步
- 云过滤 / 共享规则市场
- 多平台桌面端
- 完整 XPath 1.0 求值引擎

## 风险提醒（务必阅读）

- **Kazumi 官方目前要求 Android 10+**。本项目的 Android 7 兼容目标是自定义目标，不是 Kazumi 的既有能力。你需要自行承担低版本 Android 的 WebView 内核过旧、TLS 协议栈落后导致的“部分源无法解析”的风险。
- Flutter 3.35+ 的 minSdk 已经是 24，但**第三方插件不保证遵守这个下限**。如果 CI 构建时遇到 `uses-sdk:minSdkVersion 24 cannot be smaller than version XX declared in library`，必须**降级或替换该插件**，不能简单把 `minSdk` 提到 26 了事——那会违背本项目的核心约束。
- Termux 本地构建可能极慢，**GitHub Actions 是主要构建通道**，Termux 本地构建仅用于快速验证语法和 UI。
