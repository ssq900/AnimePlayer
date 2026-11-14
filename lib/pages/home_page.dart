import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import '../services/xpath_service.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _storage = StorageService();
  final _xpath = XPathService();
  final _searchController = TextEditingController();
  
  List<AnimeRule> _rules = [];
  List<String> _searchHistory = [];
  List<SearchResult> _results = [];
  
  bool _isSearching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.loadRules();
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _searchHistory = history;
    });
  }

  Future<void> _startSearch([String? keyword]) async {
    final text = keyword ?? _searchController.text.trim();
    if (text.isEmpty) return;
    if (_rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在“我的”中导入规则')));
      return;
    }

    _searchController.text = text;
    FocusScope.of(context).unfocus();

    // 保存搜索历史
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    history.remove(text);
    history.insert(0, text);
    if (history.length > 10) history.removeLast();
    await prefs.setStringList('search_history', history);
    setState(() => _searchHistory = history);

    setState(() {
      _isSearching = true;
      _error = null;
      _results = [];
    });

    // 串行多源搜索
    for (final rule in _rules) {
      try {
        final res = await _xpath.search(rule, text);
        if (res.isNotEmpty && mounted) {
          setState(() => _results.addAll(res));
        }
      } catch (e) {
        debugPrint('搜索源 ${rule.name} 失败: $e');
      }
    }

    if (mounted) setState(() => _isSearching = false);
  }

  void _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    setState(() => _searchHistory = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全网聚合搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _startSearch(),
              decoration: InputDecoration(
                hintText: '输入番剧名称，即刻全网搜',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _startSearch(),
                ),
              ),
            ),
          ),
          
          if (_searchHistory.isNotEmpty && _results.isEmpty && !_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('搜索历史', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const Spacer(),
                  TextButton(onPressed: _clearHistory, child: const Text('清空', style: TextStyle(fontSize: 12))),
                ],
              ),
            ),
          if (_searchHistory.isNotEmpty && _results.isEmpty && !_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _searchHistory.map((h) => ActionChip(
                  label: Text(h),
                  onPressed: () => _startSearch(h),
                )).toList(),
              ),
            ),

          if (_isSearching)
            const Expanded(child: Center(child: CircularProgressIndicator())),
            
          if (_error != null)
            Expanded(child: Center(child: Text('搜索失败: $_error'))),

          if (!_isSearching && _results.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _results[i];
                  return ListTile(
                    title: Text(r.title),
                    subtitle: Text('${r.rule.name} · ${r.link}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailPage(rule: r.rule, detailUrl: r.link, title: r.title),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
          if (!_isSearching && _results.isEmpty && _error == null && _searchHistory.isEmpty)
            const Expanded(
              child: Center(child: Text('输入关键词开始搜索吧！', style: TextStyle(color: Colors.grey))),
            ),
        ],
      ),
    );
  }
}
