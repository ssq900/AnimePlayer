import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// WebView 抓取引擎抽象
abstract class WebViewEngine {
  /// 使用 WebView 加载网页并返回纯 HTML
  Future<String> fetchHtml(String url);
}

class InAppWebViewEngine implements WebViewEngine {
  // 保证同一时间只有一个 WebView 实例在运行，防止内存溢出/闪退
  static final _SerialLock _lock = _SerialLock();

  @override
  Future<String> fetchHtml(String url) async {
    return _lock.run(() => _doFetch(url));
  }

  Future<String> _doFetch(String url) async {
    final completer = Completer<String>();
    HeadlessInAppWebView? headlessWebView;

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
          // 伪装成手机端浏览器
          userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ),
        onLoadStop: (controller, loadedUrl) async {
          // 等待 1.5 秒，给前端 JS (如 Vue/React) 渲染 DOM 的时间
          await Future.delayed(const Duration(milliseconds: 1500));
          
          try {
            // 注入 JS 获取完整的 HTML
            final html = await controller.evaluateJavascript(
              source: "document.documentElement.outerHTML",
            );
            if (!completer.isCompleted) {
              completer.complete(html.toString());
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('JS 执行失败: $e'));
            }
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted) {
            completer.completeError(Exception('WebView 加载失败: ${error.description}'));
          }
        },
      );

      await headlessWebView.run();

      // 强制 20 秒超时熔断
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('WebView 加载超时 (20s)'),
      );
    } finally {
      // 🔥 核心：无论成功还是失败，必须销毁 WebView 释放内存
      await headlessWebView?.dispose();
    }
  }
}

/// 内部串行锁
class _SerialLock {
  Future<void> _chain = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
