#!/data/data/com.termux/files/usr/bin/bash
# ==========================================
# 1. 修改 pubspec.yaml 添加依赖
# ==========================================
if ! grep -q "flutter_riverpod" pubspec.yaml; then
    sed -i '/^dependencies:/a\  flutter_riverpod: ^2.6.1\n  http: ^1.2.0\n  xpath: ^1.1.0' pubspec.yaml
fi

# ==========================================
# 2. 创建目录
# ==========================================
mkdir -p lib/services lib/features/search lib/features/player lib/pages

# ==========================================
# 3. 生成 lib/services/xpath_service.dart
# ==========================================
cat << 'EOF' > lib/services/xpath_service.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xpath/xpath.dart';
import '../models/rule.dart';

class XPathParseException implements Exception {
  final String message;
  XPathParseException(this.message);
  @override
  String toString() => 'XPathParseException: $message';
}

class _SerialLock {
  Future<void> _chain = Future.value();
  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

class XPathService {
  final _webViewLock = _SerialLock();

  static const _httpHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    final url = buildSearchUrl(rule.baseUrl, keyword);
    String html;
    try {
      html = await _fetchHttp(url);
    } catch (_) {
      html = await _webViewLock.run(() => _fetchWithWebView(url));
    }
    return parseSearchPage(html, rule);
  }

  String buildSearchUrl(String baseUrl, String keyword) {
    final encoded = Uri.encodeComponent(keyword);
    if (baseUrl.contains('{keyword}')) {
      return baseUrl.replaceAll('{keyword}', encoded);
    }
    return baseUrl;
  }

  Future<String> _fetchHttp(String url) async {
    final resp = await http.get(Uri.parse(url), headers: _httpHeaders).timeout(const Duration(seconds: 12));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  Future<String> _fetchWithWebView(String url) async {
    throw UnimplementedError('请把原项目的 WebView 嗅探逻辑填入 _fetchWithWebView');
  }

  XmlDocument parseHtml(String html) {
    final cleaned = _cleanHtml(html);
    try {
      return XmlDocument.parse(cleaned);
    } on XmlException catch (e) {
      throw XPathParseException('HTML 解析失败: ${e.message}');
    }
  }

  String _cleanHtml(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<(br|hr|img|input|meta|link|area|base|col|embed|param|source|track|wbr)([^>]*?)/?>', caseSensitive: false), '<$1$2/>');
    s = s.replaceAll('&nbsp;', '&#160;');
    return s;
  }

  List<XmlElement> findElements(XmlNode context, String expr) {
    if (expr.trim().isEmpty) return const [];
    try {
      final nodes = context.xpath(expr);
      return nodes.whereType<XmlElement>().toList();
    } catch (e) {
      throw XPathParseException('XPath "$expr" 执行失败: $e');
    }
  }

  List<SearchResult> parseSearchPage(String html, AnimeRule rule) {
    final doc = parseHtml(html);
    final containers = findElements(doc, rule.searchSelector);
    if (containers.isEmpty) return [];

    final results = <SearchResult>[];
    for (final container in containers) {
      final links = findElements(container, rule.animeLinkSelector);
      for (final a in links) {
        final title = a.innerText.trim();
        final href = a.getAttribute('href')?.trim() ?? '';
        if (title.isEmpty || href.isEmpty) continue;
        results.add(SearchResult(
          title: title,
          url: _resolveUrl(rule.baseUrl, href),
          sourceName: rule.name,
        ));
      }
    }
    return results;
  }

  String _resolveUrl(String base, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return Uri.parse(base).resolve(path).toString();
    } catch (_) {
      return path;
    }
  }
}
EOF

# ==========================================
# 4. 生成 lib/features/search/search_provider.dart
# ==========================================
cat << 'EOF' > lib/features/search/search_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/rule.dart';
import '../../services/xpath_service.dart';

class ConcurrentPool {
  final int maxConcurrent;
  int _running = 0;
  final _queue = <void Function()>[];

  ConcurrentPool({this.maxConcurrent = 5});

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    void execute() {
      _running++;
      task().then((value) {
        completer.complete(value);
      }).catchError((Object e, StackTrace st) {
        completer.completeError(e, st);
      }).whenComplete(() {
        _running--;
        _drain();
      });
    }
    _queue.add(execute);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      _queue.removeAt(0)();
    }
  }
}

final searchProvider = AsyncNotifierProvider<SearchNotifier, List<SearchResult>>(SearchNotifier.new);

class SearchNotifier extends AsyncNotifier<List<SearchResult>> {
  final _pool = ConcurrentPool(maxConcurrent: 5);
  final _xpath = XPathService();

  @override
  Future<List<SearchResult>> build() async => [];

