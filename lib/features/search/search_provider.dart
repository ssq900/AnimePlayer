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
