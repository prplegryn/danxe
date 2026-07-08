import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/asset_models.dart';

class PlayerController extends ChangeNotifier {
  static const double defaultDuration = 120;

  Timer? _timer;
  bool _playing = false;
  double _position = 0;
  double _duration = defaultDuration;
  double _speed = 1;
  double _yaw = 18;
  double _pitch = -8;
  double _distance = 5.4;
  double _panX = 0;
  double _panY = 0;

  bool get playing => _playing;
  double get position => _position;
  double get duration => _duration;
  double get speed => _speed;
  double get yaw => _yaw;
  double get pitch => _pitch;
  double get distance => _distance;
  double get panX => _panX;
  double get panY => _panY;

  String get timeLabel {
    final current = _formatSeconds(_position);
    final total = _formatSeconds(_duration);
    return '$current / $total';
  }

  void toggle() {
    _playing ? pause() : play();
  }

  void play() {
    if (_playing) return;
    _playing = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _position += 0.08 * _speed;
      if (_position > _duration) {
        _position = 0;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _playing = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void seek(double value) {
    _position = value.clamp(0, _duration).toDouble();
    notifyListeners();
  }

  void setSpeed(double value) {
    _speed = value.clamp(0.25, 2).toDouble();
    notifyListeners();
  }

  void resetCamera() {
    _yaw = 18;
    _pitch = -8;
    _distance = 5.4;
    _panX = 0;
    _panY = 0;
    notifyListeners();
  }

  void orbit({double? yaw, double? pitch, double? distance}) {
    if (yaw != null) _yaw = yaw.clamp(-180, 180).toDouble();
    if (pitch != null) _pitch = pitch.clamp(-80, 80).toDouble();
    if (distance != null) _distance = distance.clamp(1.4, 12).toDouble();
    notifyListeners();
  }

  void pan(double dx, double dy) {
    _panX = (_panX + dx).clamp(-1.5, 1.5).toDouble();
    _panY = (_panY + dy).clamp(-1.5, 1.5).toDouble();
    notifyListeners();
  }

  void applyMotion(LibraryAsset? motion, LibraryAsset? camera) {
    final motionFrames = motion?.motionCandidates.length ?? 0;
    final cameraFrames = camera?.motionCandidates.length ?? 0;
    final signal = motionFrames + cameraFrames;
    _duration = signal == 0 ? defaultDuration : 150 + signal * 8;
    _position = _position.clamp(0, _duration).toDouble();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatSeconds(double seconds) {
    final total = seconds.round();
    final minutes = total ~/ 60;
    final rest = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }
}
