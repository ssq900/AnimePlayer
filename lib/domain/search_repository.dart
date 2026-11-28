import 'dart:async';
import '../core/errors/app_failure.dart';
import '../models/rule.dart';
import '../../domain/selector_engine.dart';

class SearchResultWithFailure {
  final List<SearchResult> results;
  final AppFailure? failure;

  SearchResultWithFailure(this.results, [this.failure]);
}

class SearchRepository {
  final SelectorEngine _engine;
  final _pool = ConcurrentPool(maxConcurrent: 5);

  SearchRepository(this._engine);

  Future<List<SearchResultWithFailure>> searchAll(String keyword, List<AnimeRule> rules) async {
    final futures = rules.map((rule) {
      return _pool.run(() async {
        try {
          final list = await _engine.search(rule, keyword)
              .timeout(const Duration(seconds: 15));
          return SearchResultWithFailure(list);
        } on TimeoutException {
          return SearchResultWithFailure([], NetworkFailure('搜索超时'));
        } catch (e) {
          final errStr = e.toString();
          if (errStr.contains('验证') || errStr.contains('403') || errStr.contains('CF')) {
            return SearchResultWithFailure([], ChallengeFailure());
          } else if (errStr.contains('XPath') || errStr.contains('CSS') || errStr.contains('容器')) {
            return SearchResultWithFailure([], ParseFailure(errStr));
          }
          return SearchResultWithFailure([], SourceUnavailableFailure(errStr));
        }
      });
    }).toList();

    return Future.wait(futures);
  }
}

// 并发池（防止多源并发导致内存溢出）
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
