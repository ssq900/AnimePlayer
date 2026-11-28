import '../models/rule.dart';

class RuleMigrator {
  /// 核心方法：将单个旧规则平滑迁移为支持 CSS 的新规则
  static AnimeRule migrateToCss(AnimeRule oldRule) {
    if (oldRule.isCssBased) return oldRule; // 已经是 CSS 则不处理

    return oldRule.copyWith(
      searchSelectorCss: _xpathToCss(oldRule.searchSelector),
      animeLinkSelectorCss: _xpathToCss(oldRule.animeLinkSelector),
      episodeListSelectorCss: _xpathToCss(oldRule.episodeListSelector),
      episodeLinkSelectorCss: _xpathToCss(oldRule.episodeLinkSelector),
      // 如果转换成功，设置为 true，下次搜索直接走极速的 CSS 引擎
      isCssBased: true, 
    );
  }

  /// 批量迁移
  static List<AnimeRule> migrateAll(List<AnimeRule> rules) {
    return rules.map((r) => migrateToCss(r)).toList();
  }

  /// 简易 XPath 转 CSS 引擎
  static String _xpathToCss(String xpath) {
    if (xpath.trim().isEmpty) return '';

    String css = xpath.trim();

    // 1. 移除前缀 //
    if (css.startsWith('//')) css = css.substring(2);
    if (css.startsWith('/')) css = css.substring(1);

    // 2. 替换包含谓词 [contains(@class, 'xxx')]
    // 变成 .xxx
    css = css.replaceAllMapped(
      RegExp(r"\[contains\(@class,\s*['""]([^'""]+)['""]\)\]"),
      (match) {
        final classes = match.group(1)!.trim().split(RegExp(r'\s+'));
        return classes.map((c) => '.$c').join('');
      },
    );

    // 3. 替换严格谓词 [@class='xxx']
    // 变成 .xxx
    css = css.replaceAllMapped(
      RegExp(r"\[@class\s*=\s*['""]([^'""]+)['""]\]"),
      (match) => '.${match.group(1)!.trim().replaceAll(' ', '.')}',
    );

    // 4. 替换 ID 谓词 [@id='xxx']
    // 变成 #xxx
    css = css.replaceAllMapped(
      RegExp(r"\[@id\s*=\s*['""]([^'""]+)['""]\]"),
      (match) => '#${match.group(1)!.trim()}',
    );

    // 5. 替换层级分隔符 / 为空格（CSS 后代选择器）
    css = css.replaceAll('/', ' ');

    // 6. 清理多余空格
    css = css.replaceAll(RegExp(r'\s+'), ' ').trim();

    return css;
  }
}
