import 'dart:convert';
import 'dart:io';

import '../../infrastructure/host_bridge.dart';
import '../library/asset_models.dart';
import 'export_models.dart';

class ExportController {
  ExportController(this._bridge);

  final HostBridge _bridge;

  Future<ExportJob> createRenderJob({
    required ExportSettings settings,
    required LibraryAsset model,
    LibraryAsset? motion,
    LibraryAsset? camera,
    LibraryAsset? audio,
  }) async {
    final root = await _bridge.getLibraryRoot();
    final exports = Directory('${root.path}/exports');
    if (!exports.existsSync()) {
      exports.createSync(recursive: true);
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${exports.path}/danxe_render_$stamp.json');
    final payload = <String, Object?>{
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'renderer_backend_pending',
      'settings': settings.toJson(),
      'assets': {
        'model': model.toJson(),
        if (motion != null) 'motion': motion.toJson(),
        if (camera != null) 'camera': camera.toJson(),
        if (audio != null) 'audio': audio.toJson(),
      },
      'nanoemPort': {
        'source': 'https://github.com/hkrn/nanoem',
        'currentBackend': 'indexed_asset_preview',
      },
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
    return ExportJob(
      path: file.path,
      settings: settings,
      model: model,
      motion: motion,
      camera: camera,
      audio: audio,
    );
  }
}

