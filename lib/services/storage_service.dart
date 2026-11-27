import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';

class StorageService {
  static const _keyRules = 'anime_rules';
  static const _keyHistory = 'watch_history';
  static const _keySchedules = 'schedules';

  Future<void> init() async {}

  // ================= 规则 =================
  Future<void> saveRules(List<AnimeRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRules, jsonEncode(rules.map((e) => e.toJson()).toList()));
  }

  Future<List<AnimeRule>> loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyRules);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => AnimeRule.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ⚠️ 恢复 bool 返回值，修复 settings_page 报错
  Future<bool> upsertRule(AnimeRule rule) async {
    final rules = await loadRules();
    final index = rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }
    await saveRules(rules);
    return true;
  }

  Future<bool> deleteRule(String ruleId) async {
    final rules = await loadRules();
    rules.removeWhere((r) => r.id == ruleId);
    await saveRules(rules);
    return true;
  }

  // ================= 历史记录 =================
  Future<void> saveHistory(List<HistoryItem> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHistory, jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  // ⚠️ 修复 List<dynamic> 无法赋值给 List<HistoryItem> 的问题
  Future<List<HistoryItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyHistory);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => HistoryItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ================= 追番表 =================
  Future<void> saveSchedules(List<ScheduleItem> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySchedules, jsonEncode(schedules.map((e) => e.toJson()).toList()));
  }

  // ⚠️ 修复 List<dynamic> 无法赋值给 List<ScheduleItem> 的问题
  Future<List<ScheduleItem>> loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keySchedules);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => ScheduleItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
