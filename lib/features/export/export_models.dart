import '../library/asset_models.dart';

class ExportSettings {
  const ExportSettings({
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.videoBitrateMbps = 8,
  });

  final int width;
  final int height;
  final int fps;
  final int videoBitrateMbps;

  ExportSettings copyWith({
    int? width,
    int? height,
    int? fps,
    int? videoBitrateMbps,
  }) {
    return ExportSettings(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      videoBitrateMbps: videoBitrateMbps ?? this.videoBitrateMbps,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'width': width,
      'height': height,
      'fps': fps,
      'videoBitrateMbps': videoBitrateMbps,
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

