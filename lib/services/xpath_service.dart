import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import '../models/rule.dart';

class XPathService {
  final http.Client _client;

  XPathService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> fetchHtml(String url) async {
    final resp = await _client.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 7.0; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }
    // 显式按 UTF-8 解码，避免部分源返回 GBK 导致乱码
    return resp.bodyBytes.isNotEmpty
        ? String.fromCharCodes(resp.bodyBytes)
        : resp.body;
  }

  Document _parse(String htmlText) =>
      html_parser.parse(htmlText, encoding: 'utf-8');

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    final searchUrl = _buildSearchUrl(rule, keyword);
    final htmlText = await fetchHtml(searchUrl);
    final doc = _parse(htmlText);

    final container = doc.querySelector(rule.searchSelector);
    if (container == null) return [];

    // 容器选择器下，用 animeLinkSelector 匹配每一项
    final items = container.querySelectorAll(rule.animeLinkSelector);
    return items.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href));
    }).where((r) => r.link.isNotEmpty).toList();
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    final htmlText = await fetchHtml(detailUrl);
    final doc = _parse(htmlText);

    final list = doc.querySelectorAll(rule.episodeListSelector);
    return list.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return EpisodeItem(title: title, link: _absolute(rule.baseUrl, href));
    }).where((e) => e.link.isNotEmpty).toList();
  }

  Future<String> resolveEpisodeLink(AnimeRule rule, String episodeUrl) async {
    final htmlText = await fetchHtml(episodeUrl);
    final doc = _parse(htmlText);
    final el = doc.querySelector(rule.episodeLinkSelector);
    if (el == null) return episodeUrl; // 回退到剧集页本身，交给外部处理

    final a = el.localName == 'a' ? el : el.querySelector('a');
    final href = a?.attributes['href'] ?? el.attributes['src'] ?? '';
    if (href.isEmpty) return episodeUrl;
    return _absolute(rule.baseUrl, href);
  }

  String _buildSearchUrl(AnimeRule rule, String keyword) {
    final encoded = Uri.encodeComponent(keyword);
    // v1 简化：baseUrl 可包含 {keyword} 占位符；否则默认追加 ?q=
    if (rule.baseUrl.contains('{keyword}')) {
      return rule.baseUrl.replaceAll('{keyword}', encoded);
    }
    final sep = rule.baseUrl.contains('?') ? '&' : '?';
    return '${rule.baseUrl}$sep q=$encoded'.replaceAll(' ', '');
  }

  String _absolute(String baseUrl, String href) {
    if (href.isEmpty) return '';
    try {
      return Uri.parse(baseUrl).resolve(href).toString();
    } catch (_) {
      return href;
    }
  }

  String _cleanText(String? t) =>
      (t ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
