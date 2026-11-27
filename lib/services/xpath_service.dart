import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xpath.dart';
import '../models/rule.dart';
import 'exceptions.dart';
import 'network_client.dart';

class XPathService {
  final _client = NetworkClient().client;

  Future<String> fetchHtml(String url, {String? waitForSelector, Duration timeout = const Duration(seconds: 25)}) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw NetworkException('非法的协议请求: 仅支持 HTTP/HTTPS');
    }

    // 1. 轻量级 HTTP 探路
    try {
      final resp = await _client.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'}).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = resp.body;
        if (!body.contains('cf-browser-verification') && body.length > 1000) {
          return body;
        }
      }
    } catch (e) {
      debugPrint('[XPathService] HTTP probe failed, falling back to WebView: $e');
    }

    // 2. 降级到 Headless WebView
    final completer = Completer<String>();
    HeadlessInAppWebView? webView;
    bool isDisposed = false;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE),
        onLoadStop: (controller, url) async {
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
              await Future.delayed(const Duration(milliseconds: 1000));
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

  // 核心修复：使用更严谨的 HTML 到 XML 的清洗策略
  String _cleanHtmlForXml(String html) {
    try {
      String cleaned = html;

      // 1. 去掉脚本和样式，减少解析负担
      cleaned = cleaned.replaceAll(RegExp(r'<script\b[^>]*>([\s\S]*?)<\/script>', caseSensitive: false), '');
      cleaned = cleaned.replaceAll(RegExp(r'<style\b[^>]*>([\s\S]*?)<\/style>', caseSensitive: false), '');

      // 2. 交给容错极强的 html_parser 修复错位的标签 (例如 <div><a></div>)
      final doc = html_parser.parse(cleaned);
      cleaned = doc.outerHtml;

      // 3. 替换 HTML 特有实体，防止 xml 解析器报错
      cleaned = cleaned
          .replaceAll('&nbsp;', '&#160;')
          .replaceAll('&copy;', '&#169;')
          .replaceAll('&reg;', '&#174;')
          .replaceAll('&hellip;', '&#8230;');

      // 4. 拿到修复后的 HTML 后，暴力匹配所有空标签，强制自闭合
      final voidTags = r'img|br|hr|meta|link|input|source|area|base|col|embed|param|track|wbr';
      cleaned = cleaned.replaceAllMapped(
        RegExp('<$voidTags\\b([^>]*?)(?<!/)>', caseSensitive: false), 
        (match) {
          String tag = match.group(0)!;
          if (tag.endsWith('/>')) return tag;
          return tag.substring(0, tag.length - 1) + ' />';
        }
      );

      return cleaned;
    } catch (_) {
      // 如果 html_parser 都炸了，直接返回原文本，由外层捕获异常
      return html;
    }
  }

  String _normalizeXpath(String xpath) {
    String res = xpath.trim();
    if (!res.startsWith('//') && !res.startsWith('/') && !res.startsWith('./')) res = '//$res';
    final reg = RegExp(r"""\[@class\s*=\s*['"]([^'"]+)['"]\]""");
    res = res.replaceAllMapped(reg, (m) => "[contains(@class, '${m.group(1)!.trim()}')]");
    return res;
  }

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    if (rule.searchSelector.trim().isEmpty) throw ParseException('规则错误: 搜索结果容器选择器为空');
    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    if (searchUrl.contains('{keyword}')) searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    else searchUrl = '$searchUrl${searchUrl.contains('?') ? '&' : '?'}wd=$encoded';

    final rawHtml = await fetchHtml(searchUrl);
    try {
      final document = xml.XmlDocument.parse(_cleanHtmlForXml(rawHtml));
      final containerNodes = document.xpath(_normalizeXpath(rule.searchSelector));
      if (containerNodes.isEmpty) throw ParseException('未找到搜索容器 "${rule.searchSelector}"');

      List<xml.XmlNode> items = [];
      if (rule.animeLinkSelector.isNotEmpty) {
        final linkXpath = _normalizeXpath(rule.animeLinkSelector);
        for (var node in containerNodes) { items.addAll(node.xpath(linkXpath)); }
      }
      if (items.isEmpty) items = containerNodes.toList();

      return items.whereType<xml.XmlElement>().map((el) {
        final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
        final title = el.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (el.name.local != 'a' && href.isEmpty) {
          try {
            final innerA = el.findElements('a').firstOrNull;
            if (innerA != null) return SearchResult(title: innerA.innerText.trim(), link: _absolute(rule.baseUrl, innerA.getAttribute('href') ?? ''), rule: rule);
          } catch (_) {}
        }
        return SearchResult(title: title, link: _absolute(rule.baseUrl, href), rule: rule);
      })
      .where((r) {
        if (r.link.isEmpty || r.title.isEmpty) return false;
        final uri = Uri.tryParse(r.link);
        if (uri == null || uri.path == '/' || uri.path.isEmpty) return false;
        final cleanKeyword = keyword.toLowerCase().trim();
        final cleanTitle = r.title.toLowerCase().trim();
        return cleanTitle.contains(cleanKeyword) || cleanKeyword.contains(cleanTitle);
      }).toList();
    } catch (e) {
      if (e is AppException) rethrow;
      throw ParseException('网页内容解析失败: $e');
    }
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    if (rule.episodeListSelector.trim().isEmpty) throw ParseException('剧集列表选择器为空');
    final rawHtml = await fetchHtml(detailUrl);
    try {
      final document = xml.XmlDocument.parse(_cleanHtmlForXml(rawHtml));
      final nodes = document.xpath(_normalizeXpath(rule.episodeListSelector));
      if (nodes.isEmpty) throw ParseException('未找到剧集列表，可能规则失效');
      return nodes.whereType<xml.XmlElement>().map((el) {
        return EpisodeItem(title: el.innerText.trim(), link: _absolute(rule.baseUrl, el.getAttribute('href') ?? ''));
      }).where((e) => e.link.isNotEmpty).toList();
    } catch (e) {
      throw ParseException('解析剧集失败: $e');
    }
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    if (rule.episodeLinkSelector.trim().isEmpty) return episodeUrl;
    final rawHtml = await fetchHtml(episodeUrl);
    try {
      final document = xml.XmlDocument.parse(_cleanHtmlForXml(rawHtml));
      final nodes = document.xpath(_normalizeXpath(rule.episodeLinkSelector));
      final el = nodes.whereType<xml.XmlElement>().firstOrNull;
      if (el == null) throw ParseException('未找到视频播放地址');
      final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
      return href.isEmpty ? episodeUrl : _absolute(rule.baseUrl, href);
    } catch (e) {
      throw ParseException('解析视频链接失败: $e');
    }
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
