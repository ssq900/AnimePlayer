import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
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
              subtitle: Text(r.baseUrl, maxLines: 1),
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
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加规则'),
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
        ],
      ),
    );
  }
}
