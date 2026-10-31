import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:gbk_codec/gbk_codec.dart'; // 处理老网站 GBK 编码
import '../models/rule.dart';

class XPathService {
  final http.Client _client;

  XPathService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> fetchHtml(String url) async {
    // 终极伪装：加上 Referer 和 Sec-Fetch 等头部，骗过大部分防盗链
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Referer': Uri.parse(url).origin, // 告诉服务器我是从你们自己主页点过来的
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'same-origin',
      'Upgrade-Insecure-Requests': '1',
    };

    try {
      final resp = await _client.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      
      return _decodeHtml(resp);
    } catch (e) {
      throw Exception('网络请求失败，可能被墙或目标网站拦截。\n详情: $e');
    }
  }

  // 核心黑科技：自动探测网页编码（解决老网站乱码问题）
  String _decodeHtml(http.Response resp) {
    // 尝试从响应头获取编码
    final contentType = resp.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('gbk') || contentType.toLowerCase().contains('gb2312')) {
      return gbk.decode(resp.bodyBytes);
    }

    // 尝试用 UTF-8 解码
    try {
      final utf8Str = String.fromCharCodes(resp.bodyBytes);
      // 如果解码出来的乱码很多，说明不是 UTF-8
      final head = utf8Str.length > 1000 ? utf8Str.substring(0, 1000) : utf8Str;
      if (head.contains('charset="gbk"') || head.contains("charset='gbk'") || head.contains('charset=gb2312')) {
        return gbk.decode(resp.bodyBytes);
      }
      return utf8Str;
    } catch (_) {
      // 默认强行按 UTF-8 处理
      return String.fromCharCodes(resp.bodyBytes);
    }
  }

  Document _parse(String htmlText) =>
      html_parser.parse(htmlText, encoding: 'utf-8');

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    
    // 处理 URL 拼接
    if (searchUrl.contains('{keyword}')) {
      searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    } else {
      final sep = searchUrl.contains('?') ? '&' : '?';
      searchUrl = '$searchUrl${sep}wd=$encoded';
    }

    final htmlText = await fetchHtml(searchUrl);
    final doc = _parse(htmlText);

    final container = doc.querySelector(rule.searchSelector);
    if (container == null) return [];

    final items = (container.localName == 'li' || container.localName == 'a' || container.localName == 'div')
        ? [container] 
        : container.querySelectorAll(rule.animeLinkSelector);
        
    return items.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.attributes['title'] ?? anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href));
    }).where((r) => r.link.isNotEmpty && r.title.isNotEmpty).toList();
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
    if (el == null) return episodeUrl;

    final a = el.localName == 'a' ? el : el.querySelector('a');
    final href = a?.attributes['href'] ?? el.attributes['src'] ?? '';
    if (href.isEmpty) return episodeUrl;
    return _absolute(rule.baseUrl, href);
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
