import 'package:flutter/material.dart';
import 'settings_page.dart';
import 'stats_page.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.bar_chart, color: Colors.deepPurple),
            title: const Text('观看统计'),
            subtitle: const Text('查看你的电子榨菜报告'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsPage())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.deepPurple),
            title: const Text('设置与规则管理'),
            subtitle: const Text('导入规则、WebDAV同步、源测活'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.grey),
            title: Text('关于 AnimePlayer'),
            subtitle: Text('v1.0.0 · 仅供学习交流'),
          ),
        ],
      ),
    );
  }
}
