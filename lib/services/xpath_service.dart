import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/rule.dart';

class XPathService {
  Future<String> fetchHtml(String url) async {
    final completer = Completer<String>();
    HeadlessInAppWebView? webView;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useHybridComposition: true,
        ),
        onProgressChanged: (controller, progress) async {
          if (progress >= 50 && !completer.isCompleted) {
            try {
              await Future.delayed(const Duration(milliseconds: 500));
              final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
              if (html != null && html.toString().length > 500) {
                completer.complete(html.toString());
              }
            } catch (_) {}
          }
        },
        onLoadStop: (controller, url) async {
          if (!completer.isCompleted) {
            try {
              final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
              if (html != null) completer.complete(html.toString());
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
      final result = await completer.future.timeout(const Duration(seconds: 30));
      return result;
    } catch (e) {
      throw Exception('请求异常: $e');
    } finally {
      if (webView != null) {
        await webView.dispose();
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
      // 修复：使用 matchesSelector 而不是 matches
      if (container.matchesSelector(itemSelector)) {
        items = [container];
      } else {
        // 修复：显式转换为 List<Element>
        items = container.querySelectorAll(itemSelector).cast<Element>();
      }
    } catch (_) {
      items = container.querySelectorAll(itemSelector).cast<Element>();
    }
        
    return items.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.attributes['title'] ?? anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      // 修复：传入 rule 参数
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
      return Uri.parse(baseUrl).resolve(href).toString();
    } catch (_) {
      return href;
    }
  }

  String _cleanText(String? t) => (t ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
