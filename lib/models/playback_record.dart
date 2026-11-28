import '../utils/episode_sort.dart';

class PlaybackRecord {
  final String animeTitle;     // 规范化番剧名
  final String episodeTitle;   // 剧集名
  final int? episodeSort;      // 解析出的集号（用于精准匹配）
  final String url;            // 剧集播放URL（作为唯一主键去重）
  final String ruleId;         // 来源规则ID
  final int progress;          // 播放进度（毫秒）
  final int duration;          // 总时长（毫秒）
  final int lastUpdated;       // 最后更新时间戳

  PlaybackRecord({
    required this.animeTitle,
    required this.episodeTitle,
    required this.episodeSort,
    required this.url,
    required this.ruleId,
    required this.progress,
    required this.duration,
    required this.lastUpdated,
  });

  // 获取格式化后的进度字符串
  String get formattedProgress {
    final p = Duration(milliseconds: progress);
    final d = Duration(milliseconds: duration);
    return '${_formatDuration(p)} / ${_formatDuration(d)}';
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Map<String, dynamic> toJson() => {
        'animeTitle': animeTitle,
        'episodeTitle': episodeTitle,
        'episodeSort': episodeSort,
        'url': url,
        'ruleId': ruleId,
        'progress': progress,
        'duration': duration,
        'lastUpdated': lastUpdated,
      };

  factory PlaybackRecord.fromJson(Map<String, dynamic> j) {
    return PlaybackRecord(
      animeTitle: j['animeTitle'] ?? '',
      episodeTitle: j['episodeTitle'] ?? '',
      episodeSort: j['episodeSort'],
      url: j['url'] ?? '',
      ruleId: j['ruleId'] ?? '',
      progress: j['progress'] ?? 0,
      duration: j['duration'] ?? 0,
      lastUpdated: j['lastUpdated'] ?? 0,
    );
  }
}
