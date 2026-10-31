import 'dart:convert';
import 'package:http/http.dart' as http;

class KazumiService {
  // 使用 GitCode 镜像，国内拉取更稳定
  static const String _mirrorUrl =
      'https://raw.githack.com/Predidit/KazumiRules/main/rules.json';
      
  // 备用官方源
  static const String _rawUrl =
      'https://raw.githubusercontent.com/Predidit/KazumiRules/main/rules.json';

  Future<List<Map<String, dynamic>>> fetchRules() async {
    try {
      final resp = await http.get(Uri.parse(_mirrorUrl));
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception('HTTP ${resp.statusCode}');
    } catch (e) {
      // 失败则降级到原生 GitHub 源
      final resp = await http.get(Uri.parse(_rawUrl));
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception('无法拉取规则仓库: $e');
    }
  }

  // 粗糙但有效的 XPath 转 CSS Selector 工具
  String _xpathToCss(String xpath) {
    if (xpath.isEmpty) return '';
    String css = xpath.trim();
    
    // 如果已经是以 . 或 # 开头，直接返回
    if (css.startsWith('.') || css.startsWith('#')) return css;

    // 处理 //div[@class="list"] -> .list
    final regClass = RegExp(r'//\w+\[@class=["'']([^"'']+)["'']\]');
    if (regClass.hasMatch(css)) {
      final match = regClass.firstMatch(css);
      return '.${match!.group(1)!.replaceAll(' ', '.')}';
    }

    // 处理 //div[@id="main"] -> #main
    final regId = RegExp(r'//\w+\[@id=["'']([^"'']+)["'']\]');
    if (regId.hasMatch(css)) {
      final match = regId.firstMatch(css);
      return '#${match!.group(1)}';
    }

    // 简单的标签替换 //div -> div，/div/a -> div a
    css = css.replaceAll('//', ' ');
    css = css.replaceAll('/', ' ');
    css = css.replaceAll(RegExp(r'\[\d+\]'), ''); // 移除 [1] 这种索引
    css = css.replaceAll(RegExp(r'\[@.*?\]'), ''); // 移除无法转换的属性过滤
    return css.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  // 将 Kazumi 规则转换为我们的 AnimeRule 模型格式
  Map<String, String> convertKazumiRule(Map<String, dynamic> kRule) {
    final baseUrl = kRule['baseUrl'] ?? '';
    
    // 兼容 Kazumi 不同版本或不同作者的规则字段命名
    // searchList (搜索容器), searchName (番剧链接)
    final searchSelector = _xpathToCss(kRule['searchList'] ?? kRule['searchResult'] ?? '');
    final animeLinkSelector = _xpathToCss(kRule['searchName'] ?? kRule['searchResultItem'] ?? '');
    
    // Kazumi 的剧集列表往往嵌套了对象，这里做兼容处理
    String episodeList = '';
    String episodeLink = '';
    final chapter = kRule['chapter'];
    if (chapter != null && chapter is Map) {
      episodeList = _xpathToCss(chapter['list'] ?? '');
      episodeLink = _xpathToCss(chapter['link'] ?? '');
    } else {
      episodeList = _xpathToCss(kRule['episodeList'] ?? '');
      episodeLink = _xpathToCss(kRule['episodeLink'] ?? '');
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
