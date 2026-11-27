import '../services/exceptions.dart';

class AnimeRule {
  final String id;
  final String name;
  final String baseUrl;
  final String searchSelector;
  final String animeLinkSelector;
  final String episodeListSelector;
  final String episodeLinkSelector;
  
  // 核心新增：记录源的信任数据
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
    this.successCount = 0,
    this.failCount = 0,
  });

  // 信任分算法（拉普拉斯平滑）：初始值为 0.5，成功越多越接近 1.0
  double get trustScore {
    return (successCount + 1) / (successCount + failCount + 2);
  }

  // 领域校验逻辑
  void validate() {
    if (baseUrl.trim().isEmpty) {
      throw RuleFormatException('规则 [$name] 校验失败：Base URL 不能为空');
    }
    if (!baseUrl.contains('{keyword}') && !baseUrl.contains('?')) {
      throw RuleFormatException('规则 [$name] 校验失败：Base URL 必须包含 {keyword} 占位符或查询参数');
    }
    if (searchSelector.trim().isEmpty) {
      throw RuleFormatException('规则 [$name] 校验失败：搜索结果容器选择器不能为空');
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
        'successCount': successCount,
        'failCount': failCount,
      };

  factory AnimeRule.fromJson(Map<String, dynamic> j) {
    final ruleId = (j['id'] as String?)?.trim();
    if (ruleId == null || ruleId.isEmpty) {
      throw RuleFormatException('数据损坏：规则缺少唯一 ID');
    }
    return AnimeRule(
      id: ruleId,
      name: (j['name'] as String?) ?? '未命名规则',
      baseUrl: (j['baseUrl'] as String?) ?? '',
      searchSelector: (j['searchSelector'] as String?) ?? '',
      animeLinkSelector: (j['animeLinkSelector'] as String?) ?? '',
      episodeListSelector: (j['episodeListSelector'] as String?) ?? '',
      episodeLinkSelector: (j['episodeLinkSelector'] as String?) ?? '',
      successCount: (j['successCount'] as int?) ?? 0,
      failCount: (j['failCount'] as int?) ?? 0,
    );
  }

  static AnimeRule empty() => AnimeRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '', 
        baseUrl: '', 
        searchSelector: '',
        animeLinkSelector: '', 
        episodeListSelector: '', 
        episodeLinkSelector: '',
      );
}

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
  final String ruleId; 
  final String ruleName;
  final String animeTitle; 
  final String episodeTitle;
  final String episodeUrl; 
  final int timestamp;

  HistoryItem({
    required this.ruleId, 
    required this.ruleName,
    required this.animeTitle, 
    required this.episodeTitle,
    required this.episodeUrl, 
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'ruleId': ruleId, 
    'ruleName': ruleName,
    'animeTitle': animeTitle, 
    'episodeTitle': episodeTitle,
    'episodeUrl': episodeUrl, 
    'timestamp': timestamp,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    ruleId: j['ruleId'] ?? '', 
    ruleName: j['ruleName'] ?? '',
    animeTitle: j['animeTitle'] ?? '', 
    episodeTitle: j['episodeTitle'] ?? '',
    episodeUrl: j['episodeUrl'] ?? '', 
    timestamp: j['timestamp'] ?? 0,
  );
}

class ScheduleItem {
  final String animeTitle; 
  final String detailUrl;
  final String ruleId; 
  final int weekday;
  final String lastEpisodeTitle;

  ScheduleItem({
    required this.animeTitle, 
    required this.detailUrl,
    required this.ruleId, 
    required this.weekday,
    required this.lastEpisodeTitle,
  });

  Map<String, dynamic> toJson() => {
    'animeTitle': animeTitle, 
    'detailUrl': detailUrl,
    'ruleId': ruleId, 
    'weekday': weekday,
    'lastEpisodeTitle': lastEpisodeTitle,
  };

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
    animeTitle: j['animeTitle'] ?? '', 
    detailUrl: j['detailUrl'] ?? '',
    ruleId: j['ruleId'] ?? '', 
    weekday: j['weekday'] ?? 1,
    lastEpisodeTitle: j['lastEpisodeTitle'] ?? '',
  );
}
