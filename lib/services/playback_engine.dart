import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

enum PlaybackErrorType { network, codec, unknown }

class PlaybackError {
  final PlaybackErrorType type;
  final String message;
  PlaybackError(this.type, this.message);
}

class PlaybackEngine {
  VideoPlayerController? _controller;
  final _errorController = StreamController<PlaybackError>.broadcast();
  Stream<PlaybackError> get errorStream => _errorController.stream;

  Duration? _pendingSeek;
  bool _isSeeking = false;

  VideoPlayerController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  Future<void> open(String url, {Map<String, String>? headers}) async {
    await dispose();

    // 核心修复：如果 headers 为空，给一个空 Map 防止类型错误
    final safeHeaders = headers ?? <String, String>{};
    _controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: safeHeaders);
    
    _controller!.addListener(_onPlayerValueChanged);
    
    try {
      await _controller!.initialize();
      _controller!.play();
    } catch (e) {
      _errorController.add(PlaybackError(PlaybackErrorType.codec, e.toString()));
      rethrow;
    }
  }

  void _onPlayerValueChanged() {
    if (_controller?.value.hasError == true) {
      final err = _controller!.value.errorDescription ?? '未知播放错误';
      _errorController.add(PlaybackError(PlaybackErrorType.network, err));
    }
  }

  Future<void> seek(Duration position) async {
    if (_controller == null || !isInitialized) return;
    _pendingSeek = position;
    if (_isSeeking) return;
    
    _isSeeking = true;
    while (_pendingSeek != null) {
      final target = _pendingSeek!;
      _pendingSeek = null;
      try {
        await _controller!.seekTo(target).timeout(const Duration(seconds: 3));
      } catch (e) {
        _errorController.add(PlaybackError(PlaybackErrorType.unknown, 'Seek failed: $e'));
        break;
      }
    }
    _isSeeking = false;
  }

  void play() => _controller?.play();
  void pause() => _controller?.pause();
  void setPlaybackSpeed(double speed) => _controller?.setPlaybackSpeed(speed);
  
  Future<void> dispose() async {
    _pendingSeek = null;
    _isSeeking = false;
    _controller?.removeListener(_onPlayerValueChanged);
    await _controller?.dispose();
    _controller = null;
  }
}
