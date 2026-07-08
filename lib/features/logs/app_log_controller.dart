import 'package:flutter/foundation.dart';

enum AppLogLevel {
  info,
  warning,
  error;

  String get label {
    switch (this) {
      case AppLogLevel.info:
        return 'INFO';
      case AppLogLevel.warning:
        return 'WARN';
      case AppLogLevel.error:
        return 'ERROR';
    }
  }
}

class AppLogEntry {
  const AppLogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
  });

  final DateTime time;
  final AppLogLevel level;
  final String module;
  final String message;

  String get line {
    final stamp = time.toIso8601String();
    return '[$stamp] ${level.label} $module: $message';
  }
}

class AppLogController extends ChangeNotifier {
  static const int _maxEntries = 200;
  final List<AppLogEntry> _entries = [];

  List<AppLogEntry> get entries => List.unmodifiable(_entries.reversed);

  void info(String module, String message) {
    _add(AppLogLevel.info, module, message);
  }

  void warning(String module, String message) {
    _add(AppLogLevel.warning, module, message);
  }

  void error(String module, String message) {
    _add(AppLogLevel.error, module, message);
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String dump() {
    if (_entries.isEmpty) return 'No log entries.';
    return _entries.map((entry) => entry.line).join('\n');
  }

  void _add(AppLogLevel level, String module, String message) {
    _entries.add(
      AppLogEntry(
        time: DateTime.now(),
        level: level,
        module: module,
        message: message,
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }
}
