import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/storage_service.dart';
import 'settings_page.dart'; // 🔥 引入设置页以便跳转
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _storage = StorageService();
  final _searchController = TextEditingController();
  
  List<AnimeRule> _rules = [];
  List<HistoryItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final rules = await _storage.loadRules();
    final history = await _storage.loadHistory();
    
    if (mounted) {
      setState(() {
        _rules = rules;
        _history = history;
        _isLoading = false;
      });
    }
  }

  void _startSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    // 🔥 核心修改：规则为空时的引导跳转
    if (_rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先导入规则才能搜索'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ).then((_) => _loadData()); // 从设置页返回后自动刷新规则列表
            },
          ),
        ),
      );
      return;
    }

    // 跳转到搜索页
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(keyword: keyword, rules: _rules),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('全网聚合搜索'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ).then((_) => _loadData());
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 搜索框
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '输入番剧名称...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _startSearch,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _startSearch(),
            ),
            
            const SizedBox(height: 24),
            
            // 规则为空时的提示
            if (_rules.isEmpty)
              Card(
                color: Colors.orange.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: const Text('暂无可用规则'),
                  subtitle: const Text('请前往设置导入规则后才能进行搜索'),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ).then((_) => _loadData());
                    },
                    child: const Text('去设置'),
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // 搜索历史
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('搜索历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (_history.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      // 这里需要你根据 StorageService 补全清空历史的方法
                      // await _storage.clearHistory();
                      // _loadData();
                    },
                    child: const Text('清空', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Expanded(
              child: _history.isEmpty
                  ? const Center(
                      child: Text('暂无搜索历史', style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(item.animeTitle),
                          subtitle: Text(item.episodeTitle),
                          onTap: () {
                            _searchController.text = item.animeTitle;
                            _startSearch();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
