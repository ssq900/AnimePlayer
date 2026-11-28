import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/selector_engine.dart';
import '../services/storage_service.dart';
import '../features/search/search_repository.dart';

final selectorEngineProvider = Provider<SelectorEngine>((ref) => SelectorEngine());

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(
    ref.watch(selectorEngineProvider),
    ref.watch(storageServiceProvider), // 🔥 注入 StorageService
  );
});
