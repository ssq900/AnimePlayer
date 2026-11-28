import 'danmaku_provider.dart';

class DanmakuRepository {
  final List<DanmakuProvider> _providers;

  DanmakuRepository(this._providers);

  Future<List<DanmakuItem>> loadAll(String animeTitle, int episode) async {
    final futures = _providers.map((p) => p.fetch(animeTitle, episode)).toList();
    final results = await Future.wait(futures);

    final allItems = <DanmakuItem>[];
    final seenTexts = <String>{};

    for (final list in results) {
      for (final item in list) {
        // 去重逻辑：同一秒内相同的文本只保留一条
        final key = '${item.time.toInt()}_${item.text}';
        if (!seenTexts.contains(key)) {
          seenTexts.add(key);
          allItems.add(item);
        }
      }
    }

    // 按时间轴排序
    allItems.sort((a, b) => a.time.compareTo(b.time));
    return allItems;
  }
}
