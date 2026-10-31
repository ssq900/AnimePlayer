import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import '../services/xpath_service.dart';
import '../services/notification_service.dart';

class SchedulePage extends StatefulWidget {
  final List<AnimeRule> rules;
  const SchedulePage({super.key, required this.rules});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _storage = StorageService();
  List<ScheduleItem> _schedules = [];
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _storage.loadSchedules();
    setState(() => _schedules = items);
  }

  Future<void> _checkUpdates() async {
    setState(() => _checking = true);
    final xpath = XPathService();
    int updatedCount = 0;

    for (int i = 0; i < _schedules.length; i++) {
      final item = _schedules[i];
      final rule = widget.rules.firstWhere((r) => r.id == item.ruleId, orElse: () => AnimeRule.empty());
      if (rule.name.isEmpty) continue;

      try {
        final episodes = await xpath.fetchEpisodes(rule, item.detailUrl);
        if (episodes.isNotEmpty) {
          final latest = episodes.last.title;
          if (latest != item.lastEpisodeTitle && item.lastEpisodeTitle.isNotEmpty) {
             updatedCount++;
             await NotificationService.showUpdateNotification(item.animeTitle, latest);
          }
          _schedules[i] = ScheduleItem(
            animeTitle: item.animeTitle,
            detailUrl: item.detailUrl,
            ruleId: item.ruleId,
            weekday: item.weekday,
            lastEpisodeTitle: latest,
          );
        }
      } catch (_) {}
    }
    await _storage.saveSchedules(_schedules);
    setState(() => _checking = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('检测完成，发现 $updatedCount 部番剧有更新')));
    }
  }

  Future<void> _exportIcs() async {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//AnimeAggregator//CN');
    
    for (var item in _schedules) {
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('SUMMARY:${item.animeTitle}');
      buffer.writeln('RRULE:FREQ=WEEKLY;BYDAY=${['MO','TU','WE','TH','FR','SA','SU'][item.weekday - 1]}');
      buffer.writeln('DESCRIPTION:通过 Anime Aggregator 导出');
      buffer.writeln('END:VEVENT');
    }
    buffer.writeln('END:VCALENDAR');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/anime_schedule.ics');
      await file.writeAsString(buffer.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('追番日历'),
        actions: [
          IconButton(
            icon: _checking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            onPressed: _checking ? null : _checkUpdates,
            tooltip: '检测更新',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportIcs,
            tooltip: '导出 ICS',
          )
        ],
      ),
      body: _schedules.isEmpty 
          ? const Center(child: Text('还没有加入日历的番剧。\n你可以去历史记录中长按添加。'))
          : ListView.builder(
              itemCount: 7,
              itemBuilder: (context, index) {
                final weekday = index + 1;
                final list = _schedules.where((e) => e.weekday == weekday).toList();
                if (list.isEmpty) return const SizedBox.shrink();
                final weekNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(weekNames[index], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    ...list.map((item) => ListTile(
                      title: Text(item.animeTitle),
                      subtitle: Text('最新已知: ${item.lastEpisodeTitle}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          setState(() => _schedules.remove(item));
                          await _storage.saveSchedules(_schedules);
                        },
                      ),
                    ))
                  ],
                );
              },
            ),
    );
  }
}
