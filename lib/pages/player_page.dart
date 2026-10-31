import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';

class PlayerPage extends StatefulWidget {
  final AnimeRule rule;
  final String episodeUrl;
  final String title;

  const PlayerPage({
    super.key,
    required this.rule,
    required this.episodeUrl,
    required this.title,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _xpath = XPathService();
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _resolvedUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final url = await _xpath.resolveEpisodeLink(widget.rule, widget.episodeUrl);
      if (!mounted) return;

      _resolvedUrl = url;

      if (_isDirectVideo(url)) {
        final c = VideoPlayerController.networkUrl(Uri.parse(url));
        await c.initialize();
        
        if (!mounted) {
          await c.dispose();
          return;
        }
        
        setState(() => _controller = c);
        c.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _resolvedUrl = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isDirectVideo(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return path.endsWith('.mp4') ||
          path.endsWith('.m3u8') ||
          path.endsWith('.webm') ||
          path.endsWith('.mkv') ||
          path.endsWith('.flv') ||
          path.endsWith('.ts');
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('解析失败：$_error'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl),
                          child: const Text('用外部浏览器打开'),
                        ),
                      ],
                    ),
                  )
                : _controller != null && _controller!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_new, size: 48),
                          const SizedBox(height: 12),
                          const Text('解析结果为网页，需交给外部应用处理'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl),
                            child: const Text('打开外部页面'),
                          ),
                        ],
                      ),
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    }
  }
}
