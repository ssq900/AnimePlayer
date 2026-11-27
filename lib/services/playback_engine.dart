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

    _controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: headers);
    
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
    if (_controller!.value.hasError) {
      final err = _controller!.value.errorDescription ?? '未知播放错误';
      _errorController.add(PlaybackError(PlaybackErrorType.network, err));
    }
  }

  // 核心实现：串行化 Seek 队列 (Single-flight)
  Future<void> seek(Duration position) async {
    if (_controller == null || !isInitialized) return;
    _pendingSeek = position;
    
    if (_isSeeking) return; // 如果正在 seek，只更新目标位置，等当前完成会自动接管
    
    _isSeeking = true;
    while (_pendingSeek != null) {
      final target = _pendingSeek!;
      _pendingSeek = null;
      
      try {
        await _controller!.seekTo(target).timeout(const Duration(seconds: 3));
      } catch (e) {
        _errorController.add(PlaybackError(PlaybackErrorType.unknown, 'Seek timeout or failed: $e'));
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
