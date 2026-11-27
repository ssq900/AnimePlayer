import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:gbk_codec/gbk_codec.dart';
import '../models/rule.dart';

class XPathParseException implements Exception {
  final String message;
  XPathParseException(this.message);
  @override
  String toString() => 'XPathParseException: $message';
}

class _SerialLock {
  Future<void> _chain = Future.value();
  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

class XPathService {
  final _webViewLock = _SerialLock();

  static const _httpHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    final url = buildSearchUrl(rule.baseUrl, keyword);
    String html;
    try {
      html = await _fetchHttp(url);
    } catch (_) {
      html = await _webViewLock.run(() => _fetchWithWebView(url));
    }
    return parseSearchPage(html, rule);
  }

  String buildSearchUrl(String baseUrl, String keyword) {
    final encoded = Uri.encodeComponent(keyword);
    if (baseUrl.contains('{keyword}')) {
      return baseUrl.replaceAll('{keyword}', encoded);
    }
    return baseUrl;
  }

  Future<String> fetchHtml(String url) async {
    try {
      return await _fetchHttp(url);
    } catch (_) {
      return await _webViewLock.run(() => _fetchWithWebView(url));
    }
  }

  Future<String> _fetchHttp(String url) async {
    final resp = await http.get(Uri.parse(url), headers: _httpHeaders).timeout(const Duration(seconds: 12));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final contentType = resp.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('gbk') || contentType.toLowerCase().contains('gb2312')) {
      return gbk.decode(resp.bodyBytes);
    }
    try {
      return utf8.decode(resp.bodyBytes);
    } catch (_) {
      try { return gbk.decode(resp.bodyBytes); } catch (_) { return resp.body; }
    }
  }

  Future<String> _fetchWithWebView(String url) async {
    throw UnimplementedError('请将原项目 WebView 逻辑填入此方法');
  }

  // ⚠️ 修复了返回类型，适配 DetailPage 的 List<EpisodeItem>
  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    // 这里只是占位，如果原项目里有具体解析逻辑，请把之前代码里的内容粘进来
    return [];
  }

  XmlDocument parseHtml(String html) {
    final cleaned = _cleanHtml(html);
    try {
      return XmlDocument.parse(cleaned);
    } on XmlException catch (e) {
      throw XPathParseException('HTML 解析失败: ${e.message}');
    }
  }

  String _cleanHtml(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<(br|hr|img|input|meta|link|area|base|col|embed|param|source|track|wbr)([^>]*?)/?>', caseSensitive: false), '<\$1\$2/>');
    s = s.replaceAll('&nbsp;', '&#160;');
    return s;
  }

  List<XmlElement> findElements(XmlNode context, String expr) {
    if (expr.trim().isEmpty) return const [];
    try {
      return context.findAllElements(expr).toList();
    } catch (e) {
      throw XPathParseException('XPath "$expr" 执行失败: $e');
    }
  }

  List<SearchResult> parseSearchPage(String html, AnimeRule rule) {
    final doc = parseHtml(html);
    final containers = findElements(doc, rule.searchSelector);
    if (containers.isEmpty) return [];

    final results = <SearchResult>[];
    for (final container in containers) {
      final links = findElements(container, rule.animeLinkSelector);
      for (final a in links) {
        final title = a.innerText.trim();
        final href = a.getAttribute('href')?.trim() ?? '';
        if (title.isEmpty || href.isEmpty) continue;
        results.add(SearchResult(
          title: title,
          link: _resolveUrl(rule.baseUrl, href),
          rule: rule,
        ));
      }
    }
    return results;
  }

  String _resolveUrl(String base, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try { return Uri.parse(base).resolve(path).toString(); } catch (_) { return path; }
  }
}
