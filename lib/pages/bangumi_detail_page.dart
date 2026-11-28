import 'package:flutter/material.dart';
import '../services/bangumi_service.dart';
import '../services/storage_service.dart';
import '../services/selector_engine.dart';
import '../models/rule.dart';
import 'player_page.dart';

class BangumiDetailPage extends StatefulWidget {
  final int subjectId;
  const BangumiDetailPage({super.key, required this.subjectId});

  @override
  State<BangumiDetailPage> createState() => _BangumiDetailPageState();
}

class _BangumiDetailPageState extends State<BangumiDetailPage> {
  final _bgmService = BangumiService();
  final _storage = StorageService();
  final _engine = SelectorEngine();

  BangumiSubject? _subject;
  bool _isLoading = true;

  // 搜索源相关状态
  List<AnimeRule> _rules = [];
  bool _isSearching = false;
  List<SearchResult> _sourceResults = [];

  // 剧集列表状态（缓存已拉取的剧集）
  final Map<String, List<EpisodeItem>> _episodesCache = {};
  String? _activeSourceUrl;
  bool _isLoadingEpisodes = false;

  // 正在解析视频流的标识
  String? _resolvingEpisodeUrl;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await _bgmService.fetchSubjectDetail(widget.subjectId);
      final rules = await _storage.loadRules();
      if (mounted) {
        setState(() {
          _subject = data;
          _rules = rules;
          _isLoading = false;
        });
        if (rules.isNotEmpty) {
          _searchSources();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载详情失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 用番剧名字去各个源搜索
  Future<void> _searchSources() async {
    if (_subject == null || _rules.isEmpty) return;
    setState(() => _isSearching = true);

    final keyword = _subject!.nameCn.isNotEmpty ? _subject!.nameCn : _subject!.name;
    
    // 简单并发搜索（这里为了不破坏现有 Repository 逻辑，直接在页面里并发）
    final futures = _rules.map((rule) async {
      try {
        final res = await _engine.search(rule, keyword);
        return res;
      } catch (_) {
        return <SearchResult>[];
      }
    }).toList();

    final results = await Future.wait(futures);
    final flatResults = results.expand((e) => e).toList();

    if (mounted) {
      setState(() {
        _sourceResults = flatResults;
        _isSearching = false;
      });
    }
  }

  // 点击某个源，拉取剧集列表
  Future<void> _toggleSource(SearchResult result) async {
    if (_activeSourceUrl == result.link) {
      setState(() => _activeSourceUrl = null); // 收起
      return;
    }

    setState(() {
      _activeSourceUrl = result.link;
      _isLoadingEpisodes = true;
    });

    if (_episodesCache.containsKey(result.link)) {
      setState(() => _isLoadingEpisodes = false);
      return;
    }

    try {
      final episodes = await _engine.fetchEpisodes(result.rule, result.link);
      if (mounted) {
        setState(() {
          _episodesCache[result.link] = episodes;
          _isLoadingEpisodes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEpisodes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取剧集失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 点击剧集，解析真实流地址并跳转播放
  Future<void> _playEpisode(AnimeRule rule, EpisodeItem ep) async {
    setState(() => _resolvingEpisodeUrl = ep.link);
    try {
      final finalUrl = await _engine.resolveEpisodeLink(rule, ep.link);
      if (mounted) {
        setState(() => _resolvingEpisodeUrl = null);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerPage(
              videoUrl: finalUrl,
              animeTitle: _subject?.nameCn ?? _subject?.name ?? '',
              episodeTitle: ep.title,
              rule: rule,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resolvingEpisodeUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析播放地址失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_subject == null) return const Scaffold(body: Center(child: Text('加载失败')));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部背景图 + 信息
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(_subject!.imageUrl, fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16, left: 16, right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _subject!.nameCn.isNotEmpty ? _subject!.nameCn : _subject!.name,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 20),
                            const SizedBox(width: 4),
                            Text(_subject!.score.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 18)),
                            if (_subject!.rank > 0) ...[
                              const SizedBox(width: 16),
                              Text('Rank #${_subject!.rank}', style: const TextStyle(color: Colors.white70)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 简介
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('简介', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _subject!.summary.isEmpty ? '暂无简介' : _subject!.summary,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // 🔥 源站搜索区域
                  Row(
                    children: [
                      const Text('播放源 (选集)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      if (_isSearching) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_rules.isEmpty)
                    const Text('请先在设置中导入规则源', style: TextStyle(color: Colors.grey)),

                  if (_rules.isNotEmpty && _sourceResults.isEmpty && !_isSearching)
                    const Text('未找到该番剧的可用播放源', style: TextStyle(color: Colors.grey)),

                  // 搜索结果列表
                  ..._sourceResults.map((result) {
                    final isExpanded = _activeSourceUrl == result.link;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(result.rule.name.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white)),
                            ),
                            title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('来源: ${result.rule.name}'),
                            trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                            onTap: () => _toggleSource(result),
                          ),
                          if (isExpanded)
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _isLoadingEpisodes && !_episodesCache.containsKey(result.link)
                                  ? const Center(child: CircularProgressIndicator())
                                  : _buildEpisodeGrid(result.rule, _episodesCache[result.link] ?? []),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 剧集网格
  Widget _buildEpisodeGrid(AnimeRule rule, List<EpisodeItem> episodes) {
    if (episodes.isEmpty) return const Text('该源暂无剧集', style: TextStyle(color: Colors.grey));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: episodes.map((ep) {
        final isResolving = _resolvingEpisodeUrl == ep.link;
        return ActionChip(
          label: isResolving 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onPressed: isResolving ? null : () => _playEpisode(rule, ep),
        );
      }).toList(),
    );
  }
}
