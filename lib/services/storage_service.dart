import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/rule.dart';

class StorageService {
  static const _fileName = 'anime_rules.json';
  static const _historyFileName = 'anime_history.json';

  Future<File> _rulesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<File> _historyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_historyFileName');
  }

  // ===== 规则存储 =====
  Future<List<AnimeRule>> loadRules() async {
    final file = await _rulesFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => AnimeRule.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRules(List<AnimeRule> rules) async {
    final file = await _rulesFile();
    await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
  }

  Future<void> upsertRule(AnimeRule rule) async {
    final rules = await loadRules();
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    await saveRules(rules);
  }

  Future<void> deleteRule(String id) async {
    final rules = await loadRules();
    rules.removeWhere((r) => r.id == id);
    await saveRules(rules);
  }

  // ===== 历史记录存储 =====
  Future<List<HistoryItem>> loadHistory() async {
    final file = await _historyFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistory(HistoryItem item) async {
    final history = await loadHistory();
    
    // 移除同一个剧集，保证最新看过的在最上面
    history.removeWhere((h) => h.episodeUrl == item.episodeUrl);
    history.insert(0, item);
    
    // 修复 Bug 3: 使用 while 循环，确保严格不超过 50 条
    while (history.length > 50) {
      history.removeLast();
    }
    
    final file = await _historyFile();
    await file.writeAsString(jsonEncode(history.map((h) => h.toJson()).toList()));
  }
}
