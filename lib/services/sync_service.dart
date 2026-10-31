import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path_provider/path_provider.dart';

class SyncService {
  // 获取配置好的 WebDAV 客户端
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

  // 备份数据到云端
  static Future<void> backupData() async {
    final client = await _getClient();
    if (client == null) throw Exception('请先配置完整的 WebDAV 信息');
    
    // 尝试创建目录（如果已存在会被忽略）
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
  }

  // 从云端恢复数据
  static Future<void> restoreData() async {
    final client = await _getClient();
    if (client == null) throw Exception('请先配置完整的 WebDAV 信息');

    final bytes = await client.read('/AnimeAggregator/backup.json');
    final String jsonStr = utf8.decode(bytes);
    final Map<String, dynamic> backup = jsonDecode(jsonStr);

    final dir = await getApplicationDocumentsDirectory();
    
    if (backup['rules'] != null) {
      await File('${dir.path}/anime_rules.json').writeAsString(jsonEncode(backup['rules']));
    }
    if (backup['history'] != null) {
      await File('${dir.path}/anime_history.json').writeAsString(jsonEncode(backup['history']));
    }
    if (backup['schedule'] != null) {
      await File('${dir.path}/anime_schedule.json').writeAsString(jsonEncode(backup['schedule']));
    }
  }
}
