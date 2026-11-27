import 'dart:convert';
import 'network_client.dart'; // 引入统一网络客户端
import 'exceptions.dart'; // 引入统一异常

class KazumiService {
  final _client = NetworkClient().client;

  static const List<String> _indexUrls = [
    'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/index.json',
    'https://ghproxy.net/https://raw.githubusercontent.com/Predidit/KazumiRules/main/index.json',
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/index.json',
  ];

  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  Future<List<Map<String, dynamic>>> fetchRuleIndex() async {
    List<String> errors = [];
    for (final url in _indexUrls) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is List) {
            return data.cast<Map<String, dynamic>>();
          }
          throw Exception('返回格式不是 List');
        }
        errors.add('${Uri.parse(url).host} 状态码: ${resp.statusCode}');
      } catch (e) {
        errors.add('${Uri.parse(url).host} 异常: $e');
      }
    }
    throw NetworkException('所有镜像均拉取失败:\n${errors.join('\n')}');
  }

  Future<Map<String, dynamic>> fetchRuleDetail(String fileName) async {
    final urls = _indexUrls.map((u) => u.replaceAll('index.json', fileName)).toList();
    List<String> errors = [];

    for (final url in urls) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
        errors.add('${Uri.parse(url).host} 状态码: ${resp.statusCode}');
      } catch (e) {
        errors.add('${Uri.parse(url).host} 异常: $e');
      }
    }
    throw NetworkException('规则详情拉取失败:\n${errors.join('\n')}');
  }

  String _xpathToCss(String xpath) {
    if (xpath.isEmpty) return '';
    String css = xpath.trim();
    if (css.startsWith('.') || css.startsWith('#') || css.startsWith('//')) {
      return css; // 如果是纯 CSS 或 原始 XPath，直接返回
    }
    
    // 兼容兜底逻辑
    css = css.replaceAll(RegExp(r'\[\d+\]'), '');
    css = css.replaceAll(RegExp(r':nth-of-type\(\d+\)'), '');
    css = css.replaceAll('//', ' ');
    css = css.replaceAll('/', ' > ');
    css = css.replaceAll(RegExp(r'\[@.*?\]'), '');
    css = css.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (css.startsWith('>')) css = css.substring(1).trim();
    
    if (css.isEmpty) return 'a';
    return css;
  }

  Map<String, String> convertKazumiRule(Map<String, dynamic> kRule) {
    String baseUrl = kRule['searchURL'] ?? kRule['baseUrl'] ?? kRule['baseURL'] ?? '';
    baseUrl = baseUrl.replaceAll('@keyword', '{keyword}');
    if (!baseUrl.contains('{keyword}')) {
      baseUrl = kRule['baseURL'] ?? kRule['baseUrl'] ?? baseUrl;
    }

    final searchSelector = kRule['searchList'] ?? kRule['searchResult'] ?? '';
    final animeLinkSelector = kRule['searchName'] ?? kRule['searchResultItem'] ?? '';
    
    String episodeList = kRule['chapterRoads'] ?? kRule['episodeList'] ?? '';
    String episodeLink = 'video, iframe, source';

    final chapter = kRule['chapter'];
    if (chapter != null) {
      if (chapter is! Map) {
        throw RuleFormatException('规则格式损坏："chapter" 字段应为对象，实际为 ${chapter.runtimeType}');
      }
      episodeList = chapter['list'] ?? kRule['chapterRoads'] ?? '';
      final customLink = chapter['link'] ?? kRule['chapterResult'] ?? '';
      if (customLink.isNotEmpty) episodeLink = customLink;
    } else {
      final customLink = kRule['chapterResult'] ?? kRule['episodeLink'] ?? '';
      if (customLink.isNotEmpty) episodeLink = customLink;
    }

    return {
      'name': kRule['name'] ?? '未命名规则',
      'baseUrl': baseUrl,
      'searchSelector': searchSelector,
      'animeLinkSelector': animeLinkSelector,
      'episodeListSelector': episodeList,
      'episodeLinkSelector': episodeLink,
    };
  }
}
