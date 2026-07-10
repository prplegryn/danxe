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
  List<ViewerPart> get parts {
    final raw = values['parts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => ViewerPart.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  factory ViewerEvent.fromPayload(String payload) {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    return ViewerEvent(Map<String, Object?>.from(decoded));
  }
}

class ViewerPart {
  const ViewerPart({
    required this.id,
    required this.name,
    required this.visible,
  });

  final String id;
  final String name;
  final bool visible;

  factory ViewerPart.fromJson(Map<String, Object?> json) {
    return ViewerPart(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Part',
      visible: json['visible'] as bool? ?? true,
    );
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
    required List<AppliedModelSlot> models,
    LibraryAsset? camera,
    LibraryAsset? audio,
  }) {
    final scene = _buildScene(
      models: models,
      camera: camera,
      audio: audio,
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

  Future<void> viewerSetLook(Map<String, Object?> look) {
    return _channel.invokeMethod<void>(
      'viewerSetLook',
      <String, Object?>{'look': jsonEncode(look)},
    );
  }

  Future<void> viewerSetViewOptions({
    required bool gridVisible,
    required bool floorVisible,
  }) {
    return _channel.invokeMethod<void>(
      'viewerSetViewOptions',
      <String, Object?>{
        'view': jsonEncode(<String, Object?>{
          'gridVisible': gridVisible,
          'floorVisible': floorVisible,
        }),
      },
    );
  }

  Future<void> viewerSetPartVisibility(String id, bool visible) {
    return _channel.invokeMethod<void>(
      'viewerSetPartVisibility',
      <String, Object?>{'id': id, 'visible': visible},
    );
  }

  Future<void> viewerSetModelTransform({
    required String id,
    required double x,
    required double y,
    required double z,
  }) {
    return _channel.invokeMethod<void>(
      'viewerSetModelTransform',
      <String, Object?>{'id': id, 'x': x, 'y': y, 'z': z},
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
    required List<AppliedModelSlot> models,
    LibraryAsset? camera,
    LibraryAsset? audio,
  }) {
    final renderableModels = models.where((slot) => slot.model.pmxCandidates.isNotEmpty);
    final sceneModels = renderableModels
        .map((slot) {
          final motionUrls = <String>[
            if (slot.motion != null)
              ...slot.motion!.motionCandidates.map((path) => _assetUrl(slot.motion!, path)),
            if (slot.face != null)
              ...slot.face!.motionCandidates.map((path) => _assetUrl(slot.face!, path)),
          ];
          return <String, Object?>{
            'id': slot.id,
            'modelUrl': _assetUrl(slot.model, slot.model.pmxCandidates.first),
            'motionUrls': motionUrls,
            'modelName': slot.model.name,
            'motionName': slot.motion?.name,
            'faceName': slot.face?.name,
            'transform': <String, Object?>{
              'x': slot.x,
              'y': slot.y,
              'z': slot.z,
            },
          };
        })
        .toList(growable: false);
    final first = sceneModels.isEmpty ? null : sceneModels.first;
    return <String, Object?>{
      'models': sceneModels,
      'modelUrl': first == null ? null : first['modelUrl'],
      'motionUrls': first == null ? const <String>[] : first['motionUrls'],
      'cameraUrls': camera == null
          ? const <String>[]
          : camera.motionCandidates.map((path) => _assetUrl(camera, path)).toList(),
      'audioUrl': audio == null
          ? null
          : audio.audioCandidates.isNotEmpty
              ? _assetUrl(audio, audio.audioCandidates.first)
              : Uri.file(audio.sourcePath).toString(),
      'modelName': first == null ? null : first['modelName'],
      'motionName': first == null ? null : first['motionName'],
      'cameraName': camera?.name,
      'audioName': audio?.name,
      'faceName': first == null ? null : first['faceName'],
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
