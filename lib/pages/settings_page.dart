import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import '../services/kazumi_service.dart';
import 'rule_edit_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _storage = StorageService();
  List<AnimeRule> _rules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.loadRules();
    if (mounted) setState(() => _rules = rules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('XPath 驱动的动漫聚合器 · v1.0.0'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('规则管理', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ..._rules.map(
            (r) => ListTile(
              title: Text(r.name.isEmpty ? '(未命名规则)' : r.name),
              subtitle: Text(r.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RuleEditPage(rule: r),
                        ),
                      );
                      _load();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await _storage.deleteRule(r.id);
                      _load();
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text('从 Kazumi 仓库一键拉取'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _showKazumiRules,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('手动添加规则'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RuleEditPage(rule: AnimeRule.empty()),
                  ),
                );
                _load();
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _showKazumiRules() async {
    // 显示 Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final kz = KazumiService();
      final rulesList = await kz.fetchRules();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关掉 Loading

      // 展示拉取到的列表
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) {
              return Column(
                children: [
                  AppBar(
                    title: const Text('选择要导入的规则'),
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      )
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: rulesList.length,
                      itemBuilder: (_, index) {
                        final kRule = rulesList[index];
                        return ListTile(
                          title: Text(kRule['name'] ?? '未知规则'),
                          subtitle: Text(
                            kRule['baseUrl'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () async {
                            // 转换并保存
                            final converted = kz.convertKazumiRule(kRule);
                            
                            // 生成新的规则对象
                            final newRule = AnimeRule(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: converted['name'] ?? '未命名',
                              baseUrl: converted['baseUrl'] ?? '',
                              searchSelector: converted['searchSelector'] ?? '',
                              animeLinkSelector: converted['animeLinkSelector'] ?? '',
                              episodeListSelector: converted['episodeListSelector'] ?? '',
                              episodeLinkSelector: converted['episodeLinkSelector'] ?? '',
                            );
                            
                            await _storage.upsertRule(newRule);
                            
                            if (mounted) {
                              Navigator.pop(sheetContext); // 关掉底部弹窗
                              _load(); // 刷新当前页的规则列表
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已导入: ${newRule.name}')),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 关掉 Loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取失败: $e')),
        );
      }
    }
  }
}
