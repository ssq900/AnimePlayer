import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import '../core/exceptions.dart'; // 引入异常类

class RuleEditPage extends StatefulWidget {
  final AnimeRule rule;
  const RuleEditPage({super.key, required this.rule});

  @override
  State<RuleEditPage> createState() => _RuleEditPageState();
}

class _RuleEditPageState extends State<RuleEditPage> {
  final _storage = StorageService();
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _search;
  late final TextEditingController _animeLink;
  late final TextEditingController _episodeList;
  late final TextEditingController _episodeLink;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.rule.name);
    _baseUrl = TextEditingController(text: widget.rule.baseUrl);
    _search = TextEditingController(text: widget.rule.searchSelector);
    _animeLink = TextEditingController(text: widget.rule.animeLinkSelector);
    _episodeList = TextEditingController(text: widget.rule.episodeListSelector);
    _episodeLink = TextEditingController(text: widget.rule.episodeLinkSelector);
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _search.dispose();
    _animeLink.dispose();
    _episodeList.dispose();
    _episodeLink.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rule = AnimeRule(
      id: widget.rule.id,
      name: _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      searchSelector: _search.text.trim(),
      animeLinkSelector: _animeLink.text.trim(),
      episodeListSelector: _episodeList.text.trim(),
      episodeLinkSelector: _episodeLink.text.trim(),
    );

    try {
      // 核心改进：调用模型层进行校验
      rule.validate(); 
      
      final success = await _storage.upsertRule(rule);
      if (success) {
        if (mounted) Navigator.pop(context);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('保存规则失败，请检查磁盘空间'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      // 捕获校验失败或存储异常
      if (mounted) {
        String msg = e is RuleFormatException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule.name.isEmpty ? '新建规则' : '编辑规则'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_name, '规则名称', '例如：示例站'),
          const SizedBox(height: 12),
          _field(
            _baseUrl,
            'Base URL',
            '搜索页 URL，可用 {keyword} 占位；例如 https://example.com/search?q={keyword}',
          ),
          const SizedBox(height: 12),
          _field(
            _search,
            '搜索结果容器选择器',
            'CSS 或 XPath 选择器，例如 .search-result-list 或 //div[@class="list"]',
          ),
          const SizedBox(height: 12),
          _field(
            _animeLink,
            '番剧条目选择器',
            '容器内每个番剧对应的选择器，例如 li.item 或 //li/a',
          ),
          const SizedBox(height: 12),
          _field(
            _episodeList,
            '剧集列表选择器',
            '详情页中剧集条目的选择器，例如 .episode-list a',
          ),
          const SizedBox(height: 12),
          _field(
            _episodeLink,
            '剧集链接选择器',
            '剧集页中视频/播放链接的选择器，例如 video, source, a.play-btn',
          ),
          const SizedBox(height: 24),
          const Text(
            '注意：v2.0 已原生支持 Kazumi 的 XPath 语法。如果你的规则是从社区直接复制的，可以直接粘贴 // 开头的 XPath 代码，系统会自动进行解析。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      maxLines: 2,
    );
  }
}
