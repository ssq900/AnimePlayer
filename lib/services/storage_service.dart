import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../models/playback_record.dart';
import '../utils/rule_migrator.dart';

class StorageService {
  static const _keyRules = 'anime_rules';
  static const _keyHistory = 'watch_history'; // 兼容旧版
  static const _keyRecords = 'playback_records'; // 新版规范实体
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
      final rules = jsonList.map((e) => AnimeRule.fromJson(e as Map<String, dynamic>)).toList();
      
      // 🔥 尝试平滑迁移到 CSS，并单独 catch 防止一条规则报错拖垮整个列表
      final migratedRules = rules.map((r) {
        try {
          if (!r.isCssBased && r.searchSelector.isNotEmpty) {
            return RuleMigrator.migrateToCss(r);
          }
        } catch (e) {
          debugPrint('[StorageService] 规则迁移失败 (ID: ${r.id}): $e');
        }
        return r;
      }).toList();

      return migratedRules;
    } catch (e, stack) {
      // 🔥 核心修复：打印出真实的 JSON 解析报错，绝不静默吞掉
      debugPrint('[StorageService] 解析规则失败: $e\n$stack');
      return [];
    }
  }

  Future<bool> upsertRule(AnimeRule rule) async {
    try {
      final rules = await loadRules();
      final index = rules.indexWhere((r) => r.id == rule.id);
      if (index >= 0) {
        rules[index] = rule;
      } else {
        rules.add(rule);
      }
      await saveRules(rules);
      return true;
    } catch (e) {
      debugPrint('[StorageService] upsertRule 失败: $e');
      return false;
    }
  }

  Future<bool> deleteRule(String ruleId) async {
    try {
      final rules = await loadRules();
      rules.removeWhere((r) => r.id == ruleId);
      await saveRules(rules);
      return true;
    } catch (e) {
      debugPrint('[StorageService] deleteRule 失败: $e');
      return false;
    }
  }

  // ================= 新版播放记录 (PlaybackRecord) =================
  Future<List<PlaybackRecord>> loadPlaybackRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyRecords);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => PlaybackRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[StorageService] 解析播放记录失败: $e');
      return [];
    }
  }

  Future<void> savePlaybackRecords(List<PlaybackRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    // 按更新时间倒序
    records.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    await prefs.setString(_keyRecords, jsonEncode(records.map((e) => e.toJson()).toList()));
  }

  // 插入或更新一条记录（以 URL 为唯一基准）
  Future<void> upsertPlaybackRecord(PlaybackRecord newRecord) async {
    try {
      final records = await loadPlaybackRecords();
      final index = records.indexWhere((r) => r.url == newRecord.url);
      if (index >= 0) {
        records[index] = newRecord;
      } else {
        records.add(newRecord);
      }
      await savePlaybackRecords(records);
    } catch (e) {
      debugPrint('[StorageService] upsertPlaybackRecord 失败: $e');
    }
  }

  // 获取单条播放记录（用于断点续播）
  Future<PlaybackRecord?> getPlaybackRecord(String url) async {
    final records = await loadPlaybackRecords();
    try {
      return records.firstWhere((r) => r.url == url);
    } catch (_) {
      return null;
    }
  }

  // ================= 旧版历史记录（保留兜底） =================
  Future<void> saveHistory(List<HistoryItem> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHistory, jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  Future<List<HistoryItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyHistory);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[StorageService] 解析历史记录失败: $e');
      return [];
    }
  }

  // ================= 追番表 =================
  Future<void> saveSchedules(List<ScheduleItem> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySchedules, jsonEncode(schedules.map((e) => e.toJson()).toList()));
  }

  Future<List<ScheduleItem>> loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keySchedules);
    if (str == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[StorageService] 解析追番表失败: $e');
      return [];
    }
  }
}
