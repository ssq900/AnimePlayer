import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import '../domain/selector_engine.dart';

// 枚举：分步测试的阶段
enum DebugStep { search, episodes, media }

class DebuggerPage extends StatefulWidget {
  const DebuggerPage({super.key});

  @override
  State<DebuggerPage> createState() => _DebuggerPageState();
}

class _DebuggerPageState extends State<DebuggerPage> {
  final _engine = SelectorEngine();
  
  // 输入控制器
  final _urlController = TextEditingController();
  final _selectorController = TextEditingController();
  final _keywordController = TextEditingController();

  DebugStep _currentStep = DebugStep.search;
  bool _isLoading = false;
  String? _error;
  
  // 存储解析出来的结果字符串，用于 UI 展示
  List<String> _parsedResults = [];

  @override
  void dispose() {
    _urlController.dispose();
    _selectorController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  // 根据当前步骤更新 UI 提示
  String get _urlHint {
    switch (_currentStep) {
      case DebugStep.search: return '输入搜索页 URL（支持 {keyword}）';
      case DebugStep.episodes: return '输入番剧详情页 URL';
      case DebugStep.media: return '输入剧集播放页 URL';
    }
  }

  String get _selectorHint {
    switch (_currentStep) {
      case DebugStep.search: return '例如: //div[@class="list"]//a';
      case DebugStep.episodes: return '例如: //ul[@id="play-list"]//a';
      case DebugStep.media: return '例如: //video/@src 或 //iframe';
    }
  }

  Future<void> _runStepTest() async {
    String url = _urlController.text.trim();
    final selector = _selectorController.text.trim();
    final keyword = _keywordController.text.trim();

    if (url.isEmpty || selector.isEmpty) {
      setState(() => _error = '请填写 URL 和选择器');
      return;
    }

    // 如果 URL 包含 {keyword}，替换它
    if (url.contains('{keyword}')) {
      if (keyword.isEmpty) {
        setState(() => _error = 'URL 中包含 {keyword}，请在下方输入关键词');
        return;
      }
      url = url.replaceAll('{keyword}', Uri.encodeComponent(keyword));
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _parsedResults.clear();
    });

    try {
      // 1. 抓取 HTML (自带 HTTP 优先，WebView 兜底)
      final html = await _engine.fetchHtml(url);
      
      // 2. 解析为 XML Document
      final doc = _engine.parseHtml(html);
      
      // 3. 执行 XPath 查询
      final elements = _engine.findElements(doc, selector);

      if (elements.isEmpty) {
        setState(() => _error = '⚠️ 没有匹配到任何节点，请检查 XPath');
      } else {
        // 4. 提取结果展示
        final results = elements.take(15).map((e) {
          final text = e.descendants.whereType<XmlText>().map((n) => n.value).join().trim().replaceAll(RegExp(r'\s+'), ' ');
          final href = e.getAttribute('href') ?? e.getAttribute('src') ?? '无链接属性';
          final shortText = text.length > 40 ? '${text.substring(0, 40)}...' : text;
          return '文本: $shortText\n链接: $href';
        }).toList();

        setState(() {
          _parsedResults = ['✅ 共命中 ${elements.length} 个节点，展示前 ${results.length} 个：\n', ...results];
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('规则分步调试器')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // === 步骤切换器 ===
            SegmentedButton<DebugStep>(
              segments: const [
                ButtonSegment(value: DebugStep.search, label: Text('1. 搜索页')),
                ButtonSegment(value: DebugStep.episodes, label: Text('2. 剧集列表')),
                ButtonSegment(value: DebugStep.media, label: Text('3. 播放流')),
              ],
              selected: {_currentStep},
              onSelectionChanged: (Set<DebugStep> newSelection) {
                setState(() {
                  _currentStep = newSelection.first;
                  _parsedResults.clear();
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 20),

            // === URL 输入 ===
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '目标网页 URL',
                hintText: _urlHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // 如果 URL 需要 keyword，显示关键词输入框
            if (_urlController.text.contains('{keyword}')) ...[
              TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  labelText: '搜索关键词',
                  hintText: '例如：久留美',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // === 选择器输入 ===
            TextField(
              controller: _selectorController,
              decoration: InputDecoration(
                labelText: 'XPath 表达式',
                hintText: _selectorHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _runStepTest,
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_isLoading ? '正在抓取并解析...' : '测试当前环节'),
            ),
            const SizedBox(height: 24),

            // === 错误展示 ===
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('❌ 测试结果:\n$_error', style: const TextStyle(color: Colors.red)),
              ),

            // === 结果展示 ===
            if (_parsedResults.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _parsedResults.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final isTitle = index == 0;
                  return Container(
                    padding: const EdgeInsets.all(8),
                    color: isTitle ? Colors.transparent : Colors.grey.withOpacity(0.1),
                    child: Text(
                      _parsedResults[index],
                      style: TextStyle(
                        fontFamily: isTitle ? null : 'monospace',
                        fontSize: isTitle ? 16 : 13,
                        fontWeight: isTitle ? FontWeight.bold : null,
                        color: isTitle ? Colors.green : null,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
