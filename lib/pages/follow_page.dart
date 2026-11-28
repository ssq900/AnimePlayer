import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';

class FollowPage extends StatefulWidget {
  const FollowPage({super.key});

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage> {
  final StorageService _storage = StorageService();
  List<AnimeRule> _rules = [];
  List<HistoryItem> _history = [];
  List<ScheduleItem> _schedules = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final rules = await _storage.loadRules();
    final history = await _storage.loadHistory();
    final schedules = await _storage.loadSchedules();

    if (mounted) {
      setState(() {
        _rules = rules;
        // 🔥 核心修复：使用 List<HistoryItem>.from() 进行强转，避免 dynamic 报错
        _history = List<HistoryItem>.from(history);
        _schedules = List<ScheduleItem>.from(schedules);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('追番与历史'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '观看历史'),
              Tab(text: '我的追番'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ================= 历史记录 Tab =================
            _history.isEmpty
                ? const Center(child: Text('暂无观看历史'))
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final h = _history[index];
                      return ListTile(
                        title: Text(
                          h.animeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // 🔥 修复：现在 HistoryItem 有 ruleName 字段了
                        subtitle: Text('${h.episodeTitle} · ${h.ruleName}'),
                        onTap: () {
                          // TODO: 点击历史记录跳转到播放页
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _history.removeAt(index);
                            });
                            // TODO: 这里需要调用 _storage.saveHistory(_history) 保存删除结果
                          },
                        ),
                      );
                    },
                  ),

            // ================= 追番列表 Tab =================
            _schedules.isEmpty
                ? const Center(child: Text('暂无追番'))
                : ListView.builder(
                    itemCount: _schedules.length,
                    itemBuilder: (context, index) {
                      final s = _schedules[index];
                      return ListTile(
                        title: Text(
                          s.animeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // 🔥 修复：现在 ScheduleItem 有 lastEpisodeTitle 字段了
                        subtitle: Text('周${s.weekday} · 最新: ${s.lastEpisodeTitle}'),
                        onTap: () {
                          // TODO: 点击追番跳转到详情页
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _schedules.removeAt(index);
                            });
                            // TODO: 这里需要调用 _storage.saveSchedules(_schedules) 保存删除结果
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
