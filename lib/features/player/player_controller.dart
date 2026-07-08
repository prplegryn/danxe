import 'package:flutter/foundation.dart';

import '../../infrastructure/host_bridge.dart';

class PlayerController extends ChangeNotifier {
  static const double defaultDuration = 0;

  bool _playing = false;
  bool _loading = false;
  bool _loaded = false;
  double _position = 0;
  double _duration = defaultDuration;
  double _speed = 1;
  double _yaw = 18;
  double _pitch = -8;
  double _distance = 5.4;
  String? _message = 'Select a PMX model.';
  String? _error;

  bool get playing => _playing;
  bool get loading => _loading;
  bool get loaded => _loaded;
  double get position => _position;
  double get duration => _duration;
  double get speed => _speed;
  double get yaw => _yaw;
  double get pitch => _pitch;
  double get distance => _distance;
  String? get message => _message;
  String? get error => _error;

  String get timeLabel {
    final current = _formatSeconds(_position);
    final total = _duration <= 0 ? '--:--' : _formatSeconds(_duration);
    return '$current / $total';
  }

  void setLoading(String message) {
    _loading = true;
    _loaded = false;
    _playing = false;
    _message = message;
    _error = null;
    _position = 0;
    _duration = 0;
    notifyListeners();
  }

  void setIdle(String message) {
    _loading = false;
    _loaded = false;
    _playing = false;
    _message = message;
    _error = null;
    _position = 0;
    _duration = 0;
    notifyListeners();
  }

  void setError(String message) {
    _loading = false;
    _loaded = false;
    _playing = false;
    _message = message;
    _error = message;
    notifyListeners();
  }

  void applyViewerEvent(ViewerEvent event) {
    switch (event.type) {
      case 'status':
        _loaded = event.loaded;
        _loading = event.loading;
        _playing = event.playing;
        _position = event.current;
        _duration = event.duration;
        _speed = event.speed;
        if (_loaded) {
          _message = null;
          _error = null;
        }
        break;
      case 'loading':
        _loading = true;
        _message = 'Loading renderer assets...';
        _error = null;
        break;
      case 'loaded':
        _loading = false;
        _loaded = event.loaded;
        _duration = event.duration;
        _message = event.loaded ? null : 'Renderer is empty.';
        _error = null;
        break;
      case 'error':
        setError(event.message ?? 'Renderer failed.');
        return;
      case 'message':
        if (event.message != null && event.message!.isNotEmpty) {
          _message = event.message;
        }
        break;
    }
    notifyListeners();
  }

  void markPlaying(bool value) {
    _playing = value;
    notifyListeners();
  }

  void seek(double value) {
    _position = value.clamp(0, _duration <= 0 ? value : _duration).toDouble();
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
    notifyListeners();
  }

  void orbit({double? yaw, double? pitch, double? distance}) {
    if (yaw != null) _yaw = yaw.clamp(-180, 180).toDouble();
    if (pitch != null) _pitch = pitch.clamp(-80, 80).toDouble();
    if (distance != null) _distance = distance.clamp(1.4, 80).toDouble();
    notifyListeners();
  }

  String _formatSeconds(double seconds) {
    final total = seconds.round();
    final minutes = total ~/ 60;
    final rest = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }
}

