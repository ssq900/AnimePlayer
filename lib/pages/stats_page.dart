import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final _storage = StorageService();
  bool _loading = true;

  // 统计数据
  int _totalEpisodes = 0;
  double _totalHours = 0.0;
  String _favoriteAnime = '暂无';
  String _favoriteRule = '暂无';
  Map<int, int> _dailyCounts = {}; // 1=周一 ... 7=周日

  @override
  void initState() {
    super.initState();
    _calculateStats();
  }

  Future<void> _calculateStats() async {
    final history = await _storage.loadHistory();
    
    // 获取最近 7 天的时间戳
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    
    final recentHistory = history.where((h) => h.timestamp >= sevenDaysAgo).toList();

    if (!mounted) return;

    if (recentHistory.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final Map<String, int> animeCount = {};
    final Map<String, int> ruleCount = {};
    final Map<int, int> dailyCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};

    for (var item in recentHistory) {
      // 计数
      animeCount[item.animeTitle] = (animeCount[item.animeTitle] ?? 0) + 1;
      ruleCount[item.ruleName] = (ruleCount[item.ruleName] ?? 0) + 1;
      
      // 计算星期几 (DateTime.weekday 1-7)
      final dt = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
      dailyCounts[dt.weekday] = (dailyCounts[dt.weekday] ?? 0) + 1;
    }

    // 找最大值
    String favAnime = '';
    int maxAnime = 0;
    animeCount.forEach((k, v) {
      if (v > maxAnime) {
        maxAnime = v;
        favAnime = k;
      }
    });

    String favRule = '';
    int maxRule = 0;
    ruleCount.forEach((k, v) {
      if (v > maxRule) {
        maxRule = v;
        favRule = k;
      }
    });

    setState(() {
      _totalEpisodes = recentHistory.length;
      _totalHours = (_totalEpisodes * 24) / 60; // 估算：每集24分钟
      _favoriteAnime = favAnime;
      _favoriteRule = favRule;
      _dailyCounts = dailyCounts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本周电子榨菜报告')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _totalEpisodes == 0
              ? const Center(child: Text('本周还没有看番哦，快去补番吧！'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 总览卡片
                    Card(
                      color: Colors.deepPurple.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text('🥬 你的电子榨菜', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStatItem('$_totalEpisodes', '看完集数'),
                                _buildStatItem(_totalHours.toStringAsFixed(1), '总计小时'),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 最爱偏好卡片
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.favorite, color: Colors.pink),
                            title: const Text('本周最爱番剧'),
                            subtitle: Text(_favoriteAnime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.dns, color: Colors.blue),
                            title: const Text('最常使用的源站'),
                            subtitle: Text(_favoriteRule, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 每日柱状图
                    const Text('每日追番活跃度', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [1, 2, 3, 4, 5, 6, 7].map((day) {
                        final count = _dailyCounts[day] ?? 0;
                        // 计算柱子高度，最高 120
                        final maxCount = _dailyCounts.values.reduce((a, b) => a > b ? a : b);
                        final height = maxCount == 0 ? 0.0 : (count / maxCount) * 120.0;
                        final labels = ['一', '二', '三', '四', '五', '六', '日'];
                        
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('$count', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Container(
                              width: 24,
                              height: height == 0 ? 4 : height,
                              decoration: BoxDecoration(
                                color: count > 0 ? Colors.deepPurple : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('周${labels[day - 1]}', style: const TextStyle(fontSize: 12)),
                          ],
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 48),
                    const Center(
                      child: Text('统计基于本地历史记录，完全隐私安全 🔒', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    )
                  ],
                ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
