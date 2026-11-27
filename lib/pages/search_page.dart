import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/search/search_provider.dart';
import '../models/rule.dart';

class SearchPage extends ConsumerStatefulWidget {
  final List<AnimeRule> rules;
  const SearchPage({super.key, required this.rules});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    ref.read(searchProvider.notifier).search(keyword, widget.rules);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: '输入番剧名称...',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _onSearch(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _onSearch),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('搜索失败:\n$err', style: const TextStyle(color: Colors.red)),
        ),
        data: (results) {
          if (results.isEmpty) {
            return const Center(child: Text('暂无结果'));
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final r = results[i];
              return ListTile(
                title: Text(r.title),
                subtitle: Text(r.rule.name), // 适配真实的 rule 字段
                onTap: () {
                  // 这里保留你的跳转逻辑
                },
              );
            },
          );
        },
      ),
    );
  }
}
