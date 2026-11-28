import 'dart:async';
import '../../core/errors/app_failure.dart';
import '../../models/rule.dart';
import '../../services/selector_engine.dart';
import '../../services/storage_service.dart'; // 🔥 引入存储服务

class SearchResultWithFailure {
  final List<SearchResult> results;
  final AppFailure? failure;
  
  SearchResultWithFailure(this.results, [this.failure]);
}

class SearchRepository {
  final SelectorEngine _engine;
  final StorageService _storageService; // 🔥 注入存储服务
  final _pool = ConcurrentPool(maxConcurrent: 5);

  SearchRepository(this._engine, this._storageService);

  Future<List<SearchResultWithFailure>> searchAll(String keyword, List<AnimeRule> rules) async {
    final futures = rules.map((rule) {
      return _pool.run(() async {
        try {
          final list = await _engine.search(rule, keyword)
              .timeout(const Duration(seconds: 15));
          
          // 🔥 成功：更新健康度
          _updateHealth(rule, true, '');
          return SearchResultWithFailure(list);
        } on TimeoutException {
          _updateHealth(rule, false, 'NetworkFailure: 搜索超时', 'search');
          return SearchResultWithFailure([], NetworkFailure('搜索超时'));
        } catch (e) {
          String reason = '未知错误';
          if (e.toString().contains('验证') || e.toString().contains('403')) {
            reason = 'ChallengeFailure: 需要人机验证';
            _updateHealth(rule, false, reason, 'search');
            return SearchResultWithFailure([], ChallengeFailure());
          } else if (e.toString().contains('XPath') || e.toString().contains('CSS')) {
            reason = 'ParseFailure: ${e.toString()}';
            _updateHealth(rule, false, reason, 'search');
            return SearchResultWithFailure([], ParseFailure(e.toString()));
          }
          
          _updateHealth(rule, false, reason, 'search');
          return SearchResultWithFailure([], SourceUnavailableFailure(e.toString()));
        }
      });
    }).toList();

    return Future.wait(futures);
  }

  // 🔥 核心：异步静默更新规则健康度
  void _updateHealth(AnimeRule rule, bool isSuccess, String reason, [String stage = '']) {
    final updatedRule = isSuccess
        ? rule.copyWith(
            successCount: rule.successCount + 1,
            lastSuccessTime: DateTime.now().millisecondsSinceEpoch,
            lastFailureReason: '',
            lastFailureStage: '',
          )
        : rule.copyWith(
            failCount: rule.failCount + 1,
            lastFailureReason: reason,
            lastFailureStage: stage,
          );
    // 异步保存，不阻塞搜索结果的返回
    _storageService.upsertRule(updatedRule).catchError((e) {
      print('更新规则健康度失败: $e');
    });
  }
}

class ConcurrentPool {
  final int maxConcurrent;
  int _running = 0;
  final _queue = <void Function()>[];

  ConcurrentPool({this.maxConcurrent = 5});

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    void execute() {
      _running++;
      task().then((value) => completer.complete(value))
          .catchError((e, st) => completer.completeError(e, st))
          .whenComplete(() {
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
