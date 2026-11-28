import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../models/rule.dart';
import '../../services/xpath_service.dart';
import '../../core/errors/app_failure.dart';

final searchProvider = AsyncNotifierProvider<SearchNotifier, List<SearchResult>>(SearchNotifier.new);

// 记录错误的 Provider（可选，用于 UI 面板显示）
final searchErrorsProvider = StateProvider<List<String>>((ref) => []);

class SearchNotifier extends AsyncNotifier<List<SearchResult>> {
  @override
  Future<List<SearchResult>> build() async => [];

  Future<void> search(String keyword, List<AnimeRule> rules) async {
    state = const AsyncLoading();
    ref.read(searchErrorsProvider.notifier).state = [];

    // 依赖注入获取 Repository
    final repo = ref.read(searchRepositoryProvider);
    
    // 调用 Repository，获取结果和错误
    final responses = await repo.searchAll(keyword, rules);

    final uniqueResults = <SearchResult>[];
    final seenTitles = <String>{};
    final errors = <String>[];

    for (int i = 0; i < responses.length; i++) {
      final resp = responses[i];
      final ruleName = rules[i].name;

      // 收集去重后的结果
      for (final res in resp.results) {
        final cleanTitle = res.title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        if (!seenTitles.contains(cleanTitle)) {
          seenTitles.add(cleanTitle);
          uniqueResults.add(res);
        }
      }

      // 处理结构化错误
      if (resp.failure != null) {
        if (resp.failure is ChallengeFailure) {
          errors.add('[$ruleName] 需要人机验证，暂时无法获取');
        } else {
          errors.add('[$ruleName] ${resp.failure!.message}');
        }
      }
    }

    ref.read(searchErrorsProvider.notifier).state = errors;

    if (uniqueResults.isEmpty && errors.isNotEmpty) {
      state = AsyncError(errors.join('\n'), StackTrace.current);
    } else {
      state = AsyncData(uniqueResults);
    }
  }
}
