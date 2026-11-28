import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/app_failure.dart';
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
        error: (error, _) {
          // 🔥 模式匹配：如果是聚合错误，展示具体的分类面板
          if (error is AggregateFailure) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: error.failures.length,
              itemBuilder: (context, i) {
                final f = error.failures[i];
                return Card(
                  color: Colors.red.withOpacity(0.1),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(f.sourceName ?? '未知源', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(f.message, style: const TextStyle(color: Colors.red)),
                  ),
                );
              },
            );
          }
          // 其他未知错误兜底
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('搜索失败:\n$error', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ),
          );
        },
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
                subtitle: Text(r.rule.name),
                onTap: () {
                  // 接入详情页
                },
              );
            },
          );
        },
      ),
    );
  }
}
