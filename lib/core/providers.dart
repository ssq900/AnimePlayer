import 'package:flutter_riverpod/flutter_riverpod.dart';

// === Data 层 ===
import '../data/storage_service.dart';
import '../data/network_client.dart';

// === Platform 层 ===
import '../platform/webview_engine.dart';

// === Domain 层 ===
import '../domain/selector_engine.dart';
import '../domain/search_repository.dart';

// ==========================================
// 依赖注入图谱 (Dependency Graph)
// ==========================================

// 1. 基础平台服务
final webViewEngineProvider = Provider<WebViewEngine>((ref) => InAppWebViewEngine());

// 2. 核心数据服务
final storageServiceProvider = Provider<StorageService>((ref) => StorageService());
// 如果你有 networkClient，也可以在这里注册：
// final networkClientProvider = Provider<NetworkClient>((ref) => NetworkClient());

// 3. 领域服务（依赖基础服务）
final selectorEngineProvider = Provider<SelectorEngine>((ref) {
  // 注意：SelectorEngine 内部现在自动使用了 WebView 降级，如果需要可以把 webViewEngine 传进去
  return SelectorEngine();
});

// 4. 领域仓库（依赖领域服务）
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(selectorEngineProvider));
});
