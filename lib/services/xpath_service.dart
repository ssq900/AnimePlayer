import 'dart:convert';
import 'dart:io'; // 必须引入
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // 用于自定义 HttpClient
import 'package:gbk_codec/gbk_codec.dart';
import '../models/rule.dart';

class XPathService {
  final http.Client _client;

  // 核心黑科技：通过重写 HttpClient，强制使用 DNS over HTTPS (DoH)
  XPathService() : _client = IOClient(_createDohClient());

  static HttpClient _createDohClient() {
    final client = HttpClient();
    
    // 强制使用阿里云的加密 DNS，绕过运营商的 DNS 劫持！
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
      return ConnectionTask<Socket>(() async {
        // 如果使用的是 DoH 地址本身，不做处理
        if (uri.host.contains('223.5.5.5') || uri.host.contains('dns.alidns.com')) {
          return await Socket.connect(uri.host, uri.port);
        }
        
        // 使用阿里云 DoH 解析真实 IP
        final dohClient = HttpClient();
        final req = await dohClient.getUrl(Uri.parse(
            'https://223.5.5.5/resolve?name=${uri.host}&type=A'));
        req.headers.set('accept', 'application/dns-json');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        
        // 解析返回的 JSON，提取真实 IP
        final data = jsonDecode(body);
        if (data['Answer'] != null && (data['Answer'] as List).isNotEmpty) {
          final ip = data['Answer'][0]['data'] as String;
          // 连接到真实的 IP 地址
          return await Socket.connect(ip, uri.port);
        }
        // 如果 DoH 解析失败，退回普通 DNS
        return await Socket.connect(uri.host, uri.port);
      });
    };
    return client;
  }

  Future<String> fetchHtml(String url) async {
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Referer': Uri.parse(url).origin,
    };

    try {
      final resp = await _client.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        throw Exception('HTTP 状态码错误: ${resp.statusCode}');
      }
      
      return _decodeHtml(resp);
    } on SocketException catch (e) {
      throw Exception('DNS解析或连接失败。详情: $e');
    } on HandshakeException catch (_) {
      throw Exception('TLS安全握手失败，目标源站可能不支持当前设备。');
    } catch (e) {
      throw Exception('网络请求异常: $e');
    }
  }

  String _decodeHtml(http.Response resp) {
    final contentType = resp.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('gbk') || contentType.toLowerCase().contains('gb2312')) {
      return gbk.decode(resp.bodyBytes);
    }
    try {
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(resp.bodyBytes);
    }
  }

  Document _parse(String htmlText) => html_parser.parse(htmlText, encoding: 'utf-8');

  Future<List<SearchResult>> search(AnimeRule rule, String keyword) async {
    if (rule.searchSelector.trim().isEmpty) return [];

    final encoded = Uri.encodeComponent(keyword);
    String searchUrl = rule.baseUrl;
    
    if (searchUrl.contains('{keyword}')) {
      searchUrl = searchUrl.replaceAll('{keyword}', encoded);
    } else {
      final sep = searchUrl.contains('?') ? '&' : '?';
      searchUrl = '$searchUrl${sep}wd=$encoded';
    }

    final htmlText = await fetchHtml(searchUrl);
    final doc = _parse(htmlText);

    final container = doc.querySelector(rule.searchSelector);
    if (container == null) {
      // 调试：如果选择器没找到，打印出网页的前 200 个字符，看是不是返回了验证页
      throw Exception("未找到搜索容器。网页内容: ${htmlText.length > 200 ? htmlText.substring(0, 200) : htmlText}");
    }

    final String itemSelector = rule.animeLinkSelector.trim().isEmpty ? '*' : rule.animeLinkSelector;
    final items = (container.localName == 'li' || container.localName == 'a' || container.localName == 'div')
        ? [container] 
        : container.querySelectorAll(itemSelector);
        
    return items.map((el) {
      final anchor = el.localName == 'a' ? el : el.querySelector('a');
      final title = _cleanText(anchor?.attributes['title'] ?? anchor?.text ?? el.text);
      final href = anchor?.attributes['href'] ?? '';
      return SearchResult(title: title, link: _absolute(rule.baseUrl, href));
    }).where((r) => r.link.isNotEmpty && r.title.isNotEmpty).toList();
  }

  Future<List<EpisodeItem>> fetchEpisodes(AnimeRule rule, String detailUrl) async {
    if (rule.episodeListSelector.trim().isEmpty) return [];

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
    if (rule.episodeLinkSelector.trim().isEmpty) return episodeUrl;

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

  String _cleanText(String? t) => (t ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
