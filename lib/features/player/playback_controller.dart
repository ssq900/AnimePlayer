import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

enum GestureMode { brightness, volume, seek }

class PlaybackState {
  final VideoPlayerController? controller;
  final bool isInitialized;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final GestureMode gestureMode;
  final double brightness;
  final double volume;

  const PlaybackState({
    this.controller,
    this.isInitialized = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
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
      gestureMode: gestureMode ?? this.gestureMode,
      brightness: brightness ?? this.brightness,
      volume: volume ?? this.volume,
    );
  }
}

final playbackControllerProvider = NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() {
    ref.onDispose(() {
      state.controller?.dispose();
    });
    return const PlaybackState();
  }

  Future<void> initialize(String url) async {
    state.controller?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    state = state.copyWith(controller: controller, isInitialized: false);
    await controller.initialize();
    controller.addListener(_onTick);
    state = state.copyWith(isInitialized: true, duration: controller.value.duration);
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
    );
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
