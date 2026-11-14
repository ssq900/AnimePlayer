import 'dart:convert';
import 'package:http/http.dart' as http;

class KazumiService {
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
        final resp = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
        }
        errors.add('${Uri.parse(url).host} 状态码: ${resp.statusCode}');
      } catch (e) {
        errors.add('${Uri.parse(url).host} 异常: $e');
      }
    }
    throw Exception('所有镜像均拉取失败:\n${errors.join('\n')}');
  }

  Future<Map<String, dynamic>> fetchRuleDetail(String fileName) async {
    final urls = _indexUrls.map((u) => u.replaceAll('index.json', fileName)).toList();
    List<String> errors = [];
    for (final url in urls) {
      try {
        final resp = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) { errors.add('${Uri.parse(url).host} 异常: $e'); }
    }
    throw Exception('规则详情拉取失败:\n${errors.join('\n')}');
  }

  /// 直接提取并映射 Kazumi 原生 XPath 字段
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
    if (chapter != null && chapter is Map) {
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
