import 'package:flutter/material.dart';
import 'package:xml/xml.dart'; // ⚠️ 新增：需要用到 XmlText
import '../services/xpath_service.dart';

class DebuggerPage extends StatefulWidget {
  const DebuggerPage({super.key});

  @override
  State<DebuggerPage> createState() => _DebuggerPageState();
}

class _DebuggerPageState extends State<DebuggerPage> {
  final _urlController = TextEditingController();
  final _xpathController = TextEditingController();
  final _xpathService = XPathService();

  bool _isLoading = false;
  String? _error;
  List<String> _matchedResults = [];
  int _totalMatched = 0;

  @override
  void dispose() {
    _urlController.dispose();
    _xpathController.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    final url = _urlController.text.trim();
    final xpath = _xpathController.text.trim();

    if (url.isEmpty || xpath.isEmpty) {
      setState(() => _error = '请输入 URL 和 XPath 表达式');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _matchedResults.clear();
      _totalMatched = 0;
    });

    try {
      final html = await _xpathService.fetchHtml(url);
      final doc = _xpathService.parseHtml(html);
      final elements = _xpathService.findElements(doc, xpath);

      setState(() {
        _totalMatched = elements.length;
        _matchedResults = elements.take(10).map((e) {
          // ⚠️ 修复：使用安全的方式获取节点内的纯文本
          final text = e.descendants.whereType<XmlText>().map((n) => n.value).join().trim().replaceAll('\n', ' ');
          final href = e.getAttribute('href')?.trim() ?? '无 href 属性';
          final shortText = text.length > 30 ? '${text.substring(0, 30)}...' : text;
          return '文本: $shortText\n链接: $href';
        }).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('规则调试器')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '目标网页 URL',
                hintText: 'https://example.com/search?q={keyword}',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _xpathController,
              decoration: const InputDecoration(
                labelText: 'XPath 表达式',
                hintText: '//div[@class="list"]//a',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _runTest,
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_isLoading ? '正在抓取并解析...' : '开始测试'),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('❌ 测试失败:\n$_error', style: const TextStyle(color: Colors.red)),
              ),
            if (_totalMatched > 0) ...[
              Text(
                '✅ 匹配成功！共找到 $_totalMatched 个节点（仅展示前 10 个）',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _matchedResults.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey.withOpacity(0.1),
                    child: Text('节点 ${index + 1}:\n${_matchedResults[index]}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  );
                },
              ),
            ] else if (!_isLoading && _error == null && _urlController.text.isNotEmpty) ...[
              const Text('⚠️ 没有匹配到任何节点，请检查 XPath 是否正确', style: TextStyle(color: Colors.orange)),
            ]
          ],
        ),
      ),
    );
  }
}
