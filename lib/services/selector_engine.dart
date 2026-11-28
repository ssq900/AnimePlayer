import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xpath.dart';
import '../models/rule.dart';
import '../core/exceptions.dart';

extension XmlNodeExt on xml.XmlNode {
  String get textContent {
    return descendants.whereType<xml.XmlText>().map((n) => n.value).join();
  }
}

class SelectorEngine {
  static const _httpHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  };

  // ==================== 核心路由：根据策略决定抓取方式 ====================
  Future<String> fetchHtmlWithStrategy(AnimeRule rule, String url, {String? waitForSelector}) async {
    if (rule.fetchStrategy == 'webview' || rule.fetchStrategy == 'iframe') {
      debugPrint('[SelectorEngine] 策略要求直接使用 WebView: $url');
      return _fetchWithWebView(url, waitForSelector: waitForSelector);
    }
    
    // direct 模式：先尝试 HTTP 直连
    try {
      return await _fetchDirect(url);
    } catch (e) {
      debugPrint('[SelectorEngine] HTTP 直连失败，自动降级 WebView: $e');
      return _fetchWithWebView(url, waitForSelector: waitForSelector);
    }
  }

  // ==================== 具体执行器：HTTP 直连 ====================
  Future<String> _fetchDirect(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw NetworkException('非法的协议请求: 仅支持 HTTP/HTTPS');
    }
    final resp = await http.get(Uri.parse(url), headers: _httpHeaders).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      // 简单拦截 CF 盾
      if (!body.contains('cf-browser-verification') && body.length > 1000) {
        return body;
      }
      throw NetworkException('疑似触发反爬盾');
    }
    throw NetworkException('HTTP 状态码异常: ${resp.statusCode}');
  }

  // ==================== 具体执行器：WebView ====================
  Future<String> _fetchWithWebView(String url, {String? waitForSelector, Duration timeout = const Duration(seconds: 25)}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw NetworkException('非法的协议请求: 仅支持 HTTP/HTTPS');
    }

    final completer = Completer<String>();
    HeadlessInAppWebView? webView;
    bool isDisposed = false;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true, 
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE
        ),
        onLoadStop: (controller, pageUrl) async {
          if (completer.isCompleted) return;
          try {
            if (waitForSelector != null && waitForSelector.isNotEmpty) {
              final safeSelector = jsonEncode(waitForSelector.startsWith('//') ? 'body' : waitForSelector);
              for (int i = 0; i < 10; i++) { 
                if (completer.isCompleted) return;
                final hasElement = await controller.evaluateJavascript(source: "document.querySelector($safeSelector) != null");
                if (hasElement == true) break;
                await Future.delayed(const Duration(milliseconds: 500));
              }
            } else {
              await Future.delayed(const Duration(milliseconds: 1500));
            }
            if (completer.isCompleted) return;
            final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
            if (html != null && !completer.isCompleted) completer.complete(html.toString());
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(NetworkException("提取HTML失败: $e"));
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted && request.isForMainFrame == true) {
             completer.completeError(NetworkException("网页加载失败: ${error.description}"));
          }
        },
      );

      await webView.run();
      return await completer.future.timeout(timeout, onTimeout: () => throw NetworkException('网页加载超时 (>${timeout.inSeconds}s)'));
    } catch (e) {
      if (e is AppException) rethrow;
      throw NetworkException('网络请求异常: $e');
    } finally {
      if (webView != null && !isDisposed) {
        isDisposed = true;
        try { await webView.dispose(); } catch (_) {}
      }
    }
  }

  // ==================== 调试器兼容用的旧方法 ====================
  Future<String> fetchHtml(String url, {String? waitForSelector}) async {
    // 调试器没有 rule 对象，默认走 direct 降级 webview
    try {
      return await _fetchDirect(url);
    } catch (e) {
      return _fetchWithWebView(url, waitForSelector: waitForSelector);
    }
  }

  // ==================== 业务查询接口 ====================
  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    if (rule.searchSelector.trim().isEmpty && rule.searchSelectorCss.trim().isEmpty) {
      throw ParseException('规则错误: 搜索结果容器选择器为空');
    }

    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    if (searchUrl.contains('{keyword}')) {
      searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    } else {
      searchUrl = '$searchUrl${searchUrl.contains('?') ? '&' : '?'}wd=$encoded';
    }

    // 🔥 使用策略路由
    final rawHtml = await fetchHtmlWithStrategy(rule, searchUrl, waitForSelector: rule.searchSelectorCss.isNotEmpty ? rule.searchSelectorCss : null);

    if (rule.isCssBased && rule.searchSelectorCss.isNotEmpty) {
      return _searchWithCss(rawHtml, rule, keyword);
    } else {
      return _searchWithXPath(rawHtml, rule, keyword);
    }
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    // 🔥 使用策略路由
    final rawHtml = await fetchHtmlWithStrategy(rule, detailUrl);

    if (rule.isCssBased && rule.episodeListSelectorCss.isNotEmpty) {
      final doc = html_parser.parse(rawHtml);
      final nodes = doc.querySelectorAll(rule.episodeListSelectorCss);
      if (nodes.isEmpty) throw ParseException('未找到剧集列表 (CSS)');
      return nodes.map((el) => EpisodeItem(
        title: el.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        link: _absolute(rule.baseUrl, el.attributes['href'] ?? '')
      )).where((e) => e.link.isNotEmpty).toList();
    } else {
      if (rule.episodeListSelector.trim().isEmpty) throw ParseException('剧集列表选择器为空 (XPath)');
      final doc = _parseHtmlToXmlDoc(rawHtml);
      final nodes = doc.xpath(_normalizeXpath(rule.episodeListSelector));
      if (nodes.isEmpty) throw ParseException('未找到剧集列表 (XPath)');
      return nodes.whereType<xml.XmlElement>().map((el) => EpisodeItem(
        title: el.textContent.trim(),
        link: _absolute(rule.baseUrl, el.getAttribute('href') ?? '')
      )).where((e) => e.link.isNotEmpty).toList();
    }
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    if (rule.episodeLinkSelector.trim().isEmpty && rule.episodeLinkSelectorCss.trim().isEmpty) {
      return episodeUrl;
    }
    
    // 🔥 使用策略路由
    final rawHtml = await fetchHtmlWithStrategy(rule, episodeUrl);

    if (rule.isCssBased && rule.episodeLinkSelectorCss.isNotEmpty) {
      final doc = html_parser.parse(rawHtml);
      final el = doc.querySelector(rule.episodeLinkSelectorCss);
      if (el == null) throw ParseException('未找到播放地址 (CSS)');
      final href = el.attributes['href'] ?? el.attributes['src'] ?? '';
      return href.isEmpty ? episodeUrl : _absolute(rule.baseUrl, href);
    } else {
      final doc = _parseHtmlToXmlDoc(rawHtml);
      final nodes = doc.xpath(_normalizeXpath(rule.episodeLinkSelector));
      final el = nodes.whereType<xml.XmlElement>().firstOrNull;
      if (el == null) throw ParseException('未找到播放地址 (XPath)');
      final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
      return href.isEmpty ? episodeUrl : _absolute(rule.baseUrl, href);
    }
  }

  // ==================== 调试器专用公开接口 ====================
  xml.XmlDocument parseHtml(String rawHtml) => _parseHtmlToXmlDoc(rawHtml);

  List<xml.XmlElement> findElements(xml.XmlNode context, String expr) {
    if (expr.trim().isEmpty) return [];
    try {
      return context.xpath(_normalizeXpath(expr)).whereType<xml.XmlElement>().toList();
    } catch (e) {
      return [];
    }
  }

  // ==================== 内部工具方法 ====================
  xml.XmlDocument _parseHtmlToXmlDoc(String rawHtml) {
    final htmlDoc = html_parser.parse(rawHtml);
    htmlDoc.querySelectorAll('script, style, iframe, noscript').forEach((e) => e.remove());
    
    String cleaned = htmlDoc.outerHtml;
    cleaned = cleaned
        .replaceAll('&nbsp;', '&#160;')
        .replaceAllMapped(RegExp(r'&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)'), (match) => '&amp;');
    
    final voidTags = r'img|br|hr|meta|link|input|source|area|base|col|embed|param|track|wbr';
    cleaned = cleaned.replaceAllMapped(
      RegExp('<$voidTags\\b([^>]*?)(?<!/)>', caseSensitive: false), 
      (match) {
        String tag = match.group(0)!;
        if (tag.endsWith('/>')) return tag;
        return tag.substring(0, tag.length - 1) + ' />';
      }
    );

    return xml.XmlDocument.parse(cleaned);
  }

  String _normalizeXpath(String xpath) {
    String res = xpath.trim();
    if (!res.startsWith('//') && !res.startsWith('/') && !res.startsWith('./')) res = '//$res';
    final reg = RegExp(r"""\[@class\s*=\s*['"]([^'"]+)['"]\]""");
    res = res.replaceAllMapped(reg, (m) => "[contains(@class, '${m.group(1)!.trim()}')]");
    return res;
  }

  List<SearchResult> _searchWithCss(String rawHtml, AnimeRule rule, String keyword) {
    final doc = html_parser.parse(rawHtml);
    final containers = doc.querySelectorAll(rule.searchSelectorCss);
    if (containers.isEmpty) throw ParseException('未找到搜索容器 (CSS: ${rule.searchSelectorCss})');

    final items = <dom.Element>[];
    if (rule.animeLinkSelectorCss.isNotEmpty) {
      for (final c in containers) {
        items.addAll(c.querySelectorAll(rule.animeLinkSelectorCss));
      }
    } else {
      items.addAll(containers);
    }

    return _filterAndMapCssResults(items, rule, keyword);
  }

  List<SearchResult> _searchWithXPath(String rawHtml, AnimeRule rule, String keyword) {
    final doc = _parseHtmlToXmlDoc(rawHtml);
    final containerNodes = doc.xpath(_normalizeXpath(rule.searchSelector));
    if (containerNodes.isEmpty) throw ParseException('未找到搜索容器 (XPath: ${rule.searchSelector})');

    List<xml.XmlNode> items = [];
    if (rule.animeLinkSelector.isNotEmpty) {
      final linkXpath = _normalizeXpath(rule.animeLinkSelector);
      for (var node in containerNodes) { 
        items.addAll(node.xpath(linkXpath)); 
      }
    }
    if (items.isEmpty) items = containerNodes.toList();

    return _filterAndMapXmlResults(items, rule, keyword);
  }

  List<SearchResult> _filterAndMapCssResults(List<dom.Element> items, AnimeRule rule, String keyword) {
    return items.map((el) {
      final href = el.attributes['href'] ?? el.attributes['src'] ?? '';
      final title = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (el.localName != 'a' && href.isEmpty) {
        final innerA = el.querySelector('a');
        if (innerA != null) {
          return SearchResult(title: innerA.text.trim(), link: _absolute(rule.baseUrl, innerA.attributes['href'] ?? ''), rule: rule);
        }
      }
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
    }).where((r) {
      if (r.link.isEmpty || r.title.isEmpty) return false;
      final cleanKeyword = keyword.toLowerCase().trim();
      final cleanTitle = r.title.toLowerCase().trim();
      return cleanTitle.contains(cleanKeyword) || cleanKeyword.contains(cleanTitle);
    }).toList();
  }

  List<SearchResult> _filterAndMapXmlResults(List<xml.XmlNode> items, AnimeRule rule, String keyword) {
    return items.whereType<xml.XmlElement>().map((el) {
      final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
      final title = el.textContent.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (el.name.local != 'a' && href.isEmpty) {
        final innerA = el.findAllElements('a').firstOrNull;
        if (innerA != null) {
          return SearchResult(title: innerA.textContent.trim(), link: _absolute(rule.baseUrl, innerA.getAttribute('href') ?? ''), rule: rule);
        }
      }
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
    }).where((r) {
      if (r.link.isEmpty || r.title.isEmpty) return false;
      final cleanKeyword = keyword.toLowerCase().trim();
      final cleanTitle = r.title.toLowerCase().trim();
      return cleanTitle.contains(cleanKeyword) || cleanKeyword.contains(cleanTitle);
    }).toList();
  }

  String _absolute(String baseUrl, String href) {
    if (href.isEmpty) return '';
    try {
      if (href.startsWith('//')) return '${Uri.parse(baseUrl).scheme}:$href';
      final resolved = Uri.parse(baseUrl).resolve(href).toString();
      final scheme = Uri.parse(resolved).scheme.toLowerCase();
      return (scheme == 'http' || scheme == 'https') ? resolved : '';
    } catch (_) { return ''; }
  }
}
