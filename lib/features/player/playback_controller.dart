import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../services/storage_service.dart';
import '../../models/playback_record.dart';
import '../../utils/episode_sort.dart';

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
  final _storage = StorageService();
  Timer? _saveTimer;
  
  // 记录当前播放的上下文（用于存库）
  String _currentUrl = '';
  String _animeTitle = '';
  String _episodeTitle = '';
  String _ruleId = '';

  @override
  PlaybackState build() {
    ref.onDispose(() {
      state.controller?.dispose();
      _saveTimer?.cancel();
    });
    return const PlaybackState();
  }

  Future<void> initialize(String url, {String animeTitle = '未知番剧', String episodeTitle = '未知剧集', String ruleId = ''}) async {
    _currentUrl = url;
    _animeTitle = animeTitle;
    _episodeTitle = episodeTitle;
    _ruleId = ruleId;

    state.controller?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    state = state.copyWith(controller: controller, isInitialized: false);
    await controller.initialize();

    // 🔥 断点续播：从本地读取上次播放进度
    final record = await _storage.getPlaybackRecord(url);
    if (record != null && record.progress > 0) {
      await controller.seekTo(Duration(milliseconds: record.progress));
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

    // 🔥 节流保存：每 5 秒触发一次写库
    if (c.value.isPlaying) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 5), _saveProgressToLocal);
    }
  }

  Future<void> _saveProgressToLocal() async {
    final c = state.controller;
    if (c == null || !c.value.isInitialized || _currentUrl.isEmpty) return;

    final record = PlaybackRecord(
      animeTitle: _animeTitle,
      episodeTitle: _episodeTitle,
      episodeSort: EpisodeSort.parse(_episodeTitle).episodeNumber,
      url: _currentUrl,
      ruleId: _ruleId,
      progress: c.value.position.inMilliseconds,
      duration: c.value.duration.inMilliseconds,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );

    await _storage.upsertPlaybackRecord(record);
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
