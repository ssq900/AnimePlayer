import 'dart:async';
import '../models/rule.dart';
import 'playback_engine.dart';

class FallbackManager {
  final List<SearchResult> _candidates;
  final Set<String> _failedUrls = {};
  int _attemptCount = 0;
  final int maxRetries;

  FallbackManager(List<SearchResult> candidates, {this.maxRetries = 2}) 
      : _candidates = List.from(candidates) {
    // 按源优先级排序：优先尝试其他源的剧集，同源降级到后面
    _candidates.sort((a, b) => a.rule.name.compareTo(b.rule.name)); 
  }

  SearchResult? getNextCandidate(String currentUrl) {
    _failedUrls.add(currentUrl);
    if (_attemptCount >= maxRetries) return null;

    for (var result in _candidates) {
      if (!_failedUrls.contains(result.link)) {
        _attemptCount++;
        return result;
      }
    }
    return null;
  }

  // 错误分类：判断该错误是否值得自动切源
  bool shouldFallback(PlaybackError error) {
    switch (error.type) {
      case PlaybackErrorType.codec:
        return true; // 解码不支持，直接换源
      case PlaybackErrorType.network:
        return true; // 404 或超时，先尝试换源
      default:
        return false;
    }
  }
}
