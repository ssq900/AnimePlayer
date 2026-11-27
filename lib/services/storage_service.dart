import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';

class StorageService {
  static const _keyRules = 'anime_rules';
  static const _keyHistory = 'watch_history';

  // ================= 规则相关 =================
  Future<void> saveRules(List<AnimeRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = rules.map((e) => e.toJson()).toList();
    await prefs.setString(_keyRules, jsonEncode(jsonList));
  }

  Future<List<AnimeRule>> getRules() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyRules);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => AnimeRule.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ================= 历史记录相关 =================
  // 使用 dynamic 接收，避免因为项目中 HistoryItem 的类名或结构不同导致编译报错
  Future<void> saveHistory(List<dynamic> history) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = history.map((e) {
      try {
        // 假设你的 HistoryItem 实现了 toJson 方法
        return e.toJson();
      } catch (_) {
        return e;
      }
    }).toList();
    await prefs.setString(_keyHistory, jsonEncode(jsonList));
  }

  Future<List<dynamic>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyHistory);
    if (str == null) return [];
    try {
      return jsonDecode(str);
    } catch (e) {
      return [];
    }
  }

  // ================= 清理数据 =================
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }
}
