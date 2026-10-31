import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  final AnimeRule rule;
  const SearchPage({super.key, required this.rule});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _service = XPathService();
  List<SearchResult> _results = [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await _service.search(widget.rule, keyword);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('搜索 · ${widget.rule.name}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '输入番剧名称',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('搜索失败：$_error'),
                  ),
                )
              : _results.isEmpty
                  ? const Center(child: Text('输入关键词开始搜索'))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        return ListTile(
                          title: Text(r.title),
                          subtitle: Text(
                            r.link,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailPage(
                                  rule: widget.rule,
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
