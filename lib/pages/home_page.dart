import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'rule_edit_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _storage = StorageService();
  List<AnimeRule> _rules = [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.loadRules();
    if (!mounted) return;
    
    setState(() {
      _rules = rules;
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
      body: _rules.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('还没有规则'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _addRule,
                    child: const Text('添加第一条规则'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('开始搜索'),
                  onPressed: _selectedId == null
                      ? null
                      : () {
                          final currentRule = _rules.firstWhere((r) => r.id == _selectedId);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SearchPage(rule: currentRule),
                            ),
                          );
                        },
                ),
              ],
            ),
    );
  }

  Future<void> _addRule() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RuleEditPage(rule: AnimeRule.empty()),
      ),
    );
    _load();
  }
}
