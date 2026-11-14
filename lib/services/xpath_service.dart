import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/rule.dart';

class XPathService {
  Future<String> fetchHtml(String url, {String? waitForSelector}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('非法的协议请求');
    }

    final completer = Completer<String>();
    HeadlessInAppWebView? webView;
    bool isDisposed = false;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // 修复安全配置：兼容模式而非无条件允许
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        ),
        onLoadStop: (controller, url) async {
          if (completer.isCompleted) return;
          try {
            // 智能等待：如果有目标选择器，则轮询检查
            if (waitForSelector != null && waitForSelector.isNotEmpty) {
              for (int i = 0; i < 10; i++) {
                if (completer.isCompleted) return;
                final hasElement = await controller.evaluateJavascript(
                    source: "document.querySelector('${waitForSelector.replaceAll("'", "\\'")}') != null"
                );
                if (hasElement == true) break;
                await Future.delayed(const Duration(milliseconds: 500));
              }
            } else {
              // 无目标时的默认延迟
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
            completer.completeError(Exception("加载失败: ${error.description}"));
          }
        },
      );

      await webView.run();
      // 监听超时，如果超时，强制给 Completer 塞入错误，防止后续 await 永久挂起
      return await completer.future.timeout(const Duration(seconds: 20), onTimeout: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('网页加载超时'));
        }
        return '';
      });
    } catch (e) {
      throw Exception('请求异常: $e');
    } finally {
      if (webView != null && !isDisposed) {
        isDisposed = true;
        try {
          await webView.dispose();
        } catch (_) {}
      }
    }
  }

  // WebView 返回的已经是渲染后的标准 UTF-8，不需要 GBK 额外处理
  Document _parse(String htmlText) => html_parser.parse(htmlText);

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

    // 传入目标选择器，让 WebView 智能等待该元素出现
    final htmlText = await fetchHtml(searchUrl, waitForSelector: rule.animeLinkSelector);
    final doc = _parse(htmlText);
    final container = doc.querySelector(rule.searchSelector);
    if (container == null) return [];

    final String itemSelector = rule.animeLinkSelector.trim().isEmpty ? '*' : rule.animeLinkSelector;
    
    List<Element> items = [];
    try {
      final children = container.querySelectorAll(itemSelector);
      if (children.isNotEmpty) {
        items = children.cast<Element>();
      } else {
        items = [container];
      }
    } catch (_) {
      items = [container];
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
    final htmlText = await fetchHtml(detailUrl, waitForSelector: rule.episodeListSelector);
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
    final htmlText = await fetchHtml(episodeUrl, waitForSelector: rule.episodeLinkSelector);
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
      final scheme = Uri.parse(resolved).scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return '';
      return resolved;
    } catch (_) {
      return '';
    }
  }

  String _cleanText(String? t) => (t ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
