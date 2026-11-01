import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';

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
    if (rule.baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('baseUrl 不能为空')),
      );
      return;
    }
    
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
            'CSS selector，例如 .search-result-list',
          ),
          const SizedBox(height: 12),
          _field(
            _animeLink,
            '番剧条目选择器',
            '容器内每个番剧对应的 CSS selector，例如 li.item',
          ),
          const SizedBox(height: 12),
          _field(
            _episodeList,
            '剧集列表选择器',
            '详情页中剧集条目的 CSS selector，例如 .episode-list a',
          ),
          const SizedBox(height: 12),
          _field(
            _episodeLink,
            '剧集链接选择器',
            '剧集页中视频/播放链接的 CSS selector，例如 video, source, a.play-btn',
          ),
          const SizedBox(height: 24),
          const Text(
            '注意：v1 使用 CSS selector（非完整 XPath）。从 Kazumi 迁移规则时，'
            '请将 //div[@class="x"] 这类写法转换为 .x。',
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
