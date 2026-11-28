import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GestureMode { brightness, volume, seek }

class PlaybackState {
  final VideoPlayerController? controller;
  final bool isInitialized;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double playbackSpeed;
  final GestureMode gestureMode;
  final double brightness;
  final double volume;

  const PlaybackState({
    this.controller,
    this.isInitialized = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.playbackSpeed = 1.0,
    this.gestureMode = GestureMode.seek,
    this.brightness = 1.0,
    this.volume = 1.0,
  });

  PlaybackState copyWith({
    VideoPlayerController? controller,
    bool? isInitialized,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    double? playbackSpeed,
    GestureMode? gestureMode,
    double? brightness,
    double? volume,
  }) {
    return PlaybackState(
      controller: controller ?? this.controller,
      isInitialized: isInitialized ?? this.isInitialized,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      gestureMode: gestureMode ?? this.gestureMode,
      brightness: brightness ?? this.brightness,
      volume: volume ?? this.volume,
    );
  }
}

final playbackControllerProvider = NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState> {
  int _lastSavedPositionMs = 0;
  String _currentUrl = '';

  @override
  PlaybackState build() {
    ref.onDispose(() {
      // 退出页面时，如果没播完，顺便保存一下最终进度
      _saveProgress(force: true);
      state.controller?.dispose();
    });
    return const PlaybackState();
  }

  Future<void> initialize(String url) async {
    state.controller?.dispose();
    _currentUrl = url;
    _lastSavedPositionMs = 0;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    state = state.copyWith(controller: controller, isInitialized: false);
    
    await controller.initialize();
    
    // ⚠️ 恢复断点进度
    final prefs = await SharedPreferences.getInstance();
    final savedMs = prefs.getInt('progress_$url') ?? 0;
    if (savedMs > 0 && savedMs < controller.value.duration.inMilliseconds) {
      await controller.seekTo(Duration(milliseconds: savedMs));
      _lastSavedPositionMs = savedMs;
    }

    controller.addListener(_onTick);
    state = state.copyWith(
      isInitialized: true,
      duration: controller.value.duration,
    );
    
    await controller.play();
    state = state.copyWith(isPlaying: true);
  }

  void _onTick() {
    final c = state.controller;
    if (c == null) return;

    state = state.copyWith(
      position: c.value.position,
      duration: c.value.duration,
      isPlaying: c.value.isPlaying,
      playbackSpeed: c.value.playbackSpeed,
    );

    // ⚠️ 保存断点进度（节流策略：每跨越 5 秒保存一次）
    final currentMs = c.value.position.inMilliseconds;
    if ((currentMs - _lastSavedPositionMs).abs() >= 5000) {
      _saveProgress();
    }
  }

  Future<void> _saveProgress({bool force = false}) async {
    final c = state.controller;
    if (c == null || _currentUrl.isEmpty) return;
    
    final currentMs = c.value.position.inMilliseconds;
    final durationMs = c.value.duration.inMilliseconds;
    
    // 如果距离上次保存不足 5 秒，且不是强制保存，直接跳过
    if (!force && (currentMs - _lastSavedPositionMs).abs() < 5000) return;
    
    _lastSavedPositionMs = currentMs;
    final prefs = await SharedPreferences.getInstance();
    
    // 如果播放完毕（距离结尾不到 2 秒），清除进度记录，下次从头播放
    if (durationMs > 0 && (durationMs - currentMs) < 2000) {
      await prefs.remove('progress_$_currentUrl');
    } else {
      await prefs.setInt('progress_$_currentUrl', currentMs);
    }
  }

  void updateGestureMode(GestureMode mode) {
    state = state.copyWith(gestureMode: mode);
  }

  void setBrightness(double v) {
    state = state.copyWith(brightness: v.clamp(0.0, 1.0));
  }

  void setVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    state.controller?.setVolume(clamped);
  }
}
