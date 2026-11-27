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

  // 细粒度锁：防止不同的文件操作互相阻塞，但保证同一文件的并发安全
  static final _rulesLock = Lock();
  static final _historyLock = Lock();
  static final _scheduleLock = Lock();

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  // 核心机制：原子写入（写入临时文件 -> 重命名），防止断电导致数据损坏
  Future<void> _atomicWrite(File targetFile, String content) async {
    final tempFile = File('${targetFile.path}.tmp');
    await tempFile.writeAsString(content, flush: true);
    await tempFile.rename(targetFile.path);
  }

  // 初始化清理：清理上次异常退出残留的 .tmp 文件
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync();
      for (var file in files) {
        if (file.path.endsWith('.tmp')) {
          try { await file.delete(); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[StorageError] 清理临时文件失败: $e');
    }
  }

  // ==================== 规则存储 ====================
  Future<List<AnimeRule>> loadRules() async {
    return await _rulesLock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        if (!await file.exists()) return [];
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return [];
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((e) => AnimeRule.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[StorageError] 读取规则失败: $e');
        return [];
      }
    });
  }

  Future<bool> saveRules(List<AnimeRule> rules) async {
    return await _rulesLock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        await _atomicWrite(file, jsonEncode(rules.map((r) => r.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('[StorageError] 保存规则失败: $e');
        return false;
      }
    });
  }

  Future<bool> upsertRule(AnimeRule rule) async {
    return await _rulesLock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        List<AnimeRule> rules = [];
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isNotEmpty) {
            rules = (jsonDecode(raw) as List).map((e) => AnimeRule.fromJson(e as Map<String, dynamic>)).toList();
          }
        }
        final idx = rules.indexWhere((r) => r.id == rule.id);
        if (idx >= 0) {
          rules[idx] = rule;
        } else {
          rules.add(rule);
        }
        await _atomicWrite(file, jsonEncode(rules.map((r) => r.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('[StorageError] 更新规则失败: $e');
        return false;
      }
    });
  }

  Future<bool> deleteRule(String id) async {
    return await _rulesLock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        if (!await file.exists()) return true;
        
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return true;
        
        final List<AnimeRule> rules = (jsonDecode(raw) as List)
            .map((e) => AnimeRule.fromJson(e as Map<String, dynamic>))
            .toList();
            
        rules.removeWhere((r) => r.id == id);
        await _atomicWrite(file, jsonEncode(rules.map((r) => r.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('[StorageError] 删除规则失败: $e');
        return false;
      }
    });
  }

  // 核心新增：记录源的成功与失败，用于计算信任分
  Future<void> updateRuleStats(String ruleId, {required bool success}) async {
    await _rulesLock.synchronized(() async {
      try {
        final file = await _getFile(_rulesFileName);
        if (!await file.exists()) return;
        
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return;
        
        final List<AnimeRule> rules = (jsonDecode(raw) as List)
            .map((e) => AnimeRule.fromJson(e as Map<String, dynamic>))
            .toList();
            
        final idx = rules.indexWhere((r) => r.id == ruleId);
        if (idx >= 0) {
          final old = rules[idx];
          // 使用不可变更新，重建对象
          rules[idx] = AnimeRule(
            id: old.id, 
            name: old.name, 
            baseUrl: old.baseUrl,
            searchSelector: old.searchSelector, 
            animeLinkSelector: old.animeLinkSelector,
            episodeListSelector: old.episodeListSelector, 
            episodeLinkSelector: old.episodeLinkSelector,
            successCount: success ? old.successCount + 1 : old.successCount,
            failCount: success ? old.failCount : old.failCount + 1,
          );
          await _atomicWrite(file, jsonEncode(rules.map((r) => r.toJson()).toList()));
        }
      } catch (e) {
        debugPrint('[StorageError] 更新规则统计失败: $e');
      }
    });
  }

  // ==================== 历史记录存储 ====================
  Future<List<HistoryItem>> loadHistory() async {
    return await _historyLock.synchronized(() async {
      try {
        final file = await _getFile(_historyFileName);
        if (!await file.exists()) return [];
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return [];
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[StorageError] 读取历史失败: $e');
        return [];
      }
    });
  }

  Future<bool> addHistory(HistoryItem item) async {
    return await _historyLock.synchronized(() async {
      try {
        final file = await _getFile(_historyFileName);
        List<HistoryItem> history = [];
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isNotEmpty) {
             history = (jsonDecode(raw) as List).map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
          }
        }
        history.removeWhere((h) => h.episodeUrl == item.episodeUrl);
        history.insert(0, item);
        while (history.length > 50) {
          history.removeLast();
        }
        await _atomicWrite(file, jsonEncode(history.map((h) => h.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('[StorageError] 保存历史失败: $e');
        return false;
      }
    });
  }

  // ==================== 追番日历存储 ====================
  Future<List<ScheduleItem>> loadSchedules() async {
    return await _scheduleLock.synchronized(() async {
      try {
        final file = await _getFile(_scheduleFileName);
        if (!await file.exists()) return [];
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return [];
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[StorageError] 读取日历失败: $e');
        return [];
      }
    });
  }

  Future<bool> saveSchedules(List<ScheduleItem> items) async {
    return await _scheduleLock.synchronized(() async {
      try {
        final file = await _getFile(_scheduleFileName);
        await _atomicWrite(file, jsonEncode(items.map((e) => e.toJson()).toList()));
        return true;
      } catch (e) {
        debugPrint('[StorageError] 保存日历失败: $e');
        return false;
      }
    });
  }
}
