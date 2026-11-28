import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/selector_engine.dart';
import '../services/storage_service.dart';
import '../features/search/search_repository.dart';

// 1. 基础服务层依赖注入
final selectorEngineProvider = Provider<SelectorEngine>((ref) => SelectorEngine());

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

// 2. Repository 层依赖注入
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(selectorEngineProvider));
});
