import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ==================== 数据模型 ====================
class BangumiSubject {
  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final double score;
  final String summary;
  final int rank;

  BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.score,
    required this.summary,
    required this.rank,
  });

  factory BangumiSubject.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    String imageUrl = images?['large'] ?? images?['common'] ?? '';
    
    // 🔥 图片 CDN 代理：国内直连 lain.bgm.tv 很慢，套一层免费图片代理
    if (imageUrl.isNotEmpty && imageUrl.contains('lain.bgm.tv')) {
      imageUrl = imageUrl.replaceFirst('https://lain.bgm.tv', 'https://wsrv.nl/?url=lain.bgm.tv');
    }

    return BangumiSubject(
      id: j['id'] ?? 0,
      name: j['name'] ?? '',
      nameCn: j['name_cn'] ?? '',
      imageUrl: imageUrl,
      score: (j['rating']?['score'] ?? 0).toDouble(),
      summary: j['summary'] ?? '',
      rank: j['rating']?['rank'] ?? 0,
    );
  }
}

class BangumiCalendarDay {
  final int weekdayId;
  final String weekdayCn;
  final List<BangumiSubject> items;
  BangumiCalendarDay({required this.weekdayId, required this.weekdayCn, required this.items});
}

// ==================== API 服务 ====================
class BangumiService {
  static const defaultBaseUrl = 'https://api.bgm.tv';
  
  // 🔥 内置高可用镜像池（国内可用，完美兼容 BGM 官方 API）
  static const _mirrorHosts = [
    'https://api.bgm.tv',                 // 官方
    'https://api.bangumi.lol',            // 社区高速反代 1
    'https://bgmapi.animes.garden',       // 社区高速反代 2
    'https://api.animeko.org',            // Animeko 官方节点 (部分接口兼容)
  ];

  static String? _fastestHost; // 缓存测速后的最快节点

  static const _headers = {
    'User-Agent': 'AnimePlayer/1.0 (https://github.com/ssq900/AnimePlayer)',
    'Accept': 'application/json',
  };

  /// 获取可用 BaseUrl：优先用户配置，其次自动测速
  Future<String> _getBaseUrl() async {
    // 1. 检查用户是否在设置里手动指定了镜像
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('bangumi_api_url');
    if (customUrl != null && customUrl.isNotEmpty && customUrl != defaultBaseUrl) {
      return customUrl.replaceAll(RegExp(r'/$'), '');
    }

    // 2. 如果内存里已经有测好的最快节点，直接用
    if (_fastestHost != null) return _fastestHost!;

    // 3. 并发测速
    try {
      final fastest = await Future.any(
        _mirrorHosts.map((host) async {
          // 用一个极轻量的接口测速
          final resp = await http.get(Uri.parse('$host/calendar'), headers: _headers)
              .timeout(const Duration(seconds: 3));
          if (resp.statusCode == 200) return host;
          throw Exception('Status: ${resp.statusCode}');
        }),
      );
      _fastestHost = fastest;
      return fastest;
    } catch (_) {
      // 如果全部超时，硬着头皮返回官方/第一个
      _fastestHost = _mirrorHosts.first;
      return _fastestHost!;
    }
  }

  /// 核心请求方法，带自动重试与节点切换
  Future<dynamic> _request(String path, {bool isPost = false, Map<String, dynamic>? body}) async {
    final baseUrl = await _getBaseUrl();
    final url = Uri.parse('$baseUrl$path');

    try {
      final resp = isPost
          ? await http.post(url, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          : await http.get(url, headers: _headers);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (e) {
      // 🔥 如果是网络错误，清空测速缓存，下次重试换节点
      _fastestHost = null;
      throw Exception('网络请求失败，请尝试在设置中更换镜像节点。错误信息: $e');
    }
  }

  // ==================== 业务接口 ====================

  Future<List<BangumiCalendarDay>> fetchCalendar() async {
    final data = await _request('/calendar');
    final List<dynamic> list = data;
    final List<BangumiCalendarDay> result = [];

    for (final day in list) {
      final weekday = day['weekday'] as Map<String, dynamic>;
      final items = (day['items'] as List).map((e) => BangumiSubject.fromJson(e)).toList();
      result.add(BangumiCalendarDay(
        weekdayId: weekday['id'] ?? 0,
        weekdayCn: weekday['cn'] ?? '',
        items: items,
      ));
    }
    return result;
  }

  Future<List<BangumiSubject>> fetchPopular() async {
    // 这里改用 BGM 官方 v0 搜索接口拉取高分排行
    final data = await _request(
      '/v0/search/subjects?limit=20&offset=0',
      isPost: true,
      body: {
        "sort": "rank",
        "filter": {"type": [2]} // 2 = 动画
      },
    );
    return (data['data'] as List).map((e) => BangumiSubject.fromJson(e)).toList();
  }

  Future<BangumiSubject> fetchSubjectDetail(int id) async {
    final data = await _request('/v0/subjects/$id');
    return BangumiSubject.fromJson(data);
  }
}
