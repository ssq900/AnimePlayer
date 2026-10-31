class AnimeRule {
  final String id;
  final String name;
  final String baseUrl;
  final String searchSelector;
  final String animeLinkSelector;
  final String episodeListSelector;
  final String episodeLinkSelector;

  const AnimeRule({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.searchSelector,
    required this.animeLinkSelector,
    required this.episodeListSelector,
    required this.episodeLinkSelector,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'searchSelector': searchSelector,
        'animeLinkSelector': animeLinkSelector,
        'episodeListSelector': episodeListSelector,
        'episodeLinkSelector': episodeLinkSelector,
      };

  factory AnimeRule.fromJson(Map<String, dynamic> j) {
    return AnimeRule(
      id: (j['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: (j['name'] as String?) ?? '',
      baseUrl: (j['baseUrl'] as String?) ?? '',
      searchSelector: (j['searchSelector'] as String?) ?? '',
      animeLinkSelector: (j['animeLinkSelector'] as String?) ?? '',
      episodeListSelector: (j['episodeListSelector'] as String?) ?? '',
      episodeLinkSelector: (j['episodeLinkSelector'] as String?) ?? '',
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
