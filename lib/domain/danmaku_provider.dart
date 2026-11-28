import 'package:flutter_riverpod/flutter_riverpod.dart';

class DanmakuItem {
  final double time; // 出现时间（秒）
  final String text;
  final int color;
  final int type; // 0:滚动, 1:顶部, 2:底部

  DanmakuItem({
    required this.time,
    required this.text,
    this.color = 0xFFFFFF,
    this.type = 0,
  });
}

abstract class DanmakuProvider {
  String get name;
  Future<List<DanmakuItem>> fetch(String animeTitle, int episode);
}

// 本地 JSON 提供者（预留坑位）
class LocalJsonProvider implements DanmakuProvider {
  @override
  String get name => '本地弹幕';

  @override
  Future<List<DanmakuItem>> fetch(String animeTitle, int episode) async {
    // 以后从 StorageService 或本地文件中读取
    return []; 
  }
}

// 弹弹play 提供者（预留坑位，后续可接入 API）
class DandanplayProvider implements DanmakuProvider {
  @override
  String get name => '弹弹play';

  @override
  Future<List<DanmakuItem>> fetch(String animeTitle, int episode) async {
    // TODO: 调用弹弹play API
    return [];
  }
}

final danmakuProvidersProvider = Provider<List<DanmakuProvider>>((ref) {
  return [
    LocalJsonProvider(),
    DandanplayProvider(),
  ];
});
