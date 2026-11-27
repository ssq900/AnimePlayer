import 'dart:io';
import '../models/rule.dart';
import 'network_client.dart';

class FallbackManager {
  final List<SearchResult> _candidates;
  final Set<String> _triedUrls = {};
  final List<SearchResult> _sortedCandidates;
  int _attemptCount = 0;
  final int maxRetries;

  FallbackManager(List<SearchResult> candidates, {this.maxRetries = 2}) 
      : _candidates = List.from(candidates) {
    // 先按信任分从高到低排序
    _candidates.sort((a, b) => b.rule.trustScore.compareTo(a.rule.trustScore));
    _sortedCandidates = _candidates;
  }

  // 核心升级：获取下一个源时，顺带做一次极轻量的预探测
  Future<SearchResult?> getNextCandidate(String currentUrl) async {
    _triedUrls.add(currentUrl);
    if (_attemptCount >= maxRetries) return null;

    for (var result in _sortedCandidates) {
      if (_triedUrls.contains(result.link)) continue;
      
      // 如果是普通的视频直链，我们快速探测一下它的可用性
      if (_isDirectLink(result.link)) {
        final isAlive = await _probeLink(result.link);
        if (!isAlive) {
          _triedUrls.add(result.link);
          continue; // 死了就跳过，看下一个
        }
      }
      
      _attemptCount++;
      _triedUrls.add(result.link);
      return result;
    }
    return null;
  }

  bool _isDirectLink(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('.mp4');
  }

  // 轻量探活：发送 HEAD 请求（或限制 Range 的 GET），避免下载整个视频
  Future<bool> _probeLink(String url) async {
    try {
      final client = NetworkClient().client;
      // 很多流媒体服务器不支持 HEAD，我们用 GET 但只请求前 1 个字节
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close().timeout(const Duration(seconds: 3));
      
      // 如果返回 200 或 206，说明源存活
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    }
  }
}
