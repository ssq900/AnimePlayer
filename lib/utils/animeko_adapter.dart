import 'package:flutter/foundation.dart';
import '../models/rule.dart';

class AnimekoAdapter {
  /// 尝试将 Animeko 的 JSON 转换为 AnimePlayer 的 AnimeRule
  static AnimeRule? convert(Map<String, dynamic> json) {
    try {
      // 兼容不同版本的 Animeko 导出格式
      final Map<String, dynamic> args = json['arguments'] != null
          ? json['arguments'] as Map<String, dynamic>
          : json;

      // 提取基础信息
      final name = json['factoryId'] ?? args['name'] ?? '导入的 Animeko 源';
      final searchConfig = args['searchConfig'] as Map<String, dynamic>? ?? {};
      final searchUrl = searchConfig['searchUrl'] as String? ?? '';

      // 提取搜索容器与条目选择器
      final subjectFormat = searchConfig['selectorSubjectFormatIndexed'] as Map<String, dynamic>? ?? searchConfig;
      
      String containerCss = subjectFormat['selectSubjectFormat'] as String? ?? '';
      final titleCss = subjectFormat['selectNames'] as String? ?? '';
      final linkCss = subjectFormat['selectLinks'] as String? ?? '';

      // 如果找不到容器，做个简单降级推断
      if (containerCss.isEmpty && titleCss.isNotEmpty) {
        containerCss = titleCss.split(' ').first;
      }

      // 提取剧集列表选择器
      final channelFormat = searchConfig['selectorChannelFormatFlattened'] as Map<String, dynamic>? ?? {};
      final episodeCss = channelFormat['selectEpisodesFromList'] as String? ?? '';

      if (searchUrl.isEmpty) return null;

      return AnimeRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        baseUrl: searchUrl.replaceAll('{keyword}', ''),
        // XPath 字段留空
        searchSelector: '',
        animeLinkSelector: '',
        episodeListSelector: '',
        episodeLinkSelector: '',
        // 🔥 关键：填入提取出的 CSS 选择器
        searchSelectorCss: containerCss.isNotEmpty ? containerCss : 'body',
        animeLinkSelectorCss: linkCss.isNotEmpty ? linkCss : titleCss,
        episodeListSelectorCss: episodeCss,
        episodeLinkSelectorCss: '', 
        isCssBased: true, // 强制启用 CSS 引擎
        fetchStrategy: 'direct',
      );
    } catch (e) {
      debugPrint('[AnimekoAdapter] 规则转换失败: $e');
      return null;
    }
  }
}
