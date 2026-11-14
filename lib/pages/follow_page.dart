import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import 'schedule_page.dart';

class FollowPage extends StatefulWidget {
  const FollowPage({super.key});

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage> {
  final _storage = StorageService();
  List<AnimeRule> _rules = [];
  List<HistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.loadRules();
    final history = await _storage.loadHistory();
    if (mounted) setState(() { _rules = rules; _history = history; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('追番与历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: '追番日历',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SchedulePage(rules: _rules)));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('最近观看', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_history.isEmpty) const Text('暂无观看记录', style: TextStyle(color: Colors.grey)),
            ..._history.map((h) => Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(h.animeTitle, maxLines: 1),
                subtitle: Text('${h.episodeTitle} · ${h.ruleName}'),
                onLongPress: () async {
                  final week = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('加入追番日历'),
                      content: const Text('选择每周更新的日子：'),
                      actions: [
                        for (int i = 1; i <= 7; i++)
                          TextButton(onPressed: () => Navigator.pop(ctx, i), child: Text('周${['一','二','三','四','五','六','日'][i-1]}'))
                      ],
                    ),
                  );
                  if (week != null) {
                    final schedules = await _storage.loadSchedules();
                    schedules.removeWhere((e) => e.detailUrl == h.episodeUrl && e.ruleId == h.ruleId);
                    schedules.add(ScheduleItem(
                      animeTitle: h.animeTitle, detailUrl: h.episodeUrl, ruleId: h.ruleId,
                      weekday: week, lastEpisodeTitle: h.episodeTitle,
                    ));
                    await _storage.saveSchedules(schedules);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入日历')));
                  }
                },
              ),
            )),
          ],
        ),
      ),
    );
  }
}
