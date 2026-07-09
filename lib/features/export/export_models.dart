import '../library/asset_models.dart';

class ExportSettings {
  const ExportSettings({
    this.width = 1920,
    this.height = 1080,
    this.fps = 60,
    this.videoBitrateMbps = 16,
    this.durationSeconds = 10,
  });

  final int width;
  final int height;
  final int fps;
  final int videoBitrateMbps;
  final int durationSeconds;

  ExportSettings copyWith({
    int? width,
    int? height,
    int? fps,
    int? videoBitrateMbps,
    int? durationSeconds,
  }) {
    return ExportSettings(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      videoBitrateMbps: videoBitrateMbps ?? this.videoBitrateMbps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'width': width,
      'height': height,
      'fps': fps,
      'videoBitrateMbps': videoBitrateMbps,
      'seconds': durationSeconds,
    };
  }
}

class ExportJob {
  const ExportJob({
    required this.path,
    required this.settings,
    required this.model,
    this.motion,
    this.camera,
    this.audio,
  });

  final String path;
  final ExportSettings settings;
  final LibraryAsset model;
  final LibraryAsset? motion;
  final LibraryAsset? camera;
  final LibraryAsset? audio;
}
