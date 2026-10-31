import 'package:flutter/material.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import 'player_page.dart';

class DetailPage extends StatefulWidget {
  final AnimeRule rule;
  final String detailUrl;
  final String title;

  const DetailPage({
    super.key,
    required this.rule,
    required this.detailUrl,
    required this.title,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _service = XPathService();
  List<EpisodeItem> _episodes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final eps = await _service.fetchEpisodes(widget.rule, widget.detailUrl);
      if (!mounted) return;
      setState(() => _episodes = eps);
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
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败：$_error'))
              : _episodes.isEmpty
                  ? const Center(child: Text('未提取到剧集'))
                  : ListView.builder(
                      itemCount: _episodes.length,
                      itemBuilder: (_, i) {
                        final ep = _episodes[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text('${i + 1}'),
                          ),
                          title: Text(ep.title),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlayerPage(
                                  rule: widget.rule,
                                  episodeUrl: ep.link,
                                  title: ep.title,
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
