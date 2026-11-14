import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter/foundation.dart';

class SyncService {
  // 核心修复：引入全局锁，防止云端恢复与本地规则写入发生冲突
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

  static Future<File> _getLocalFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<void> backupData() async {
    await _syncLock.synchronized(() async {
      final client = await _getClient();
      if (client == null) throw Exception('请先配置完整的 WebDAV 信息');
      
      try {
        await client.mkdir('/AnimeAggregator');
      } catch (_) {
        // 目录已存在忽略
      }

      final rulesFile = await _getLocalFile('anime_rules.json');
      final historyFile = await _getLocalFile('anime_history.json');
      final scheduleFile = await _getLocalFile('anime_schedule.json');

      final Map<String, dynamic> backup = {
        'schemaVersion': 1, // 核心修复：增加数据版本号
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
      
      // 核心修复：防止坏 JSON 直接落盘导致数据全丢
      Map<String, dynamic> backup;
      try {
        backup = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (!backup.containsKey('rules') || !backup.containsKey('history')) {
          throw const FormatException('备份文件缺少核心字段');
        }
      } catch (e) {
        throw Exception('云端备份文件已损坏或格式不兼容: $e');
      }

      // 核心修复：覆盖前将旧数据备份为 .bak
      final rulesFile = await _getLocalFile('anime_rules.json');
      final historyFile = await _getLocalFile('anime_history.json');
      final scheduleFile = await _getLocalFile('anime_schedule.json');

      if (await rulesFile.exists()) await rulesFile.copy('${rulesFile.path}.bak');
      if (await historyFile.exists()) await historyFile.copy('${historyFile.path}.bak');
      if (await scheduleFile.exists()) await scheduleFile.copy('${scheduleFile.path}.bak');

      try {
        if (backup['rules'] != null) {
          await rulesFile.writeAsString(jsonEncode(backup['rules']));
        }
        if (backup['history'] != null) {
          await historyFile.writeAsString(jsonEncode(backup['history']));
        }
        if (backup['schedule'] != null) {
          await scheduleFile.writeAsString(jsonEncode(backup['schedule']));
        }
      } catch (e) {
        // 写入失败则尝试从 bak 回滚
        debugPrint('写入失败，尝试回滚: $e');
        if (await File('${rulesFile.path}.bak').exists()) {
          await File('${rulesFile.path}.bak').copy(rulesFile.path);
        }
        throw Exception('数据恢复失败，已尽量为您回滚');
      }
    });
  }
}
