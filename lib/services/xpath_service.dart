import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xpath.dart'; // 核心修复：引入 xpath 扩展
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

  String _cleanHtmlForXml(String html) {
    try {
      final doc = html_parser.parse(html);
      return doc.outerHtml;
    } catch (_) {
      return html;
    }
  }

  String _normalizeXpath(String xpath) {
    String res = xpath.trim();
    if (!res.startsWith('//') && !res.startsWith('/') && !res.startsWith('./')) {
      res = '//$res';
    }
    return res;
  }

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

    final rawHtml = await fetchHtml(searchUrl);
    final safeHtml = _cleanHtmlForXml(rawHtml);
    
    final document = xml.XmlDocument.parse(safeHtml);
    final searchXpath = _normalizeXpath(rule.searchSelector);
    
    // 核心修复：使用 document.xpath() 进行查询
    final containerNodes = document.xpath(searchXpath);
    if (containerNodes.isEmpty) {
      throw Exception('规则不匹配: 网页中未找到容器 "${rule.searchSelector}"，可能网站已改版');
    }

    List<xml.XmlNode> items = [];
    
    if (rule.animeLinkSelector.isNotEmpty) {
      final linkXpath = _normalizeXpath(rule.animeLinkSelector);
      for (var node in containerNodes) {
        // 核心修复：对每个容器节点调用 .xpath()
        final subNodes = node.xpath(linkXpath);
        items.addAll(subNodes);
      }
    }

    if (items.isEmpty) {
      items = containerNodes.toList();
    }

    return items.whereType<xml.XmlElement>().map((el) {
      final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
      final title = el.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      if (el.name.local != 'a' && href.isEmpty) {
        try {
          final innerA = el.findElements('a').firstOrNull;
          if (innerA != null) {
            return SearchResult(
              title: innerA.innerText.replaceAll(RegExp(r'\s+'), ' ').trim(),
              link: _absolute(rule.baseUrl, innerA.getAttribute('href') ?? ''),
              rule: rule
            );
          }
        } catch (_) {}
      }

      return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
    })
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
    
    final rawHtml = await fetchHtml(detailUrl);
    final safeHtml = _cleanHtmlForXml(rawHtml);
    
    final document = xml.XmlDocument.parse(safeHtml);
    final episodeXpath = _normalizeXpath(rule.episodeListSelector);
    // 核心修复：使用 document.xpath()
    final nodes = document.xpath(episodeXpath);
    
    if (nodes.isEmpty) throw Exception('网页中未找到剧集列表，可能规则失效');
    
    return nodes.whereType<xml.XmlElement>().map((el) {
      final href = el.getAttribute('href') ?? '';
      final title = el.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      return EpisodeItem(title: title, link: _absolute(rule.baseUrl, href));
    }).where((e) => e.link.isNotEmpty).toList();
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    if (rule.episodeLinkSelector.trim().isEmpty) return episodeUrl;
    
    final rawHtml = await fetchHtml(episodeUrl);
    final safeHtml = _cleanHtmlForXml(rawHtml);
    
    final document = xml.XmlDocument.parse(safeHtml);
    final linkXpath = _normalizeXpath(rule.episodeLinkSelector);
    // 核心修复：使用 document.xpath()
    final nodes = document.xpath(linkXpath);
    
    if (nodes.isEmpty) throw Exception('网页中未找到视频播放地址');

    final el = nodes.whereType<xml.XmlElement>().firstOrNull;
    if (el == null) return episodeUrl;

    final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
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
}
