import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import '../services/kazumi_service.dart';
import '../services/sync_service.dart';
import 'rule_edit_page.dart';
import 'debugger_page.dart';
import '../services/xpath_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _storage = StorageService();
  List<AnimeRule> _rules = [];

  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _syncing = false;
  bool _obscurePass = true;

  Map<String, bool> _healthStatus = {};
  Map<String, bool> _checkingStatus = {};
  bool _checkingAll = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _loadWebdavSettings();
  }

  Future<void> _loadRules() async {
    final rules = await _storage.loadRules();
    if (mounted) setState(() => _rules = rules);
  }

  Future<void> _loadWebdavSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('webdav_url') ?? '';
      _userController.text = prefs.getString('webdav_user') ?? '';
      _passController.text = prefs.getString('webdav_pass') ?? '';
    });
  }

  Future<void> _saveWebdavSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_url', _urlController.text.trim());
    await prefs.setString('webdav_user', _userController.text.trim());
    await prefs.setString('webdav_pass', _passController.text.trim());
  }

  Future<void> _doBackup() async {
    setState(() => _syncing = true);
    await _saveWebdavSettings();
    try {
      await SyncService.backupData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 备份成功')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _doRestore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('此操作将覆盖本地的规则、历史和日历，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定恢复')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _syncing = true);
    await _saveWebdavSettings();
    try {
      await SyncService.restoreData();
      await _loadRules();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 恢复成功，数据已同步')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _checkRuleHealth(AnimeRule rule) async {
    setState(() => _checkingStatus[rule.id] = true);
    try {
      final xpath = XPathService();
      final url = rule.baseUrl.replaceAll('{keyword}', '');
      await xpath.fetchHtml(url);
      if (mounted) setState(() => _healthStatus[rule.id] = true);
    } catch (_) {
      if (mounted) setState(() => _healthStatus[rule.id] = false);
    } finally {
      if (mounted) setState(() => _checkingStatus[rule.id] = false);
    }
  }

  Future<void> _checkAllHealth() async {
    setState(() {
      _checkingAll = true;
      _healthStatus.clear();
    });
    for (var rule in _rules) {
      await _checkRuleHealth(rule);
    }
    if (mounted) setState(() => _checkingAll = false);
  }

  Future<void> _showKazumiRules() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final kz = KazumiService();
      final indexList = await kz.fetchRuleIndex();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); 

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
                      itemCount: indexList.length,
                      itemBuilder: (_, index) {
                        final item = indexList[index];
                        final name = item['name'] ?? '未知规则';
                        final fileName = item['file'] ?? '${item['name']}.json';

                        return ListTile(
                          title: Text(name),
                          subtitle: Text(item['baseUrl'] ?? ''),
                          trailing: const Icon(Icons.download_for_offline_outlined),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            _downloadAndSave(kz, fileName, name);
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
        Navigator.of(context, rootNavigator: true).pop(); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('索引拉取失败: $e')),
        );
      }
    }
  }

  Future<void> _downloadAndSave(KazumiService kz, String fileName, String ruleName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final detail = await kz.fetchRuleDetail(fileName);
      final converted = kz.convertKazumiRule(detail);

      final newRule = AnimeRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: converted['name'] ?? ruleName,
        baseUrl: converted['baseUrl'] ?? '',
        searchSelector: converted['searchSelector'] ?? '',
        animeLinkSelector: converted['animeLinkSelector'] ?? '',
        episodeListSelector: converted['episodeListSelector'] ?? '',
        episodeLinkSelector: converted['episodeLinkSelector'] ?? '',
      );

      final success = await _storage.upsertRule(newRule);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        if (success) {
          _loadRules();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入: ${newRule.name}')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入失败，请检查存储'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            icon: _checkingAll 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.network_check),
            tooltip: '一键检测源健康',
            onPressed: _checkingAll ? null : _checkAllHealth,
          )
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('规则管理 (右上角可一键测活)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无规则，请从下方导入。', style: TextStyle(color: Colors.grey)),
            ),
          ..._rules.map(
            (r) => ListTile(
              leading: _checkingStatus[r.id] == true
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(
                      _healthStatus[r.id] == null
                          ? Icons.circle_outlined
                          : (_healthStatus[r.id]! ? Icons.check_circle : Icons.error),
                      color: _healthStatus[r.id] == null
                          ? Colors.grey
                          : (_healthStatus[r.id]! ? Colors.green : Colors.red),
                    ),
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
                        MaterialPageRoute(builder: (_) => RuleEditPage(rule: r)),
                      );
                      _loadRules();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final success = await _storage.deleteRule(r.id);
                      if (success) {
                        _loadRules();
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请检查存储')));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text('从 Kazumi 仓库一键拉取'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              onPressed: _showKazumiRules,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('手动添加规则'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RuleEditPage(rule: AnimeRule.empty())),
                );
                _loadRules();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.bug_report),
              label: const Text('规则调试器 (进阶)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: Colors.orange,
              ),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DebuggerPage()));
              },
            ),
          ),

          const Divider(height: 32),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('云端同步 (WebDAV)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: '例如: https://dav.jianguoyun.com/dav/',
                      ),
                    ),
                    TextField(
                      controller: _userController,
                      decoration: const InputDecoration(labelText: '账号/邮箱'),
                    ),
                    TextField(
                      controller: _passController,
                      obscureText: _obscurePass,
                      decoration: InputDecoration(
                        labelText: '密码/应用密码',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _syncing ? null : _doRestore,
                            child: const Text('恢复数据'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _syncing ? null : _doBackup,
                            child: _syncing 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('备份到云端'),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
