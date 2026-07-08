import '../../infrastructure/host_bridge.dart';
import '../library/asset_models.dart';
import 'export_models.dart';

class ExportController {
  ExportController(this._bridge);

  final HostBridge _bridge;

  Future<ExportJob> exportVideo({
    required ExportSettings settings,
    required LibraryAsset model,
    LibraryAsset? motion,
    LibraryAsset? camera,
    LibraryAsset? audio,
  }) async {
    final path = await _bridge.viewerExport(settings);
    return ExportJob(
      path: path,
      settings: settings,
      model: model,
      motion: motion,
      camera: camera,
      audio: audio,
    );
  }
}

