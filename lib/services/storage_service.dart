import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import '../models/rule.dart';

class StorageService {
  static const _rulesFileName = 'anime_rules.json';
  static const _historyFileName = 'anime_history.json';
  static const _scheduleFileName = 'anime_schedule.json';

  // 核心修复：引入全局锁，防止多线程并发读写导致文件损坏
  static final _lock = Lock();

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  // ===== 规则存储 =====
  Future<List<AnimeRule>> loadRules() async {
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

  Future<void> saveRules(List<AnimeRule> rules) async {
    await _lock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
      } catch (e) {
        debugPrint('保存规则失败: $e');
      }
    });
  }

  Future<void> upsertRule(AnimeRule rule) async {
    await _lock.synchronized(() async {
      final rules = await loadRules();
      final idx = rules.indexWhere((r) => r.id == rule.id);
      if (idx >= 0) {
        rules[idx] = rule;
      } else {
        rules.add(rule);
      }
      try {
        final file = await _getFile(_rulesFileName);
        await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
      } catch (e) {
        debugPrint('更新规则失败: $e');
      }
    });
  }

  Future<void> deleteRule(String id) async {
    await _lock.synchronized(() async {
      final rules = await loadRules();
      rules.removeWhere((r) => r.id == id);
      try {
        final file = await _getFile(_rulesFileName);
        await file.writeAsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
      } catch (e) {
        debugPrint('删除规则失败: $e');
      }
    });
  }

  // ===== 历史记录存储 =====
  Future<List<HistoryItem>> loadHistory() async {
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

  Future<void> addHistory(HistoryItem item) async {
    await _lock.synchronized(() async {
      final history = await loadHistory();
      history.removeWhere((h) => h.episodeUrl == item.episodeUrl);
      history.insert(0, item);
      
      while (history.length > 50) {
        history.removeLast();
      }
      
      try {
        final file = await _getFile(_historyFileName);
        await file.writeAsString(jsonEncode(history.map((h) => h.toJson()).toList()));
      } catch (e) {
        debugPrint('保存历史失败: $e');
      }
    });
  }

  // ===== 追番日历存储 =====
  Future<List<ScheduleItem>> loadSchedules() async {
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

  Future<void> saveSchedules(List<ScheduleItem> items) async {
    await _lock.synchronized(() async {
      try {
        final file = await _getFile(_scheduleFileName);
        await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
      } catch (e) {
        debugPrint('保存日历失败: $e');
      }
    });
  }
}

// 简单的日志打印工具，避免导入flutter/material.dart导致其他纯Dart文件报错
void debugPrint(String message) {
  // 调试时可打开下面这行，发布时无需改动
  // print('[StorageService] $message');
}
