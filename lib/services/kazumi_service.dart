import 'dart:convert';
import 'package:http/http.dart' as http;

class KazumiService {
  // GitCode 国内镜像的索引文件地址（截图推荐）
  static const String _indexUrl =
      'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/index.json';

  // 备用索引地址
  static const List<String> _fallbackIndexUrls = [
    'https://ghproxy.net/https://raw.githubusercontent.com/Predidit/KazumiRules/main/index.json',
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/index.json',
  ];

  /// 拉取规则索引列表
  Future<List<Map<String, dynamic>>> fetchRuleIndex() async {
    final urls = [_indexUrl, ..._fallbackIndexUrls];
    dynamic lastError;

    for (final url in urls) {
      try {
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final List<dynamic> data = jsonDecode(resp.body);
          return data.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('索引拉取失败: $lastError');
  }

  /// 根据索引中的文件名，下载完整的规则 JSON
  Future<Map<String, dynamic>> fetchRuleDetail(String fileName) async {
    final urls = [
      'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/$fileName',
      'https://ghproxy.net/https://raw.githubusercontent.com/Predidit/KazumiRules/main/$fileName',
      'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/$fileName',
    ];
    dynamic lastError;

    for (final url in urls) {
      try {
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('规则详情拉取失败: $lastError');
  }

  // ========== 以下为已有的转换逻辑，保持不变 ==========
  String _xpathToCss(String xpath) {
    if (xpath.isEmpty) return '';
    String css = xpath.trim();
    if (css.startsWith('.') || css.startsWith('#')) return css;

    css = css.replaceAllMapped(RegExp(r'(\w+)\[(\d+)\]'), (match) {
      return '${match.group(1)}:nth-of-type(${match.group(2)})';
    });

    final regClass = RegExp(r'//\w+\[@class=["'']([^"'']+)["'']\]');
    if (regClass.hasMatch(css)) {
      final match = regClass.firstMatch(css);
      return '.${match!.group(1)!.replaceAll(' ', '.')}';
    }

    final regId = RegExp(r'//\w+\[@id=["'']([^"'']+)["'']\]');
    if (regId.hasMatch(css)) {
      final match = regId.firstMatch(css);
      return '#${match!.group(1)}';
    }

    css = css.replaceAll('//', ' ');
    css = css.replaceAll('/', ' > ');
    css = css.replaceAll(RegExp(r'\[@.*?\]'), '');
    css = css.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (css.startsWith('>')) css = css.substring(1).trim();
    return css;
  }

  Map<String, String> convertKazumiRule(Map<String, dynamic> kRule) {
    String baseUrl = kRule['searchURL'] ?? kRule['baseUrl'] ?? kRule['baseURL'] ?? '';
    baseUrl = baseUrl.replaceAll('@keyword', '{keyword}');
    if (!baseUrl.contains('{keyword}')) {
      baseUrl = kRule['baseURL'] ?? kRule['baseUrl'] ?? baseUrl;
    }

    final searchSelector = _xpathToCss(kRule['searchList'] ?? kRule['searchResult'] ?? '');
    final animeLinkSelector = _xpathToCss(kRule['searchName'] ?? kRule['searchResultItem'] ?? '');

    String episodeList = _xpathToCss(kRule['chapterRoads'] ?? kRule['episodeList'] ?? '');
    String episodeLink = 'video, iframe, source';

    final chapter = kRule['chapter'];
    if (chapter != null && chapter is Map) {
      episodeList = _xpathToCss(chapter['list'] ?? kRule['chapterRoads'] ?? '');
      final customLink = _xpathToCss(chapter['link'] ?? kRule['chapterResult'] ?? '');
      if (customLink.isNotEmpty) episodeLink = customLink;
    } else {
      final customLink = _xpathToCss(kRule['chapterResult'] ?? kRule['episodeLink'] ?? '');
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
