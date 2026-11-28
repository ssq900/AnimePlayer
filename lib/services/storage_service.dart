import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../utils/rule_migrator.dart'; // 🔥 引入迁移器

class StorageService {
  static const _keyRules = 'anime_rules';
  static const _keyHistory = 'watch_history';
  static const _keySchedules = 'schedules';

  Future<void> init() async {
    // 初始化动作，目前留空
  }

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
      final rules = jsonList.map((e) => AnimeRule.fromJson(e)).toList();
      
      // 🔥 核心：在读取时自动尝试平滑迁移到 CSS
      // 这样旧规则也能享受新引擎的速度
      final migratedRules = rules.map((r) {
        // 如果它有 XPath 但没有标记为 CSS，说明是老规则，自动转换
        if (!r.isCssBased && r.searchSelector.isNotEmpty) {
          return RuleMigrator.migrateToCss(r);
        }
        return r;
      }).toList();

      return migratedRules;
    } catch (e) {
      return [];
    }
  }

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
  Future<void> saveHistory(List<dynamic> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHistory, jsonEncode(history.map((e) {
      try { return e.toJson(); } catch (_) { return e; }
    }).toList()));
  }

  Future<List<dynamic>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyHistory);
    if (str == null) return [];
    try { return jsonDecode(str); } catch (_) { return []; }
  }

  // ================= 追番表 =================
  Future<void> saveSchedules(List<dynamic> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySchedules, jsonEncode(schedules.map((e) {
      try { return e.toJson(); } catch (_) { return e; }
    }).toList()));
  }

  Future<List<dynamic>> loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keySchedules);
    if (str == null) return [];
    try { return jsonDecode(str); } catch (_) { return []; }
  }
}
