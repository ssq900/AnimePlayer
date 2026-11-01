import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter/foundation.dart';
import '../models/rule.dart';

class StorageService {
  static const _rulesFileName = 'anime_rules.json';
  static const _historyFileName = 'anime_history.json';
  static const _scheduleFileName = 'anime_schedule.json';

  static final _lock = Lock();

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  // ===== 规则存储 =====
  Future<List<AnimeRule>> _loadRulesUnsafe() async {
    try {
      final file = await _getFile(_rulesFileName);
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => AnimeRule.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('读取规则失败: $e');
      return [];
    }
  }

  Future<List<AnimeRule>> loadRules() async {
    return await _lock.synchronized(() => _loadRulesUnsafe());
  }

  Future<bool> saveRules(List<AnimeRule> rules) async {
    return await _lock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('保存规则失败: $e');
        return false;
      }
    });
  }

  Future<bool> upsertRule(AnimeRule rule) async {
    return await _lock.synchronized(() async {
      try {
        final rules = await _loadRulesUnsafe(); // 使用无锁方法防死锁
        final idx = rules.indexWhere((r) => r.id == rule.id);
        if (idx >= 0) {
          rules[idx] = rule;
        } else {
          rules.add(rule);
        }
        final file = await _getFile(_rulesFileName);
        await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('更新规则失败: $e');
        return false;
      }
    });
  }

  Future<bool> deleteRule(String id) async {
    return await _lock.synchronized(() async {
      try {
        final rules = await _loadRulesUnsafe();
        rules.removeWhere((r) => r.id == id);
        final file = await _getFile(_rulesFileName);
        await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('删除规则失败: $e');
        return false;
      }
    });
  }

  // ===== 历史记录存储 =====
  Future<List<HistoryItem>> _loadHistoryUnsafe() async {
    try {
      final file = await _getFile(_historyFileName);
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('读取历史失败: $e');
      return [];
    }
  }

  Future<List<HistoryItem>> loadHistory() async {
    return await _lock.synchronized(() => _loadHistoryUnsafe());
  }

  Future<bool> addHistory(HistoryItem item) async {
    return await _lock.synchronized(() async {
      try {
        final history = await _loadHistoryUnsafe();
        history.removeWhere((h) => h.episodeUrl == item.episodeUrl);
        history.insert(0, item);
        
        while (history.length > 50) {
          history.removeLast();
        }
        
        final file = await _getFile(_historyFileName);
        await file.writeAsString(jsonEncode(history.map((h) => h.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('保存历史失败: $e');
        return false;
      }
    });
  }

  // ===== 追番日历存储 =====
  Future<List<ScheduleItem>> _loadSchedulesUnsafe() async {
    try {
      final file = await _getFile(_scheduleFileName);
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('读取日历失败: $e');
      return [];
    }
  }

  Future<List<ScheduleItem>> loadSchedules() async {
    return await _lock.synchronized(() => _loadSchedulesUnsafe());
  }

  Future<bool> saveSchedules(List<ScheduleItem> items) async {
    return await _lock.synchronized(() async {
      try {
        final file = await _getFile(_scheduleFileName);
        await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('保存日历失败: $e');
        return false;
      }
    });
  }
}