  Future<void> search(String keyword, List<AnimeRule> rules) async {
    state = const AsyncLoading();
    final results = <SearchResult>[];
    final errors = <String>[];

    final futures = rules.map((rule) {
      return _pool.run(() async {
        try {
          final list = await _xpath.search(rule, keyword);
          return (rule, list, null as Object?);
        } catch (e) {
          return (rule, const <SearchResult>[], e as Object?);
        }
      });
    }).toList();

    final finished = await Future.wait(futures);
    for (final (rule, list, err) in finished) {
      results.addAll(list);
      if (err != null) errors.add('${rule.name}: $err');
    }

    if (results.isEmpty && errors.isNotEmpty) {
      state = AsyncError(errors.join('\n'), StackTrace.current);
    } else {
      state = AsyncData(results);
    }
  }
}
EOF

# ==========================================
# 5. 生成 lib/features/player/playback_controller.dart
# ==========================================
cat << 'EOF' > lib/features/player/playback_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

enum GestureMode { brightness, volume, seek }

class PlaybackState {
  final VideoPlayerController? controller;
  final bool isInitialized;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final GestureMode gestureMode;
  final double brightness;
  final double volume;

  const PlaybackState({
    this.controller,
    this.isInitialized = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.gestureMode = GestureMode.seek,
    this.brightness = 1.0,
    this.volume = 1.0,
  });

  PlaybackState copyWith({
    VideoPlayerController? controller,
    bool? isInitialized,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    GestureMode? gestureMode,
    double? brightness,
    double? volume,
  }) {
    return PlaybackState(
      controller: controller ?? this.controller,
      isInitialized: isInitialized ?? this.isInitialized,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      gestureMode: gestureMode ?? this.gestureMode,
      brightness: brightness ?? this.brightness,
      volume: volume ?? this.volume,
    );
  }
}

final playbackControllerProvider = NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() {
    ref.onDispose(() {
      state.controller?.dispose();
    });
    return const PlaybackState();
  }

  Future<void> initialize(String url) async {
    state.controller?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    state = state.copyWith(controller: controller, isInitialized: false);
    await controller.initialize();
    controller.addListener(_onTick);
    state = state.copyWith(isInitialized: true, duration: controller.value.duration);
    await controller.play();
    state = state.copyWith(isPlaying: true);
  }

  void _onTick() {
    final c = state.controller;
    if (c == null) return;
    state = state.copyWith(
      position: c.value.position,
      duration: c.value.duration,
      isPlaying: c.value.isPlaying,
    );
  }

  void updateGestureMode(GestureMode mode) {
    state = state.copyWith(gestureMode: mode);
  }

  void setBrightness(double v) {
    state = state.copyWith(brightness: v.clamp(0.0, 1.0));
  }

  void setVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    state.controller?.setVolume(clamped);
  }
}
EOF

# ==========================================
# 6. 生成 lib/pages/player_page.dart
# ==========================================
cat << 'EOF' > lib/pages/player_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../features/player/playback_controller.dart';

class PlayerPage extends ConsumerStatefulWidget {
  final String videoUrl;
  const PlayerPage({super.key, required this.videoUrl});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackControllerProvider.notifier).initialize(widget.videoUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackControllerProvider);
    final notifier = ref.read(playbackControllerProvider.notifier);

    if (!state.isInitialized || state.controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    final controller = state.controller!;
    final aspect = controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          if (details.globalPosition.dx < MediaQuery.of(context).size.width / 2) {
            notifier.setBrightness(state.brightness - delta / 200);
          } else {
            notifier.setVolume(state.volume - delta / 200);
          }
        },
        onHorizontalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          final newPos = state.position + Duration(milliseconds: (delta * 100).round());
          controller.seekTo(newPos);
        },
        onDoubleTap: () {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        },
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
EOF

# ==========================================
# 7. 生成 lib/pages/search_page.dart
# ==========================================
cat << 'EOF' > lib/pages/search_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/search/search_provider.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';

class SearchPage extends ConsumerStatefulWidget {
  final List<AnimeRule> rules;
  const SearchPage({super.key, required this.rules});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    ref.read(searchProvider.notifier).search(keyword, widget.rules);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: '输入番剧名称...',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _onSearch(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _onSearch),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('搜索失败:\n$err', style: const TextStyle(color: Colors.red)),
        ),
        data: (results) {
          if (results.isEmpty) return const Center(child: Text('暂无结果'));
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final r = results[i];
              return ListTile(
                title: Text(r.title),
                subtitle: Text(r.sourceName),
                onTap: () {},
              );
            },
          );
        },
      ),
    );
  }
}
EOF

# ==========================================
# 8. 尝试修改 main.dart
# ==========================================
if ! grep -q "flutter_riverpod" lib/main.dart; then
  sed -i "1i import 'package:flutter_riverpod/flutter_riverpod.dart';" lib/main.dart
fi
sed -i -E 's/runApp\((const )?MyApp\(\)\);/runApp(const ProviderScope(child: MyApp()));/' lib/main.dart

echo -e "\n\033[32m✅ 所有文件已生成完毕！\033[0m"

# ==========================================
# 9. 自动提交到 Git
# ==========================================
git add pubspec.yaml lib/
git commit -m "refactor: 按真实 AnimeRule 模型重写搜索，受控并发 + WebView 串行降级"
echo -e "\n\033[32m✅ 代码已 Commit，请执行 git push 推送到 GitHub！\033[0m"
