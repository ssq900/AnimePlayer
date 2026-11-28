import '../services/exceptions.dart';

class AnimeRule {
  final String id;
  final String name;
  final String baseUrl;
  
  // 旧版 XPath 字段（保留兼容）
  final String searchSelector;
  final String animeLinkSelector;
  final String episodeListSelector;
  final String episodeLinkSelector;

  // 新版 CSS 字段
  final String searchSelectorCss;
  final String animeLinkSelectorCss;
  final String episodeListSelectorCss;
  final String episodeLinkSelectorCss;
  
  // 标记：是否已经成功迁移到 CSS 模式
  final bool isCssBased;

  // 🔥 新增：抓取策略。'direct'(默认直连), 'webview'(无头浏览器), 'iframe'(特殊嵌套处理)
  final String fetchStrategy;

  final int successCount;
  final int failCount;

  const AnimeRule({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.searchSelector,
    required this.animeLinkSelector,
    required this.episodeListSelector,
    required this.episodeLinkSelector,
    this.searchSelectorCss = '',
    this.animeLinkSelectorCss = '',
    this.episodeListSelectorCss = '',
    this.episodeLinkSelectorCss = '',
    this.isCssBased = false,
    this.fetchStrategy = 'direct', // 默认策略
    this.successCount = 0,
    this.failCount = 0,
  });

  double get trustScore => (successCount + 1) / (successCount + failCount + 2);

  void validate() {
    if (baseUrl.trim().isEmpty) throw RuleFormatException('Base URL 不能为空');
    if (searchSelector.trim().isEmpty && searchSelectorCss.trim().isEmpty) {
      throw RuleFormatException('搜索结果容器选择器不能为空');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'searchSelector': searchSelector,
        'animeLinkSelector': animeLinkSelector,
        'episodeListSelector': episodeListSelector,
        'episodeLinkSelector': episodeLinkSelector,
        'searchSelectorCss': searchSelectorCss,
        'animeLinkSelectorCss': animeLinkSelectorCss,
        'episodeListSelectorCss': episodeListSelectorCss,
        'episodeLinkSelectorCss': episodeLinkSelectorCss,
        'isCssBased': isCssBased,
        'fetchStrategy': fetchStrategy, // 序列化
        'successCount': successCount,
        'failCount': failCount,
      };

  factory AnimeRule.fromJson(Map<String, dynamic> j) {
    return AnimeRule(
      id: j['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: j['name'] ?? '未命名规则',
      baseUrl: j['baseUrl'] ?? '',
      searchSelector: j['searchSelector'] ?? '',
      animeLinkSelector: j['animeLinkSelector'] ?? '',
      episodeListSelector: j['episodeListSelector'] ?? '',
      episodeLinkSelector: j['episodeLinkSelector'] ?? '',
      searchSelectorCss: j['searchSelectorCss'] ?? '',
      animeLinkSelectorCss: j['animeLinkSelectorCss'] ?? '',
      episodeListSelectorCss: j['episodeListSelectorCss'] ?? '',
      episodeLinkSelectorCss: j['episodeLinkSelectorCss'] ?? '',
      isCssBased: j['isCssBased'] ?? false,
      fetchStrategy: j['fetchStrategy'] ?? 'direct', // 默认兼容
      successCount: j['successCount'] ?? 0,
      failCount: j['failCount'] ?? 0,
    );
  }

  AnimeRule copyWith({
    String? searchSelectorCss,
    String? animeLinkSelectorCss,
    String? episodeListSelectorCss,
    String? episodeLinkSelectorCss,
    bool? isCssBased,
    String? fetchStrategy,
  }) {
    return AnimeRule(
      id: this.id,
      name: this.name,
      baseUrl: this.baseUrl,
      searchSelector: this.searchSelector,
      animeLinkSelector: this.animeLinkSelector,
      episodeListSelector: this.episodeListSelector,
      episodeLinkSelector: this.episodeLinkSelector,
      searchSelectorCss: searchSelectorCss ?? this.searchSelectorCss,
      animeLinkSelectorCss: animeLinkSelectorCss ?? this.animeLinkSelectorCss,
      episodeListSelectorCss: episodeListSelectorCss ?? this.episodeListSelectorCss,
      episodeLinkSelectorCss: episodeLinkSelectorCss ?? this.episodeLinkSelectorCss,
      isCssBased: isCssBased ?? this.isCssBased,
      fetchStrategy: fetchStrategy ?? this.fetchStrategy,
      successCount: this.successCount,
      failCount: this.failCount,
    );
  }

  static AnimeRule empty() => AnimeRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '', baseUrl: '', searchSelector: '',
        animeLinkSelector: '', episodeListSelector: '', episodeLinkSelector: '',
      );
}
