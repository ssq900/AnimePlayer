import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/xpath_service.dart';
import '../services/webview_engine.dart';
import '../services/storage_service.dart';
import '../features/search/search_repository.dart';

// 1. 基础服务层
final webViewEngineProvider = Provider<WebViewEngine>((ref) => InAppWebViewEngine());

final xpathServiceProvider = Provider<XPathService>((ref) {
  return XPathService(webViewEngine: ref.watch(webViewEngineProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

// 2. Repository 层（依赖基础服务）
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(xpathServiceProvider));
});
