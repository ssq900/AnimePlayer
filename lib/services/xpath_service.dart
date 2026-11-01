import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/rule.dart';

class XPathService {
  Future<String> fetchHtml(String url) async {
    // 安全拦截：只允许 HTTP/HTTPS
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('非法的协议请求');
    }

    final completer = Completer<String>();
    HeadlessInAppWebView? webView;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // 移除写死的 Chrome 120，使用空值让系统 WebView 自己决定
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        onProgressChanged: (controller, progress) async {
          if (progress >= 50 && !completer.isCompleted) {
            try {
              // 延迟 500ms 等待异步渲染
              await Future.delayed(const Duration(milliseconds: 500));
              // 核心修复：延迟结束后必须再次检查是否已由 onLoadStop 完成
              if (!completer.isCompleted) {
                final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
                if (html != null && html.toString().length > 500) {
                  completer.complete(html.toString());
                }
              }
            } catch (_) {}
          }
        },
        onLoadStop: (controller, url) async {
          if (!completer.isCompleted) {
            try {
              final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
              if (html != null && !completer.isCompleted) {
                completer.complete(html.toString());
              }
            } catch (_) {}
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted && request.isForMainFrame == true) {
            completer.completeError(Exception("加载失败: ${error.description}"));
          }
        },
      );

      await webView.run();
      return await completer.future.timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('请求异常: $e');
    } finally {
      if (webView != null) {
        try {
          await webView.dispose();
        } catch (_) {
          // 忽略 dispose 异常，防止掩盖原始错误
        }
      }
    }
  }

  Document _parse(String htmlText) => html_parser.parse(htmlText, encoding: 'utf-8');

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    if (rule.searchSelector.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    
    if (searchUrl.contains('{keyword}')) {
      searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    } else {
      final sep = searchUrl.contains('?') ? '&' : '?';
      searchUrl = '$searchUrl${sep}wd=$encoded';
    }

    final htmlText = await fetchHtml(searchUrl);
    final doc = _parse(htmlText);
    final container = doc.querySelector(rule.searchSelector);
    if (container == null) return [];

    final String itemSelector = rule.animeLinkSelector.trim().isEmpty ? '*' : rule.animeLinkSelector;
    List<Element> items = [];
    
    try {
      if (container.matchesSelector(itemSelector)) {
        items = [container];
      } else {
        items = container.querySelectorAll(itemSelector).cast<Element>();
      }
    } catch (_) {
      items = container.querySelectorAll(itemSelector).cast<Element>();
    }
        
    return items.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.attributes['title'] ?? anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
    }).where((r) => r.link.isNotEmpty && r.title.isNotEmpty).toList();
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    if (rule.episodeListSelector.trim().isEmpty) return [];
    final htmlText = await fetchHtml(detailUrl);
    final doc = _parse(htmlText);
    final list = doc.querySelectorAll(rule.episodeListSelector);
    return list.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return EpisodeItem(title: title, link: _absolute(rule.baseUrl, href));
    }).where((e) => e.link.isNotEmpty).toList();
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    if (rule.episodeLinkSelector.trim().isEmpty) return episodeUrl;
    final htmlText = await fetchHtml(episodeUrl);
    final doc = _parse(htmlText);
    final el = doc.querySelector(rule.episodeLinkSelector);
    if (el == null) return episodeUrl;

    final a = el.localName == 'a' ? el : el.querySelector('a');
    final href = a?.attributes['href'] ?? el.attributes['src'] ?? '';
    if (href.isEmpty) return episodeUrl;
    return _absolute(rule.baseUrl, href);
  }

  String _absolute(String baseUrl, String href) {
    if (href.isEmpty) return '';
    try {
      final resolved = Uri.parse(baseUrl).resolve(href).toString();
      // 安全校验：防止 javascript: 伪协议注入
      final scheme = Uri.parse(resolved).scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        return '';
      }
      return resolved;
    } catch (_) {
      return '';
    }
  }

  String _cleanText(String? t) => (t ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
