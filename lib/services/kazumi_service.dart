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
    dynamic lastError;
    for (final url in _indexUrls) {
      try {
        final resp = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final List<dynamic> data = jsonDecode(resp.body);
          return data.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('索引拉取失败，请检查网络: $lastError');
  }

  Future<Map<String, dynamic>> fetchRuleDetail(String fileName) async {
    final urls = [
      'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/$fileName',
      'https://ghproxy.net/https://raw.githubusercontent.com/Predidit/KazumiRules/main/$fileName',
      'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/$fileName',
    ];
    dynamic lastError;

    for (final url in urls) {
      try {
        final resp = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('规则详情拉取失败: $lastError');
  }

  String _xpathToCss(String xpath) {
    if (xpath.isEmpty) return '';
    String css = xpath.trim();
    if (css.startsWith('.') || css.startsWith('#')) return css;

    // 1. 处理 //tag[@class="a b"] -> .a.b
    final regClass = RegExp(r'''//\w+\[@class=["']([^"']+)["']\]''');
    if (regClass.hasMatch(css)) {
      final match = regClass.firstMatch(css);
      return '.${match!.group(1)!.replaceAll(' ', '.')}';
    }

    // 2. 处理 //tag[@id="x"] -> #x
    final regId = RegExp(r'''//\w+\[@id=["']([^"']+)["']\]''');
    if (regId.hasMatch(css)) {
      final match = regId.firstMatch(css);
      return '#${match!.group(1)}';
    }

    // 3. 处理 //tag[@attr="v"] -> tag[attr="v"]
    css = css.replaceAllMapped(RegExp(r'''//(\w+)\[@([^=]+)="([^"]+)"\]'''), (m) {
      return '${m[1]}[${m[2]}="${m[3]}"]';
    });

    // 4. 数字索引降级 -> :nth-of-type
    css = css.replaceAllMapped(RegExp(r'(\w+)\[(\d+)\]'), (match) {
      return '${match.group(1)}:nth-of-type(${match.group(2)})';
    });

    // 5. 基础路径清理
    css = css.replaceAll('//', ' ');
    css = css.replaceAll('/', ' > ');
    css = css.replaceAll(RegExp(r'\[@.*?\]'), '');
    css = css.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    if (css.startsWith('>')) css = css.substring(1).trim();
    
    if (css.isEmpty) return 'a';
    return css;
  }

  Map<String, String> convertKazumiRule(Map<String, dynamic> kRule) {
    // 兼容不同版本的字段名
    String baseUrl = kRule['searchURL'] ?? kRule['baseUrl'] ?? kRule['baseURL'] ?? '';
    
    // 处理 URL 占位符
    baseUrl = baseUrl.replaceAll('@keyword', '{keyword}');
    if (!baseUrl.contains('{keyword}')) {
      baseUrl = kRule['baseURL'] ?? kRule['baseUrl'] ?? baseUrl;
    }

    // 映射搜索字段
    final searchSelector = _xpathToCss(kRule['searchList'] ?? kRule['searchResult'] ?? '');
    final animeLinkSelector = _xpathToCss(kRule['searchName'] ?? kRule['searchResultItem'] ?? '');

    // 映射剧集字段
    String episodeList = '';
    String episodeLink = 'video, iframe, source'; // 兜底

    final chapter = kRule['chapter'];
    if (chapter != null && chapter is Map) {
      episodeList = _xpathToCss(chapter['list'] ?? kRule['chapterRoads'] ?? '');
      final customLink = _xpathToCss(chapter['link'] ?? kRule['chapterResult'] ?? '');
      if (customLink.isNotEmpty) episodeLink = customLink;
    } else {
      episodeList = _xpathToCss(kRule['chapterRoads'] ?? kRule['episodeList'] ?? '');
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
