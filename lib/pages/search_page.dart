import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  final List<AnimeRule> rules;
  const SearchPage({super.key, required this.rules});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _service = XPathService();
  
  List<SearchResult> _results = [];
  bool _searching = false;
  int _completedCount = 0;
  String? _currentSearchKeyword;

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    
    setState(() {
      _searching = true;
      _results = [];
      _completedCount = 0;
      _currentSearchKeyword = keyword;
    });

    // 串行搜索每一个源，防止 WebView 并发过多导致内存溢出闪退
    for (final rule in widget.rules) {
      if (!mounted || _currentSearchKeyword != keyword) break; // 如果用户中途发起了新搜索，中断旧搜索
      
      try {
        final res = await _service.search(rule, keyword);
        if (res.isNotEmpty && mounted && _currentSearchKeyword == keyword) {
          setState(() {
            _results.addAll(res);
          });
        }
      } catch (e) {
        // 忽略单个源的报错，继续搜下一个
        debugPrint("源 ${rule.name} 搜索失败: $e");
      } finally {
        if (mounted) {
          setState(() {
            _completedCount++;
          });
        }
      }
    }

    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('聚合搜索 (${_completedCount}/${widget.rules.length})'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '输入番剧名称（将搜索所有源）',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                filled: true,
              ),
            ),
          ),
        ),
      ),
      body: _searching && _results.isEmpty
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在多源聚合搜索中，请稍候...'),
              ],
            ))
          : _results.isEmpty && !_searching
              ? const Center(child: Text('没有搜到相关结果，请尝试更换关键词'))
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    return ListTile(
                      title: Text(r.title),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(r.rule.name, style: const TextStyle(fontSize: 12, color: Colors.deepPurple)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.link,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailPage(
                              rule: r.rule, // 精准传递这条结果对应的规则
                              detailUrl: r.link,
                              title: r.title,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
