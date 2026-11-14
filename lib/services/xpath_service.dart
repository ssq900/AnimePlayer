import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xpath.dart';
import '../models/rule.dart';
import 'exceptions.dart'; // 引入统一异常库

class XPathService {
  Future<String> fetchHtml(
    String url, {
    String? waitForSelector,
    Duration timeout = const Duration(seconds: 25),
    int pollCount = 15,
  }) async {
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
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        ),
        onLoadStop: (controller, url) async {
          if (completer.isCompleted) return;
          try {
            if (waitForSelector != null && waitForSelector.isNotEmpty) {
              final safeSelector = jsonEncode(waitForSelector.startsWith('//') ? 'body' : waitForSelector);
              for (int i = 0; i < pollCount; i++) { 
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
      return await completer.future.timeout(timeout, onTimeout: () {
        throw NetworkException('网页加载超时 (>${timeout.inSeconds}s)');
      });
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

  String _cleanHtmlForXml(String html) {
    try {
      String cleaned = html;
      cleaned = cleaned.replaceAll(RegExp(r'<script\b[^>]*>([\s\S]*?)<\/script>'), '');
      cleaned = cleaned.replaceAll(RegExp(r'<style\b[^>]*>([\s\S]*?)<\/style>'), '');
      cleaned = cleaned.replaceAll(RegExp(r'<head\b[^>]*>([\s\S]*?)<\/head>'), '');
      cleaned = cleaned.replaceAll(RegExp(r'<(link|meta|img|br|hr|input)([^>]*?)(?<!/)>'), '<$1$2 />');
      final doc = html_parser.parse(cleaned);
      return doc.outerHtml;
    } catch (_) { return html; }
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
      final searchXpath = _normalizeXpath(rule.searchSelector);
      final containerNodes = document.xpath(searchXpath);
      if (containerNodes.isEmpty) throw ParseException('未找到搜索容器，可能网站已改版');

      List<xml.XmlNode> items = [];
      if (rule.animeLinkSelector.isNotEmpty) {
        final linkXpath = _normalizeXpath(rule.animeLinkSelector);
        for (var node in containerNodes) {
          items.addAll(node.xpath(linkXpath));
        }
      }
      if (items.isEmpty) items = containerNodes.toList();

      return items.whereType<xml.XmlElement>().map((el) {
        final href = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
        final title = el.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (el.name.local != 'a' && href.isEmpty) {
          try {
            final innerA = el.findElements('a').firstOrNull;
            if (innerA != null) {
              return SearchResult(title: innerA.innerText.trim(), link: _absolute(rule.baseUrl, innerA.getAttribute('href') ?? ''), rule: rule);
            }
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
