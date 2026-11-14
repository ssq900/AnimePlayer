import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
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
              final safeSelector = jsonEncode(waitForSelector);
              for (int i = 0; i < 15; i++) { 
                if (completer.isCompleted) return;
                final hasElement = await controller.evaluateJavascript(
                    source: "document.querySelector($safeSelector) != null"
                );
                if (hasElement == true) break;
                await Future.delayed(const Duration(milliseconds: 500));
              }
            } else {
              await Future.delayed(const Duration(milliseconds: 1000));
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

  Document _parse(String htmlText) => html_parser.parse(htmlText);

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    if (rule.searchSelector.trim().isEmpty) {
      throw Exception('规则错误: 搜索结果容器选择器 (searchSelector) 为空');
    }
    
    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    if (searchUrl.contains('{keyword}')) {
      searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    } else {
      final sep = searchUrl.contains('?') ? '&' : '?';
      searchUrl = '$searchUrl${sep}wd=$encoded';
    }

    final htmlText = await fetchHtml(searchUrl, waitForSelector: rule.searchSelector);
    final doc = _parse(htmlText);
    
    final container = doc.querySelector(rule.searchSelector);
    if (container == null) {
      throw Exception('规则不匹配: 网页中未找到容器 "${rule.searchSelector}"');
    }

    final String itemSelector = rule.animeLinkSelector.trim().isEmpty ? '*' : rule.animeLinkSelector;
    List<Element> items = [];
    try {
      final children = container.querySelectorAll(itemSelector);
      items = children.isNotEmpty ? children.cast<Element>() : [container];
    } catch (_) {
      items = [container];
    }
        
    return items.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.attributes['title'] ?? anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
    })
    // 【核心修复】：相关性及有效性过滤
    .where((r) {
      if (r.link.isEmpty || r.title.isEmpty) return false;
      
      // 1. 过滤掉主页和过短的链接
      final uri = Uri.tryParse(r.link);
      if (uri == null) return false;
      final path = uri.path;
      if (path == '/' || path.isEmpty || (path.length < 5 && !path.contains('anime'))) {
        return false;
      }

      // 2. 必须包含搜索词（过滤推荐位、侧边栏、无职转生等）
      final cleanKeyword = keyword.toLowerCase().trim();
      final cleanTitle = r.title.toLowerCase().trim();
      
      // 允许简单的空格忽略匹配
      if (!cleanTitle.contains(cleanKeyword) && !cleanKeyword.contains(cleanTitle)) {
        return false;
      }
      
      return true;
    }).toList();
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    if (rule.episodeListSelector.trim().isEmpty) throw Exception('规则错误: 剧集列表选择器为空');
    final htmlText = await fetchHtml(detailUrl, waitForSelector: rule.episodeListSelector);
    final doc = _parse(htmlText);
    final list = doc.querySelectorAll(rule.episodeListSelector);
    if (list.isEmpty) throw Exception('网页中未找到剧集列表，可能规则失效');
    
    return list.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return EpisodeItem(title: title, link: _absolute(rule.baseUrl, href));
    }).where((e) => e.link.isNotEmpty).toList();
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    if (rule.episodeLinkSelector.trim().isEmpty) return episodeUrl;
    final htmlText = await fetchHtml(episodeUrl, waitForSelector: rule.episodeLinkSelector);
    final doc = _parse(htmlText);
    final el = doc.querySelector(rule.episodeLinkSelector);
    if (el == null) throw Exception('网页中未找到视频播放地址');

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
