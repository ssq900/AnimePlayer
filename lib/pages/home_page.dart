import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'player_page.dart';
import 'schedule_page.dart';
import 'stats_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _storage = StorageService();
  List<AnimeRule> _rules = [];
  List<HistoryItem> _history = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.loadRules();
    final history = await _storage.loadHistory();
    if (!mounted) return;
    
    setState(() {
      _rules = rules;
      _history = history;
    });
  }

  void _startGlobalSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入搜索关键词')));
      return;
    }
    if (_rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中导入规则')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(rules: _rules),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime Aggregator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '观看统计',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsPage()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: '追番日历',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SchedulePage(rules: _rules)));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _startGlobalSearch(),
            decoration: InputDecoration(
              hintText: '想看点什么？(全网多源聚合)',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _startGlobalSearch,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.travel_explore),
            label: Text('使用 ${_rules.length} 个源进行聚合搜索'),
            onPressed: _startGlobalSearch,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          ),
          
          const SizedBox(height: 32),
          
          if (_history.isNotEmpty) ...[
            const Text('最近观看 (长按加入日历)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._history.take(10).map((h) {
              final targetRule = _rules.firstWhere(
                (r) => r.id == h.ruleId || r.name == h.ruleName,
                orElse: () => _rules.isNotEmpty ? _rules.first : AnimeRule.empty(),
              );
              
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(h.animeTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${h.episodeTitle} · ${h.ruleName}', maxLines: 1),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () {
                    if (targetRule.name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('该规则已被删除，无法继续播放')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerPage(
                          rule: targetRule,
                          episodeUrl: h.episodeUrl,
                          title: h.episodeTitle,
                          animeTitle: h.animeTitle,
                        ),
                      ),
                    ).then((_) => _load());
                  },
                  onLongPress: () async {
                    final week = await showDialog<int>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('加入追番日历'),
                        content: const Text('选择每周更新的日子：'),
                        actions: [
                          for (int i = 1; i <= 7; i++)
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, i),
                              child: Text('周${['一','二','三','四','五','六','日'][i-1]}'),
                            )
                        ],
                      ),
                    );
                    if (week != null) {
                      final schedules = await _storage.loadSchedules();
                      schedules.removeWhere((e) => e.detailUrl == h.episodeUrl && e.ruleId == h.ruleId);
                      schedules.add(ScheduleItem(
                        animeTitle: h.animeTitle,
                        detailUrl: h.episodeUrl,
                        ruleId: h.ruleId,
                        weekday: week,
                        lastEpisodeTitle: h.episodeTitle,
                      ));
                      final success = await _storage.saveSchedules(schedules);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? '已加入追番日历' : '保存失败，请检查存储')),
                        );
                      }
                    }
                  },
                ),
              );
            }),
          ]
        ],
      ),
    );
  }
}
