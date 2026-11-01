import 'package:flutter_test/flutter_test.dart';
import 'package:anime_aggregator/services/xpath_service.dart';
import 'package:anime_aggregator/models/rule.dart';

void main() {
  group('XPathService 测试', () {
    final service = XPathService();
    final mockRule = AnimeRule.empty();

    test('传入空选择器时返回空列表而非崩溃', () async {
      final rule = AnimeRule(
        id: '1', name: 'test', baseUrl: 'https://example.com',
        searchSelector: '', animeLinkSelector: '', episodeListSelector: '', episodeLinkSelector: '',
      );
      final results = await service.search(rule, 'keyword');
      expect(results, isEmpty);
    });

    test('传入非法 CSS 选择器时抛出可捕获的异常', () {
      // html 包在解析未闭合的括号时会抛出异常
      expect(() => parseFragment('<html></html>').querySelector('['), throwsA(anything));
    });
  });
}
