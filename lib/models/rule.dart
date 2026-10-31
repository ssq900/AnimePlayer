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

  factory AnimeRule.fromJson(Map<String, dynamic> j) => AnimeRule(
        id: j['id'] as String,
        name: j['name'] as String,
        baseUrl: j['baseUrl'] as String,
        searchSelector: j['searchSelector'] as String,
        animeLinkSelector: j['animeLinkSelector'] as String,
        episodeListSelector: j['episodeListSelector'] as String,
        episodeLinkSelector: j['episodeLinkSelector'] as String,
      );

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
  const SearchResult({required this.title, required this.link});
}

class EpisodeItem {
  final String title;
  final String link;
  const EpisodeItem({required this.title, required this.link});
}
