import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/rule.dart';

class StorageService {
  static const _rulesFileName = 'anime_rules.json';
  static const _historyFileName = 'anime_history.json';
  static const _scheduleFileName = 'anime_schedule.json';

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  // ===== 规则存储 =====
  Future<List<AnimeRule>> loadRules() async {
    final file = await _getFile(_rulesFileName);
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
    final file = await _getFile(_rulesFileName);
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
    final file = await _getFile(_historyFileName);
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
    history.removeWhere((h) => h.episodeUrl == item.episodeUrl);
    history.insert(0, item);
    
    while (history.length > 50) {
      history.removeLast();
    }
    
    final file = await _getFile(_historyFileName);
    await file.writeAsString(jsonEncode(history.map((h) => h.toJson()).toList()));
  }

  // ===== 追番日历存储 =====
  Future<List<ScheduleItem>> loadSchedules() async {
    final file = await _getFile(_scheduleFileName);
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSchedules(List<ScheduleItem> items) async {
    final file = await _getFile(_scheduleFileName);
    await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
