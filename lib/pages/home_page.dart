import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
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

  // 语音搜索
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _load();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    // 核心修复：检测设备是否支持语音识别，不支持自动隐藏按钮
    _speechAvailable = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (val) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  void _listen() async {
    if (!_speechAvailable || _isListening) return;
    if (!_speech.isListening) {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (val) {
          setState(() {
            _searchController.text = val.recognizedWords;
          });
        },
        localeId: 'zh_CN',
        onDevice: true, // 优先使用本地离线识别
      );
    } else {
      setState(() => _isListening = false);
      await _speech.stop();
      if (_searchController.text.isNotEmpty) {
        _startSearch();
      }
    }
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

    final rules = await _storage.loadRules();
    if (!mounted) return;
    
    if (rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在“我的”中导入规则')));
      return;
    }

    setState(() {
      _rules = rules;
      _searchController.text = text;
      _isSearching = true;
      _error = null;
      _results = [];
    });
    FocusScope.of(context).unfocus();

    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    history.remove(text);
    history.insert(0, text);
    if (history.length > 10) history.removeLast();
    await prefs.setStringList('search_history', history);
    if (mounted) setState(() => _searchHistory = history);

    const int maxConcurrent = 3;
    int activeTasks = 0;
    int completedTasks = 0;
    final queue = List<AnimeRule>.from(rules);
    
    Future<void> processRule(AnimeRule rule) async {
      try {
        final res = await _xpath.search(rule, text).timeout(
          const Duration(seconds: 15), 
          onTimeout: () => []
        );
        if (res.isNotEmpty && mounted) {
          setState(() => _results.addAll(res));
        }
      } catch (e) {
        debugPrint('搜索源 ${rule.name} 失败: $e');
      }
    }

    while (queue.isNotEmpty || activeTasks > 0) {
      while (activeTasks < maxConcurrent && queue.isNotEmpty) {
        final rule = queue.removeAt(0);
        activeTasks++;
        processRule(rule).then((_) {
          activeTasks--;
          completedTasks++;
          if (completedTasks == rules.length && mounted) {
            setState(() => _isSearching = false);
          }
        });
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    if (mounted) setState(() => _searchHistory = []);
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
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 语音搜索按钮（如果不支持自动隐藏）
                    if (_speechAvailable)
                      IconButton(
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? Colors.red : null,
                        ),
                        onPressed: _listen,
                      ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => _startSearch(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          if (_isSearching) const LinearProgressIndicator(),
          
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

          if (_error != null) Expanded(child: Center(child: Text('搜索失败: $_error'))),

          if (_results.isNotEmpty)
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
            const Expanded(child: Center(child: Text('输入关键词开始搜索吧！', style: TextStyle(color: Colors.grey)))),
        ],
      ),
    );
  }
}
