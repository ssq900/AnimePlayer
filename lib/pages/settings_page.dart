import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import '../services/kazumi_service.dart';
import '../services/sync_service.dart';
import '../services/selector_engine.dart';
import '../services/bangumi_service.dart'; // 🔥 引入 BangumiService
import '../services/exceptions.dart';
import 'rule_edit_page.dart';
import 'package:flutter/services.dart'; // 用于读取剪贴板
import '../utils/animeko_adapter.dart'; // 引入刚写的转换器
import 'debugger_page.dart';

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
  final _bgmUrlController = TextEditingController(); // 🔥 Bangumi 镜像控制器
  bool _syncing = false;
  bool _obscurePass = true;

  Map<String, bool> _healthStatus = {};
  Map<String, bool> _checkingStatus = {};
  bool _checkingAll = false;

// 智能导入规则
Future<void> _importFromClipboard() async {
  final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
  if (clipboardData == null || clipboardData.text == null || clipboardData.text!.isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板为空，请先复制规则 JSON 字符串'), backgroundColor: Colors.orange),
      );
    }
    return;
  }

  final jsonStr = clipboardData.text!;
  try {
    final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
    
    AnimeRule? newRule;

    // 🔥 智能识别逻辑
    if (jsonMap.containsKey('factoryId') || jsonMap.containsKey('searchConfig') || jsonMap.containsKey('arguments')) {
      // 识别为 Animeko 规则
      newRule = AnimekoAdapter.convert(jsonMap);
    } else {
      // 识别为 Kazumi 或普通规则
      newRule = AnimeRule.fromJson(jsonMap);
    }

    if (newRule != null && newRule.baseUrl.isNotEmpty) {
      await _storage.upsertRule(newRule);
      await _loadRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 成功导入规则: ${newRule.name}'), backgroundColor: Colors.green),
        );
      }
    } else {
      throw Exception('解析后规则为空或缺少 BaseUrl');
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: 格式不正确或缺失字段 ($e)'), backgroundColor: Colors.red),
      );
    }
  }
}

  @override
  void initState() {
    super.initState();
    _loadRules();
    _loadWebdavSettings();
    _loadBgmSettings(); // 🔥 加载 Bangumi 配置
  }

  Future<void> _loadRules() async {
    final rules = await _storage.loadRules();
    if (mounted) setState(() => _rules = rules);
  }

  Future<void> _loadWebdavSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _urlController.text = prefs.getString('webdav_url') ?? '';
        _userController.text = prefs.getString('webdav_user') ?? '';
        _passController.text = prefs.getString('webdav_pass') ?? '';
      });
    }
  }

  // 🔥 加载 Bangumi 配置
  Future<void> _loadBgmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _bgmUrlController.text = prefs.getString('bangumi_api_url') ?? BangumiService.defaultBaseUrl;
      });
    }
  }

  Future<void> _saveWebdavSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_url', _urlController.text.trim());
    await prefs.setString('webdav_user', _userController.text.trim());
    await prefs.setString('webdav_pass', _passController.text.trim());
  }

  // ==================== WebDAV 同步 ====================
  Future<void> _doBackup() async {
    setState(() => _syncing = true);
    await _saveWebdavSettings();
    try {
      await SyncService.backupData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 云端备份成功'), backgroundColor: Colors.green),
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份异常: $e'), backgroundColor: Colors.red),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 恢复成功，数据已同步'), backgroundColor: Colors.green),
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复异常: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ==================== 规则测活 ====================
  Future<void> _checkRuleHealth(AnimeRule rule) async {
    setState(() => _checkingStatus[rule.id] = true);
    try {
      final engine = SelectorEngine();
      final url = rule.baseUrl.replaceAll('{keyword}', '');
      await engine.fetchHtml(url, timeout: const Duration(seconds: 10), strategy: "direct");
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
      if (!mounted) break;
      await _checkRuleHealth(rule);
    }
    if (mounted) setState(() => _checkingAll = false);
  }

  // ==================== 规则拉取与下载 ====================
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
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetContext)),
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
                          onTap: () {
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
    } on AppException catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取失败: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取异常: $e'), backgroundColor: Colors.red),
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

      newRule.validate();
      final success = await _storage.upsertRule(newRule);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        await _loadRules();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导入: ${newRule.name}'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导入失败，写入存储出错'), backgroundColor: Colors.red),
          );
        }
      }
    } on RuleFormatException catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已跳过该源: ${e.message}'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载或解析失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _bgmUrlController.dispose(); // 🔥 销毁 Bangumi 控制器
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
          ),
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
              title: Row(
                children: [
                  Expanded(child: Text(r.name.isEmpty ? '(未命名规则)' : r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (r.trustScore > 0.6)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text('⭐', style: TextStyle(fontSize: 14)),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  if (r.lastFailureReason.isNotEmpty)
                    Text(
                      '❌ 失败(${r.lastFailureStage}): ${r.lastFailureReason}',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (r.lastSuccessTime > 0)
                    Text(
                      '✅ 上次成功: ${DateTime.fromMillisecondsSinceEpoch(r.lastSuccessTime).toString().substring(0, 16)}',
                      style: const TextStyle(color: Colors.green, fontSize: 12),
                    )
                  else
                    const Text('⚪ 尚未测试过', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => RuleEditPage(rule: r)));
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('删除失败，请检查存储'), backgroundColor: Colors.red),
                        );
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
                await Navigator.push(context, MaterialPageRoute(builder: (_) => RuleEditPage(rule: AnimeRule.empty())));
                _loadRules();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.content_paste),
              label: const Text('从剪贴板导入 JSON 规则'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              onPressed: _importFromClipboard, // 🔥 绑定刚才的方法
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.bug_report),
              label: const Text('规则调试器 (进阶)'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), foregroundColor: Colors.orange),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DebuggerPage()));
              },
            ),
          ),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('WebDAV 同步', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          // WebDAV 输入框
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(labelText: 'WebDAV 地址', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(labelText: '账号', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passController,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    labelText: '密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _syncing ? null : _doBackup,
                        child: _syncing ? const CircularProgressIndicator() : const Text('备份到云端'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _syncing ? null : _doRestore,
                        child: _syncing ? const CircularProgressIndicator() : const Text('从云端恢复'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 🔥 新增的 Bangumi 配置区域
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Bangumi 元数据配置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _bgmUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Bangumi API 镜像地址',
                    hintText: 'https://api.bgm.tv',
                    helperText: '如果官方地址无法访问，请在此处填入可用的反代或镜像地址',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('保存 API 节点'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('bangumi_api_url', _bgmUrlController.text.trim());
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Bangumi 节点已更新'), backgroundColor: Colors.green),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
