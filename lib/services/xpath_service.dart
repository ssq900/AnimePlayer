import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xpath.dart';
import '../models/rule.dart';
import 'exceptions.dart';
import 'network_client.dart';

class XPathService {
  final _client = NetworkClient().client;

  Future<String> fetchHtml(
    String url, {
    String? waitForSelector,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw NetworkException('非法的协议请求: 仅支持 HTTP/HTTPS');
    }

    // 1. 优先尝试轻量级 HTTP 请求
    try {
      final resp = await _client.get(
        Uri.parse(url), 
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
        }
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = resp.body;
        // 如果网页包含 Cloudflare 挑战或体积太小，则视为拦截，降级到 WebView
        if (!body.contains('cf-browser-verification') && body.length > 1000) {
          return body;
        }
      }
    } catch (e) {
      debugPrint('[XPathService] HTTP probe failed, falling back to WebView: $e');
    }

    // 2. 降级到 Headless WebView (针对动态渲染或防爬盾)
    return _fetchWithWebView(url, waitForSelector, timeout);
  }

  Future<String> _fetchWithWebView(String url, String? waitForSelector, Duration timeout) async {
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
              for (int i = 0; i < 10; i++) { 
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

  // ... _cleanHtmlForXml, _normalizeXpath 与搜索解析逻辑完全保持不变 ...
  // （为节省篇幅，这里省略，请复制你现有的这部分代码过来即可）
}
