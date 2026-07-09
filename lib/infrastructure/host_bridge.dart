import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../features/export/export_models.dart';
import '../features/library/asset_models.dart';

typedef ViewerEventHandler = Future<void> Function(ViewerEvent event);

class ViewerEvent {
  const ViewerEvent(this.values);

  final Map<String, Object?> values;

  String get type => values['type'] as String? ?? 'status';
  String? get message => values['message'] as String?;
  String? get path => values['path'] as String?;
  bool get loaded => values['loaded'] as bool? ?? false;
  bool get loading => values['loading'] as bool? ?? false;
  bool get playing => values['playing'] as bool? ?? false;
  double get current => (values['current'] as num?)?.toDouble() ?? 0;
  double get duration => (values['duration'] as num?)?.toDouble() ?? 0;
  double get speed => (values['speed'] as num?)?.toDouble() ?? 1;

  factory ViewerEvent.fromPayload(String payload) {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    return ViewerEvent(Map<String, Object?>.from(decoded));
  }
}

class HostBridge {
  HostBridge() {
    _viewerEvents.setMethodCallHandler(_handleViewerEvent);
  }

  static const MethodChannel _channel = MethodChannel('danxe/host');
  static const MethodChannel _viewerEvents = MethodChannel('danxe/viewer_events');
  static ViewerEventHandler? _viewerHandler;

  void setViewerEventHandler(ViewerEventHandler? handler) {
    _viewerHandler = handler;
  }

  Future<Directory> getLibraryRoot() async {
    final path = await _channel.invokeMethod<String>('getLibraryRoot');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Android library root is unavailable');
    }
    return Directory(path);
  }

  Future<List<LibraryAsset>> scanLibrary() async {
    final payload = await _channel.invokeMethod<String>('scanLibrary');
    final decoded = jsonDecode(payload ?? '[]') as List<dynamic>;
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => LibraryAsset.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  Future<List<LibraryAsset>> importAssets(AssetKind kind) async {
    final payload = await _channel.invokeMethod<String>(
      'importAsset',
      <String, Object?>{'kind': kind.name},
    );
    if (payload == null || payload.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(payload);
    if (decoded is List) {
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((item) => LibraryAsset.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false);
    }
    if (decoded is Map<String, dynamic>) {
      return [LibraryAsset.fromJson(Map<String, Object?>.from(decoded))];
    }
    return const [];
  }

  Future<void> deleteAsset(LibraryAsset asset) {
    return _channel.invokeMethod<void>(
      'deleteAsset',
      <String, Object?>{'kind': asset.kind.name, 'id': asset.id},
    );
  }

  Future<LibraryAsset> renameAsset(LibraryAsset asset, String name) async {
    final payload = await _channel.invokeMethod<String>(
      'renameAsset',
      <String, Object?>{'kind': asset.kind.name, 'id': asset.id, 'name': name},
    );
    final decoded = jsonDecode(payload ?? '{}') as Map<String, dynamic>;
    return LibraryAsset.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<LibraryAsset> rescanAsset(LibraryAsset asset) async {
    final payload = await _channel.invokeMethod<String>(
      'rescanAsset',
      <String, Object?>{'kind': asset.kind.name, 'id': asset.id},
    );
    final decoded = jsonDecode(payload ?? '{}') as Map<String, dynamic>;
    return LibraryAsset.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> viewerLoadScene({
    required LibraryAsset? model,
    LibraryAsset? motion,
    LibraryAsset? camera,
    LibraryAsset? audio,
    LibraryAsset? face,
  }) {
    final scene = _buildScene(
      model: model,
      motion: motion,
      camera: camera,
      audio: audio,
      face: face,
    );
    return _channel.invokeMethod<void>(
      'viewerLoadScene',
      <String, Object?>{'scene': jsonEncode(scene)},
    );
  }

  Future<void> viewerClear() {
    return _channel.invokeMethod<void>('viewerClear');
  }

  Future<void> viewerPlay() {
    return _channel.invokeMethod<void>('viewerPlay');
  }

  Future<void> viewerPause() {
    return _channel.invokeMethod<void>('viewerPause');
  }

  Future<void> viewerSeek(double second) {
    return _channel.invokeMethod<void>('viewerSeek', <String, Object?>{'second': second});
  }

  Future<void> viewerSetSpeed(double speed) {
    return _channel.invokeMethod<void>('viewerSetSpeed', <String, Object?>{'speed': speed});
  }

  Future<void> viewerSetCamera({
    required double yaw,
    required double pitch,
    required double distance,
  }) {
    return _channel.invokeMethod<void>(
      'viewerSetCamera',
      <String, Object?>{'yaw': yaw, 'pitch': pitch, 'distance': distance},
    );
  }

  Future<void> viewerSetCameraPreset(String preset) {
    return _channel.invokeMethod<void>(
      'viewerSetCameraPreset',
      <String, Object?>{'preset': preset},
    );
  }

  Future<String> viewerExport(ExportSettings settings) async {
    final path = await _channel.invokeMethod<String>(
      'viewerExport',
      <String, Object?>{'settings': jsonEncode(settings.toJson())},
    );
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Renderer did not return an export path');
    }
    return path;
  }

  Map<String, Object?> _buildScene({
    required LibraryAsset? model,
    LibraryAsset? motion,
    LibraryAsset? camera,
    LibraryAsset? audio,
    LibraryAsset? face,
  }) {
    final modelUrl = model == null || model.pmxCandidates.isEmpty
        ? null
        : _assetUrl(model, model.pmxCandidates.first);
    final motionUrls = <String>[
      if (motion != null)
        ...motion.motionCandidates.map((path) => _assetUrl(motion, path)),
      if (face != null)
        ...face.motionCandidates.map((path) => _assetUrl(face, path)),
    ];
    return <String, Object?>{
      'modelUrl': modelUrl,
      'motionUrls': motionUrls,
      'cameraUrls': camera == null
          ? const <String>[]
          : camera.motionCandidates.map((path) => _assetUrl(camera, path)).toList(),
      'audioUrl': audio == null
          ? null
          : audio.audioCandidates.isNotEmpty
              ? _assetUrl(audio, audio.audioCandidates.first)
              : Uri.file(audio.sourcePath).toString(),
      'modelName': model?.name,
      'motionName': motion?.name,
      'cameraName': camera?.name,
      'audioName': audio?.name,
      'faceName': face?.name,
    };
  }

  String _assetUrl(LibraryAsset asset, String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return Uri(
      scheme: 'https',
      host: 'danxe.local',
      pathSegments: ['library', asset.kind.name, asset.id, ...segments],
    ).toString();
  }

  Future<void> _handleViewerEvent(MethodCall call) async {
    if (call.method != 'viewerStatus') return;
    final payload = call.arguments as String? ?? '{}';
    final handler = _viewerHandler;
    if (handler != null) {
      await handler(ViewerEvent.fromPayload(payload));
    }
  }
}
