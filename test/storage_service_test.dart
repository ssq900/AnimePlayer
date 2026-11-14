import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:anime_aggregator/services/storage_service.dart';
import 'package:anime_aggregator/models/rule.dart';

class MockPathProviderPlatform extends Mock with MockPlatformInterfaceMixin implements PathProviderPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anime_test_');
    final mockPathProvider = MockPathProviderPlatform();
    when(() => mockPathProvider.getApplicationDocumentsPath()).thenAnswer((_) async => tempDir.path);
    PathProviderPlatform.instance = mockPathProvider;
    storage = StorageService();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('并发写入不会导致数据损坏', () async {
    final futures = <Future<bool>>[];
    for (int i = 0; i < 10; i++) {
      futures.add(storage.addHistory(HistoryItem(
        ruleId: 'rule1', ruleName: 'test', animeTitle: 'Anime', episodeTitle: 'Ep$i', 
        episodeUrl: 'url$i', timestamp: DateTime.now().millisecondsSinceEpoch
      )));
    }
    final results = await Future.wait(futures);
    expect(results.every((e) => e == true), isTrue);

    final history = await storage.loadHistory();
    expect(history.length, 10); // 没有相互覆盖
  });

  test('初始化时应当清理 .tmp 文件', () async {
    final tmpFile = File('${tempDir.path}/anime_rules.json.tmp');
    await tmpFile.writeAsString('dirty data');
    
    await storage.init();
    expect(await tmpFile.exists(), isFalse);
  });

  test('加载损坏的 JSON 时应当返回空列表而不崩溃', () async {
    final corruptFile = File('${tempDir.path}/anime_rules.json');
    await corruptFile.writeAsString('{ "broken": [1, 2, 3] ... }'); // 不完整的数据
    
    final rules = await storage.loadRules();
    expect(rules, isEmpty);
  });
}
