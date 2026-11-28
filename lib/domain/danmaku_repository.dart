import 'dart:async';
import 'danmaku_provider.dart';

class DanmakuRepository {
  final List<DanmakuProvider> _providers;

  DanmakuRepository(this._providers);

  /// 并发拉取所有源的弹幕，合并并去重
  Future<List<DanmakuItem>> loadAll(String animeTitle, int episode) async {
    // 1. 并发请求所有 Provider
    final futures = _providers.map((p) => p.fetch(animeTitle, episode)).toList();
    
    // 2. 等待所有源返回（即使某个源报错，catch 也会返回空列表，不会中断）
    final results = await Future.wait(futures);

    final allItems = <DanmakuItem>[];
    final seenTexts = <String>{};

    // 3. 聚合与去重
    for (final list in results) {
      for (final item in list) {
        // 核心去重逻辑：相同时间（取整）且相同文本，视为同一条弹幕
        final key = '${item.time.toInt()}_${item.text}';
        
        if (!seenTexts.contains(key)) {
          seenTexts.add(key);
          allItems.add(item);
        }
      }
    }

    // 4. 按时间轴全局排序，准备交给 UI 层渲染
    allItems.sort((a, b) => a.time.compareTo(b.time));
    
    return allItems;
  }
}
