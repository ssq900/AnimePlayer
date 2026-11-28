sealed class AppFailure implements Exception {
  final String message;
  final String? sourceName;

  const AppFailure(this.message, {this.sourceName});

  @override
  String toString() => message;
}

/// 网络错误（如断网、DNS 解析失败）
class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.sourceName});
}

/// 请求超时
class TimeoutFailure extends AppFailure {
  const TimeoutFailure({super.sourceName}) : super('请求超时');
}

/// 解析失败（如 HTML 格式错误、XPath 未命中）
class ParseFailure extends AppFailure {
  const ParseFailure(super.message, {super.sourceName});
}

/// 规则校验失败
class RuleValidationFailure extends AppFailure {
  const RuleValidationFailure(super.message, {super.sourceName});
}

/// WebView 验证挑战（如触发 Cloudflare 盾）
class WebViewChallengeFailure extends AppFailure {
  const WebViewChallengeFailure({super.sourceName}) : super('触发站点安全验证，需切换 WebView 模式');
}

/// 聚合搜索时，多个源同时失败的错误集合
class AggregateFailure extends AppFailure {
  final List<AppFailure> failures;
  AggregateFailure(this.failures) : super('${failures.length} 个源搜索失败');
}
