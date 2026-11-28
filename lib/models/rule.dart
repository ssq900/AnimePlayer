import '../services/exceptions.dart';

class AnimeRule {
  final String id;
  final String name;
  final String baseUrl;
  
  final String searchSelector;
  final String animeLinkSelector;
  final String episodeListSelector;
  final String episodeLinkSelector;

  final String searchSelectorCss;
  final String animeLinkSelectorCss;
  final String episodeListSelectorCss;
  final String episodeLinkSelectorCss;
  
  final bool isCssBased;
  final String fetchStrategy;

  // 🔥 新增：规则健康度字段
  final int successCount;
  final int failCount;
  final int lastSuccessTime;       // 最后一次成功的时间戳
  final String lastFailureReason;  // 最后一次失败原因
  final String lastFailureStage;   // 最后一次失败环节（如 search, episodes, media）

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
    this.fetchStrategy = 'direct',
    this.successCount = 0,
    this.failCount = 0,
    this.lastSuccessTime = 0,
    this.lastFailureReason = '',
    this.lastFailureStage = '',
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
        'fetchStrategy': fetchStrategy,
        'successCount': successCount,
        'failCount': failCount,
        'lastSuccessTime': lastSuccessTime,
        'lastFailureReason': lastFailureReason,
        'lastFailureStage': lastFailureStage,
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
      fetchStrategy: j['fetchStrategy'] ?? 'direct',
      successCount: j['successCount'] ?? 0,
      failCount: j['failCount'] ?? 0,
      lastSuccessTime: j['lastSuccessTime'] ?? 0,
      lastFailureReason: j['lastFailureReason'] ?? '',
      lastFailureStage: j['lastFailureStage'] ?? '',
    );
  }

  AnimeRule copyWith({
    String? searchSelectorCss,
    String? animeLinkSelectorCss,
    String? episodeListSelectorCss,
    String? episodeLinkSelectorCss,
    bool? isCssBased,
    String? fetchStrategy,
    int? successCount,
    int? failCount,
    int? lastSuccessTime,
    String? lastFailureReason,
    String? lastFailureStage,
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
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
      lastSuccessTime: lastSuccessTime ?? this.lastSuccessTime,
      lastFailureReason: lastFailureReason ?? this.lastFailureReason,
      lastFailureStage: lastFailureStage ?? this.lastFailureStage,
    );
  }

  static AnimeRule empty() => AnimeRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '', baseUrl: '', searchSelector: '',
        animeLinkSelector: '', episodeListSelector: '', episodeLinkSelector: '',
      );
}

// ================= 保留其他模型 (SearchResult, EpisodeItem, HistoryItem, ScheduleItem) =================
class SearchResult {
  final String title;
  final String link;
  final AnimeRule rule;
  const SearchResult({required this.title, required this.link, required this.rule});
}

class EpisodeItem {
  final String title;
  final String link;
  const EpisodeItem({required this.title, required this.link});
}

class HistoryItem {
  final String animeTitle;
  final String episodeTitle;
  final String episodeUrl;
  final String ruleId;
  final String ruleName;
  final String detailUrl;
  final int timestamp;

  const HistoryItem({
    required this.animeTitle, required this.episodeTitle, required this.episodeUrl, 
    required this.ruleId, required this.ruleName, required this.detailUrl, required this.timestamp
  });

  Map<String, dynamic> toJson() => {'animeTitle': animeTitle, 'episodeTitle': episodeTitle, 'episodeUrl': episodeUrl, 'ruleId': ruleId, 'ruleName': ruleName, 'detailUrl': detailUrl, 'timestamp': timestamp};
  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    animeTitle: j['animeTitle'] ?? '', episodeTitle: j['episodeTitle'] ?? '', episodeUrl: j['episodeUrl'] ?? '', 
    ruleId: j['ruleId'] ?? '', ruleName: j['ruleName'] ?? '', detailUrl: j['detailUrl'] ?? '', timestamp: j['timestamp'] ?? 0
  );
}

class ScheduleItem {
  final String animeTitle;
  final String detailUrl;
  final int weekday;
  final String lastEpisodeTitle;
  final String episodeUrl;
  final String ruleId;

  const ScheduleItem({
    required this.animeTitle, required this.detailUrl, required this.weekday, 
    this.lastEpisodeTitle = '', this.episodeUrl = '', this.ruleId = ''
  });

  Map<String, dynamic> toJson() => {'animeTitle': animeTitle, 'detailUrl': detailUrl, 'weekday': weekday, 'lastEpisodeTitle': lastEpisodeTitle, 'episodeUrl': episodeUrl, 'ruleId': ruleId};
  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
    animeTitle: j['animeTitle'] ?? '', detailUrl: j['detailUrl'] ?? '', weekday: j['weekday'] ?? 1, 
    lastEpisodeTitle: j['lastEpisodeTitle'] ?? '', episodeUrl: j['episodeUrl'] ?? '', ruleId: j['ruleId'] ?? ''
  );
}
