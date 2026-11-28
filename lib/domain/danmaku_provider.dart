import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 弹幕数据模型
class DanmakuItem {
  final double time; // 出现时间（秒）
  final String text;
  final int color;   // 颜色，如 0xFFFFFF
  final int type;    // 0:滚动, 1:顶部, 2:底部

  DanmakuItem({
    required this.time,
    required this.text,
    this.color = 0xFFFFFF,
    this.type = 0,
  });
}

/// 弹幕数据源统一接口
abstract class DanmakuProvider {
  String get name;
  /// 根据番剧名和集数获取弹幕
  Future<List<DanmakuItem>> fetch(String animeTitle, int episode);
}

// ========================================================
// 1. 本地 JSON 提供者（支持离线导入的弹幕）
// ========================================================
class LocalJsonProvider implements DanmakuProvider {
  @override
  String get name => '本地弹幕';

  @override
  Future<List<DanmakuItem>> fetch(String animeTitle, int episode) async {
    // TODO: 以后从 StorageService 或本地文件中读取用户导入的 JSON
    return []; 
  }
}

// ========================================================
// 2. 弹弹play 在线提供者（预留核心骨架）
// ========================================================
class DandanplayProvider implements DanmakuProvider {
  @override
  String get name => '弹弹play';

  @override
  Future<List<DanmakuItem>> fetch(String animeTitle, int episode) async {
    try {
      // 弹弹play 真实流程：1. 搜索番剧获取 animeId -> 2. 获取对应集的 epId -> 3. 请求弹幕
      // 这里为了不阻塞编译，先返回空列表，未来只需在这里填入真实的 HTTP 请求即可
      
      // 示例伪代码：
      // final res = await http.get(Uri.parse('https://api.dandanplay.net/api/v2/search/episodes?anime=$animeTitle&episode=$episode'));
      // final data = jsonDecode(res.body);
      // 解析成 List<DanmakuItem> 返回
      
      return [];
    } catch (e) {
      // 某个在线源挂了，不能影响其他源和主流程
      return [];
    }
  }
}

// ========================================================
// 3. 依赖注入配置
// ========================================================
final danmakuProvidersProvider = Provider<List<DanmakuProvider>>((ref) {
  return [
    LocalJsonProvider(),
    DandanplayProvider(), // 以后如果接别的源，在这里 add 进去即可
  ];
});
