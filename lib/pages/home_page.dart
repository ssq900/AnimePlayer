import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'rule_edit_page.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _storage = StorageService();
  List<AnimeRule> _rules = [];
  List<HistoryItem> _history = [];
  String? _selectedId;

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
      if (rules.isNotEmpty) {
        final exists = rules.any((r) => r.id == _selectedId);
        if (!exists) {
          _selectedId = rules.first.id;
        }
      } else {
        _selectedId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime Aggregator'),
        actions: [
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
          // ====== 搜索控制区 ======
          if (_rules.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('还没有规则，请先去设置添加'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
                        _load();
                      },
                      child: const Text('去添加'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedId,
              decoration: const InputDecoration(
                labelText: '当前规则',
                border: OutlineInputBorder(),
              ),
              items: _rules
                  .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name.isEmpty ? r.baseUrl : r.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedId = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('开始搜索'),
              onPressed: _selectedId == null
                  ? null
                  : () async {
                      final currentRule = _rules.firstWhere((r) => r.id == _selectedId);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SearchPage(rule: currentRule),
                        ),
                      );
                      _load(); // 从搜索页回来时刷新历史
                    },
            ),
          ],
          
          const SizedBox(height: 32),
          
          // ====== 最近观看历史区 ======
          if (_history.isNotEmpty) ...[
            const Text('最近观看', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._history.take(10).map((h) {
              // 查找这条记录对应的规则是否还存在
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
                    );
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
