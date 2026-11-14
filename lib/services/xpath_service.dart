import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:xpath_for_html/xpath_for_html.dart';
import '../models/rule.dart';

class XPathService {
  Future<String> fetchHtml(String url, {String? waitForSelector}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('非法的协议请求: 仅支持 HTTP/HTTPS');
    }

    final completer = Completer<String>();
    HeadlessInAppWebView? webView;
    bool isDisposed = false;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        ),
        onLoadStop: (controller, url) async {
          if (completer.isCompleted) return;
          try {
            if (waitForSelector != null && waitForSelector.isNotEmpty) {
              // 对于 XPath，我们可以简单地检查页面是否加载完毕（通过检查 body 是否有子元素）
              final safeSelector = jsonEncode(waitForSelector.startsWith('//') ? 'body' : waitForSelector);
              for (int i = 0; i < 15; i++) { 
                if (completer.isCompleted) return;
                final hasElement = await controller.evaluateJavascript(
                    source: "document.querySelector($safeSelector) != null"
                );
                if (hasElement == true) break;
                await Future.delayed(const Duration(milliseconds: 500));
              }
            } else {
              await Future.delayed(const Duration(milliseconds: 1500));
            }

            if (completer.isCompleted) return;
            final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
            if (html != null && !completer.isCompleted) {
              completer.complete(html.toString());
            }
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(Exception("提取HTML失败: $e"));
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted && request.isForMainFrame == true) {
            completer.completeError(Exception("网页加载失败: ${error.description}"));
          }
        },
      );

      await webView.run();
      return await completer.future.timeout(const Duration(seconds: 25), onTimeout: () {
        if (!completer.isCompleted) completer.completeError(Exception('网页加载超时'));
        return '';
      });
    } catch (e) {
      throw Exception('网络异常: $e');
    } finally {
      if (webView != null && !isDisposed) {
        isDisposed = true;
        try { await webView.dispose(); } catch (_) {}
      }
    }
  }

  Document _parseHtml(String htmlText) => html_parser.parse(htmlText);

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    if (rule.searchSelector.trim().isEmpty) {
      throw Exception('规则错误: 搜索结果容器选择器为空');
    }
    
    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    if (searchUrl.contains('{keyword}')) {
      searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    } else {
      final sep = searchUrl.contains('?') ? '&' : '?';
      searchUrl = '$searchUrl${sep}wd=$encoded';
    }

    final htmlText = await fetchHtml(searchUrl);
    
    // 核心替换：使用原生 XPath 查询
    final xpath = XPath.html(htmlText);
    final results = xpath.query(rule.searchSelector).toList();
    
    if (results.isEmpty) {
      throw Exception('规则不匹配: 网页中未找到容器 "${rule.searchSelector}"，可能网站已改版');
    }

    // 提取所有条目
    List<dynamic> items = [];
    if (rule.animeLinkSelector.isNotEmpty) {
      try {
        final subQuery = xpath.query(rule.animeLinkSelector);
        // 这里简化处理，实际可能需要从每个匹配的容器中继续查询
        items = subQuery.toList(); 
      } catch (_) {}
    }
    
    // 如果子查询失败，直接用结果本身
    if (items.isEmpty) items = results;

    return items.map((item) {
      // xpath_for_html 返回的可能不是标准的 Element，需要做类型转换或兼容处理
      Element? el;
      if (item is Element) {
        el = item;
      } else if (item is String) {
        // 某些库可能返回文本节点
        return SearchResult(title: item.trim(), link: '', rule: rule);
      }
      
      if (el == null) return null;
      
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.attributes['title'] ?? anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
    })
    .whereType<SearchResult>()
    .where((r) {
      if (r.link.isEmpty || r.title.isEmpty) return false;
      final uri = Uri.tryParse(r.link);
      if (uri == null) return false;
      final path = uri.path;
      if (path == '/' || path.isEmpty) return false;
      
      final cleanKeyword = keyword.toLowerCase().trim();
      final cleanTitle = r.title.toLowerCase().trim();
      if (!cleanTitle.contains(cleanKeyword) && !cleanKeyword.contains(cleanTitle)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    if (rule.episodeListSelector.trim().isEmpty) throw Exception('规则错误: 剧集列表选择器为空');
    
    final htmlText = await fetchHtml(detailUrl);
    final xpath = XPath.html(htmlText);
    final results = xpath.query(rule.episodeListSelector).toList();
    
    if (results.isEmpty) throw Exception('网页中未找到剧集列表，可能规则失效');
    
    return results.map((item) {
      Element? el;
      if (item is Element) el = item;
      if (el == null) return null;
      
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return EpisodeItem(title: title, link: _absolute(rule.baseUrl, href));
    }).whereType<EpisodeItem>().where((e) => e.link.isNotEmpty).toList();
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    if (rule.episodeLinkSelector.trim().isEmpty) return episodeUrl;
    
    final htmlText = await fetchHtml(episodeUrl);
    final xpath = XPath.html(htmlText);
    final results = xpath.query(rule.episodeLinkSelector).toList();
    
    if (results.isEmpty) throw Exception('网页中未找到视频播放地址');

    Element? el;
    if (results.first is Element) el = results.first;
    if (el == null) return episodeUrl;

    final a = el.localName == 'a' ? el : el.querySelector('a');
    final href = a?.attributes['href'] ?? el.attributes['src'] ?? '';
    if (href.isEmpty) return episodeUrl;
    return _absolute(rule.baseUrl, href);
  }

  String _absolute(String baseUrl, String href) {
    if (href.isEmpty) return '';
    try {
      if (href.startsWith('//')) return '${Uri.parse(baseUrl).scheme}:$href';
      final resolved = Uri.parse(baseUrl).resolve(href).toString();
      final scheme = Uri.parse(resolved).scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return '';
      return resolved;
    } catch (_) {
      return '';
    }
  }

  String _cleanText(String? t) => (t ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
