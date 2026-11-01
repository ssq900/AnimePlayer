import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/xpath_service.dart';

class DebuggerPage extends StatefulWidget {
  const DebuggerPage({super.key});

  @override
  State<DebuggerPage> createState() => _DebuggerPageState();
}

class _DebuggerPageState extends State<DebuggerPage> {
  final _urlController = TextEditingController();
  final _selectorController = TextEditingController();
  final _xpathService = XPathService();

  bool _loading = false;
  String? _error;
  int _matchCount = 0;
  String _firstItemText = '';
  String _htmlPreview = '';

  Future<void> _test() async {
    String url = _urlController.text.trim();
    final selector = _selectorController.text.trim();

    if (url.isEmpty || selector.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 URL 和 选择器')),
      );
      return;
    }

    // 核心修复：自动对 URL 里的中文进行 URL 编码
    try {
      url = Uri.parse(url).toString();
    } catch (_) {
      // 忽略解析异常，使用原样
    }

    setState(() {
      _loading = true;
      _error = null;
      _matchCount = 0;
      _firstItemText = '';
      _htmlPreview = '';
    });

    try {
      final htmlText = await _xpathService.fetchHtml(url);
      final doc = html_parser.parse(htmlText, encoding: 'utf-8');
      final elements = doc.querySelectorAll(selector);

      if (elements.isEmpty) {
        setState(() {
          _error = '未匹配到任何元素。请检查选择器是否正确，或该网页是否需要动态渲染。';
          _htmlPreview = htmlText.length > 500 ? htmlText.substring(0, 500) : htmlText;
        });
      } else {
        final firstEl = elements.first;
        String title = firstEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final href = firstEl.attributes['href'] ?? '无链接属性';
        final src = firstEl.attributes['src'] ?? '';

        setState(() {
          _matchCount = elements.length;
          _firstItemText = '文本: $title\n'
              '链接: $href\n'
              '${src.isNotEmpty ? '资源: $src\n' : ''}'
              'HTML 预览: ${firstEl.outerHtml.length > 200 ? firstEl.outerHtml.substring(0, 200) : firstEl.outerHtml}';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _selectorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('规则调试器')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '目标 URL',
              hintText: '例如：https://example.com/search?wd=测试',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _selectorController,
            decoration: const InputDecoration(
              labelText: 'CSS 选择器',
              hintText: '例如：.module-item 或 ul > li > a',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _test,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始抓取并测试'),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            )
          else if (_matchCount > 0)
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✅ 成功匹配到 $_matchCount 个节点',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    const Text('【第一个节点提取结果】', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_firstItemText),
                  ],
                ),
              ),
            ),
          if (_htmlPreview.isNotEmpty && _matchCount == 0) ...[
            const SizedBox(height: 16),
            const Text('【网页源码预览（前 500 字）】', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade200,
              child: SelectableText(
                _htmlPreview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
