import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/rule.dart';

class StorageService {
  static const _fileName = 'anime_rules.json';

  Future<File> _rulesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<AnimeRule>> loadRules() async {
    final file = await _rulesFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AnimeRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRules(List<AnimeRule> rules) async {
    final file = await _rulesFile();
    await file.writeAsString(
      jsonEncode(rules.map((r) => r.toJson()).toList()),
    );
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
}
