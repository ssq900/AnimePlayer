import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import '../models/rule.dart';
import 'storage_service.dart';

class SyncService {
  // 独立的锁，防止多次点击备份/恢复导致网络请求冲突
  static final _syncLock = Lock();

  static Future<webdav.Client?> _getClient() async {
    final prefs = await SharedPreferences.getInstance();
    String url = prefs.getString('webdav_url') ?? '';
    final user = prefs.getString('webdav_user') ?? '';
    final pass = prefs.getString('webdav_pass') ?? '';
    
    if (url.isEmpty || user.isEmpty) return null;
    if (!url.endsWith('/')) url += '/';

    return webdav.newClient(
      url,
      user: user,
      password: pass,
      debug: false,
    );
  }

  static Future<void> backupData() async {
    await _syncLock.synchronized(() async {
      final client = await _getClient();
      if (client == null) throw Exception('请先配置完整的 WebDAV 信息');
      
      try {
        await client.mkdir('/AnimeAggregator');
      } catch (_) {}

      final dir = await getApplicationDocumentsDirectory();
      final rulesFile = File('${dir.path}/anime_rules.json');
      final historyFile = File('${dir.path}/anime_history.json');
      final scheduleFile = File('${dir.path}/anime_schedule.json');

      final Map<String, dynamic> backup = {
        'rules': rulesFile.existsSync() ? jsonDecode(await rulesFile.readAsString()) : [],
        'history': historyFile.existsSync() ? jsonDecode(await historyFile.readAsString()) : [],
        'schedule': scheduleFile.existsSync() ? jsonDecode(await scheduleFile.readAsString()) : [],
      };

      final bytes = utf8.encode(jsonEncode(backup));
      await client.write('/AnimeAggregator/backup.json', bytes);
    });
  }

  static Future<void> restoreData() async {
    await _syncLock.synchronized(() async {
      final client = await _getClient();
      if (client == null) throw Exception('请先配置完整的 WebDAV 信息');

      final bytes = await client.read('/AnimeAggregator/backup.json');
      final String jsonStr = utf8.decode(bytes);
      final Map<String, dynamic> backup = jsonDecode(jsonStr);

      // 核心修复：不再直接操作文件系统，委托给 StorageService 进行原子写入
      final storage = StorageService();
      
      if (backup['rules'] != null) {
        final rules = (backup['rules'] as List).map((e) => AnimeRule.fromJson(e as Map<String, dynamic>)).toList();
        await storage.saveRules(rules);
      }
      
      if (backup['history'] != null) {
        final history = (backup['history'] as List).map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
        await storage.saveHistory(history);
      }
      
      if (backup['schedule'] != null) {
        final schedules = (backup['schedule'] as List).map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
        await storage.saveSchedules(schedules);
      }
    });
  }
}
