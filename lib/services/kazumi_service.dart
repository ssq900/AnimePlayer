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
          final data = jsonDecode(resp.body);
          if (data is List) {
            return data.cast<Map<String, dynamic>>();
          }
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
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map<String, dynamic>) {
            return data;
          }
        }
        errors.add('${Uri.parse(url).host} 状态码: ${resp.statusCode}');
      } catch (e) {
        errors.add('${Uri.parse(url).host} 异常: $e');
      }
    }
    throw Exception('规则详情拉取失败:\n${errors.join('\n')}');
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

    // 4. 数字索引降级 -> 直接抛弃
    css = css.replaceAll(RegExp(r'\[\d+\]'), '');
    css = css.replaceAll(RegExp(r':nth-of-type\(\d+\)'), '');

    // 5. 基础路径清理
    css = css.replaceAll('//', ' ');
    css = css.replaceAll('/', ' > ');
    css = css.replaceAll(RegExp(r'\[@.*?\]'), '');
    css = css.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    if (css.startsWith('>')) css = css.substring(1).trim();
    
    // 6. 兜底判断：如果清理后只剩下一堆 div 标签（没有任何类名和 ID），说明规则无法使用
    if (css.isEmpty || (!css.contains('.') && !css.contains('#'))) {
      return 'UNSUPPORTED_RULE'; 
    }
    
    return css;
  }

  Map<String, String> convertKazumiRule(Map<String, dynamic> kRule) {
    String baseUrl = kRule['searchURL'] ?? kRule['baseUrl'] ?? kRule['baseURL'] ?? '';
    
    // 处理 URL 占位符
    baseUrl = baseUrl.replaceAll('@keyword', '{keyword}');
    if (!baseUrl.contains('{keyword}')) {
      baseUrl = kRule['baseURL'] ?? kRule['baseUrl'] ?? baseUrl;
    }

    final searchSelector = _xpathToCss(kRule['searchList'] ?? kRule['searchResult'] ?? '');
    final animeLinkSelector = _xpathToCss(kRule['searchName'] ?? kRule['searchResultItem'] ?? '');

    String episodeList = _xpathToCss(kRule['chapterRoads'] ?? kRule['episodeList'] ?? '');
    String episodeLink = 'video, iframe, source';

    final chapter = kRule['chapter'];
    if (chapter != null) {
      // 核心修复：拦截脏数据，如果 chapter 存在但结构不对，直接抛出明显错误
      if (chapter is! Map) {
        throw FormatException('规则格式损坏："chapter" 字段应为对象，实际为 ${chapter.runtimeType}');
      }
      episodeList = _xpathToCss(chapter['list'] ?? kRule['chapterRoads'] ?? '');
      final customLink = _xpathToCss(chapter['link'] ?? kRule['chapterResult'] ?? '');
      if (customLink.isNotEmpty && customLink != 'UNSUPPORTED_RULE') episodeLink = customLink;
    } else {
      final customLink = _xpathToCss(kRule['chapterResult'] ?? kRule['episodeLink'] ?? '');
      if (customLink.isNotEmpty && customLink != 'UNSUPPORTED_RULE') episodeLink = customLink;
    }

    // 如果搜索容器和番剧条目全部是垃圾规则，则拦截导入
    if (searchSelector == 'UNSUPPORTED_RULE' || searchSelector.isEmpty) {
       throw FormatException('该规则基于纯标签层级，无法转换为稳健的解析器语法，已跳过。');
    }

    return {
      'name': kRule['name'] ?? '未命名规则',
      'baseUrl': baseUrl,
      'searchSelector': searchSelector,
      // 如果条目选择器是垃圾规则，给一个兜底值，后面会在 search 里直接用容器
      'animeLinkSelector': (animeLinkSelector == 'UNSUPPORTED_RULE' || animeLinkSelector.isEmpty) ? '*' : animeLinkSelector,
      'episodeListSelector': (episodeList == 'UNSUPPORTED_RULE' || episodeList.isEmpty) ? 'a' : episodeList,
      'episodeLinkSelector': episodeLink,
    };
  }
}
