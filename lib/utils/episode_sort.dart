class EpisodeSort {
  final int? episodeNumber; // 集号（如 1, 2, 3），如果是剧场版或无法识别则为 null
  final String rawTitle;    // 原始标题

  EpisodeSort({this.episodeNumber, required this.rawTitle});

  // 核心提取算法：从复杂的标题中提取真实的集数
  static EpisodeSort parse(String title) {
    // 去除空格，转小写方便匹配
    final cleanTitle = title.trim().toLowerCase();
    
    // 匹配常见的 "第01集"、"第1话"、"EP01" 等
    final reg = RegExp(r'第?\s*(\d+)\s*[集话回]|ep?\s*(\d+)');
    final match = reg.firstMatch(cleanTitle);
    
    if (match != null) {
      final numStr = match.group(1) ?? match.group(2);
      if (numStr != null) {
        return EpisodeSort(episodeNumber: int.tryParse(numStr), rawTitle: title);
      }
    }

    // 匹配纯数字（如 "01", "12"）
    final pureNumReg = RegExp(r'^\d+$');
    if (pureNumReg.hasMatch(cleanTitle)) {
      return EpisodeSort(episodeNumber: int.tryParse(cleanTitle), rawTitle: title);
    }

    // 匹配小数集数（如 "12.5"）
    final floatReg = RegExp(r'(\d+\.\d+)');
    final floatMatch = floatReg.firstMatch(cleanTitle);
    if (floatMatch != null) {
      return EpisodeSort(episodeNumber: (double.tryParse(floatMatch.group(1)!) ?? 0 * 1000).toInt(), rawTitle: title);
    }

    // 无法识别的（如 "剧场版"、"HD中字"）
    return EpisodeSort(episodeNumber: null, rawTitle: title);
  }

  // 比较两个剧集是否匹配（用于一键换源）
  bool matches(EpisodeSort other) {
    if (episodeNumber == null || other.episodeNumber == null) {
      // 如果都没有集号，退化为标题模糊匹配
      return rawTitle.contains(other.rawTitle) || other.rawTitle.contains(rawTitle);
    }
    return episodeNumber == other.episodeNumber;
  }
}
