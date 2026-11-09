import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

enum Sfx {
  turn,
  align,
  free,
  peg,
  tray,
  win,
  blocked,
  tap,
  coin,
  star,
  fail,
  hint,
  undo,
  unseal,
  unlock,
}

/// How much of each music layer plays. The layers are three loops of
/// different lengths with no fixed beat, so they never need to be in sync.
enum MusicMood {
  off(0, 0, 0),
  menu(0.55, 0.30, 0),
  levelStart(0.50, 0, 0),
  levelFlow(0.50, 0.38, 0),
  levelClose(0.50, 0.38, 0.32);

  const MusicMood(this.pad, this.mallets, this.shimmer);
  final double pad;
  final double mallets;
  final double shimmer;
}

/// Pitch steps of the C major pentatonic scale, used to raise the "ring
/// freed" chime for each ring released in a row.
const List<double> kPentatonic = [1, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2];

abstract class AudioService {
  Future<void> init();

  /// Plays an effect. [pitch] is a speed multiplier (1 = as recorded).
  void play(Sfx sfx, {double pitch = 1, double volume = 1, double pan = 0});

  void setMood(MusicMood mood);

  /// Lowers the music briefly so a sting can be heard.
  void duck(Duration time);

  bool get musicOn;
  set musicOn(bool value);
  bool get soundOn;
  set soundOn(bool value);

  /// Silences everything, for ads and when the app is in the background.
  void suspend();
  void resume();
  Future<void> dispose();
}

/// Used in tests, and if the audio engine fails to start.
class SilentAudio implements AudioService {
  final List<Sfx> played = [];
  MusicMood mood = MusicMood.off;

  @override
  bool musicOn = true;
  @override
  bool soundOn = true;

  @override
  Future<void> init() async {}
  @override
  void play(Sfx sfx, {double pitch = 1, double volume = 1, double pan = 0}) =>
      played.add(sfx);
  @override
  void setMood(MusicMood mood) => this.mood = mood;
  @override
  void duck(Duration time) {}
  @override
  void suspend() {}
  @override
  void resume() {}
  @override
  Future<void> dispose() async {}
}

/// Audio through the SoLoud engine (package:flutter_soloud).
class SoloudAudio implements AudioService {
  final SoLoud _engine = SoLoud.instance;
  final Random _rng = Random();
  final Map<Sfx, List<AudioSource>> _sources = {};
  final List<SoundHandle?> _layers = [null, null, null];
  bool _ready = false;
  bool _suspended = false;
  bool _musicOn = true;
  bool _soundOn = true;
  MusicMood _mood = MusicMood.off;
  double _duck = 1;
  Timer? _duckTimer;

  /// Loop lengths written by tool/make_audio.py. Each file carries half a
  /// second of wrapped audio before and after the loop, so any window exactly
  /// one loop long repeats without a click.
  static const _music = [
    ('assets/audio/music/pad.mp3', 32.0),
    ('assets/audio/music/mallets.mp3', 24.0),
    ('assets/audio/music/shimmer.mp3', 20.0),
  ];
  static const _loopStart = Duration(milliseconds: 250);

  static const _files = <Sfx, List<String>>{
    Sfx.turn: ['turn_1', 'turn_2', 'turn_3'],
    Sfx.align: ['align'],
    Sfx.free: ['free'],
    Sfx.peg: ['peg'],
    Sfx.tray: ['tray'],
    Sfx.win: ['win'],
    Sfx.blocked: ['blocked'],
    Sfx.tap: ['tap'],
    Sfx.coin: ['coin'],
    Sfx.star: ['star'],
    Sfx.fail: ['fail'],
    Sfx.hint: ['hint'],
    Sfx.undo: ['undo'],
    Sfx.unseal: ['unseal'],
    Sfx.unlock: ['unlock'],
  };

  @override
  Future<void> init() async {
    try {
      if (!_engine.isInitialized) await _engine.init();
      _engine.setMaxActiveVoiceCount(32);
      for (final entry in _files.entries) {
        _sources[entry.key] = [
          for (final name in entry.value)
            await _engine.loadAsset('assets/audio/sfx/$name.wav'),
        ];
      }
      for (var i = 0; i < _music.length; i++) {
        final source = await _engine.loadAsset(_music[i].$1);
        final loop = Duration(microseconds: (_music[i].$2 * 1e6).round());
        _layers[i] = _engine.play(
          source,
          volume: 0,
          looping: true,
          loopingStartAt: _loopStart,
          loopingEndAt: _loopStart + loop,
          paused: !_musicOn,
        );
      }
      _ready = true;
      _applyMood(const Duration(milliseconds: 900));
    } catch (e) {
      // The game is fully playable without sound, so never fail startup.
      debugPrint('Audio unavailable: $e');
      _ready = false;
    }
  }

  @override
  void play(Sfx sfx, {double pitch = 1, double volume = 1, double pan = 0}) {
    if (!_ready || !_soundOn || _suspended) return;
    final options = _sources[sfx];
    if (options == null || options.isEmpty) return;
    var scale = pitch;
    if (sfx == Sfx.turn) scale *= 0.96 + _rng.nextDouble() * 0.08;
    try {
      _engine.play(
        options[_rng.nextInt(options.length)],
        volume: volume.clamp(0.0, 1.0),
        pan: pan.clamp(-1.0, 1.0),
        scale: scale,
      );
    } catch (e) {
      debugPrint('Sound failed: $e');
    }
  }

  @override
  void setMood(MusicMood mood) {
    if (_mood == mood) return;
    _mood = mood;
    _applyMood(const Duration(milliseconds: 1400));
  }

  void _applyMood(Duration fade) {
    if (!_ready) return;
    final levels = [_mood.pad, _mood.mallets, _mood.shimmer];
    final on = _musicOn && !_suspended;
    for (var i = 0; i < _layers.length; i++) {
      final h = _layers[i];
      if (h == null) continue;
      try {
        _engine.fadeVolume(h, on ? levels[i] * _duck : 0, fade);
      } catch (_) {}
    }
  }

  @override
  void duck(Duration time) {
    _duck = 0.45;
    _applyMood(const Duration(milliseconds: 200));
    _duckTimer?.cancel();
    _duckTimer = Timer(time, () {
      _duck = 1;
      _applyMood(const Duration(milliseconds: 900));
    });
  }

  void _pauseLayers(bool paused) {
    if (!_ready) return;
    for (final h in _layers) {
      if (h == null) continue;
      try {
        _engine.setPause(h, paused);
      } catch (_) {}
    }
  }

  @override
  bool get musicOn => _musicOn;

  @override
  set musicOn(bool value) {
    if (_musicOn == value) return;
    _musicOn = value;
    if (value && !_suspended) _pauseLayers(false);
    _applyMood(const Duration(milliseconds: 500));
    if (!value) {
      Timer(const Duration(milliseconds: 550), () {
        if (!_musicOn) _pauseLayers(true);
      });
    }
  }

  @override
  bool get soundOn => _soundOn;

  @override
  set soundOn(bool value) => _soundOn = value;

  @override
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    _pauseLayers(true);
  }

  @override
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    if (_musicOn) _pauseLayers(false);
    _applyMood(const Duration(milliseconds: 600));
  }

  @override
  Future<void> dispose() async {
    _duckTimer?.cancel();
    if (_engine.isInitialized) await _engine.deinitAsync();
    _ready = false;
  }
}
