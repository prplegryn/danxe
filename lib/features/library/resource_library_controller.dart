import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../infrastructure/host_bridge.dart';
import 'asset_models.dart';

class ResourceLibraryController extends ChangeNotifier {
  ResourceLibraryController(this._bridge);

  final HostBridge _bridge;

  bool _busy = false;
  String? _error;
  List<LibraryAsset> _assets = const [];
  LibraryAsset? _selectedModel;
  LibraryAsset? _selectedMotion;
  LibraryAsset? _selectedCamera;
  LibraryAsset? _selectedAudio;

  bool get busy => _busy;
  String? get error => _error;
  List<LibraryAsset> get assets => _assets;
  LibraryAsset? get selectedModel => _selectedModel;
  LibraryAsset? get selectedMotion => _selectedMotion;
  LibraryAsset? get selectedCamera => _selectedCamera;
  LibraryAsset? get selectedAudio => _selectedAudio;

  List<LibraryAsset> byKind(AssetKind kind) {
    return _assets.where((asset) => asset.kind == kind).toList(growable: false);
  }

  Future<void> load() async {
    _setBusy(true);
    try {
      _assets = await _bridge.scanLibrary();
      _restoreSelections();
      _error = null;
    } on MissingPluginException {
      _error = 'Android host bridge is not attached.';
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<LibraryAsset?> importKind(AssetKind kind) async {
    _setBusy(true);
    try {
      final asset = await _bridge.importAsset(kind);
      if (asset != null) {
        _assets = [..._assets.where((item) => item.id != asset.id), asset];
        select(asset);
      }
      _error = null;
      return asset;
    } on MissingPluginException {
      _error = 'Android file picker is unavailable in this runtime.';
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
    return null;
  }

  Future<void> delete(LibraryAsset asset) async {
    _setBusy(true);
    try {
      await _bridge.deleteAsset(asset);
      _assets = _assets.where((item) => item.id != asset.id).toList();
      if (_selectedModel?.id == asset.id) _selectedModel = null;
      if (_selectedMotion?.id == asset.id) _selectedMotion = null;
      if (_selectedCamera?.id == asset.id) _selectedCamera = null;
      if (_selectedAudio?.id == asset.id) _selectedAudio = null;
      _error = null;
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
  }

  void select(LibraryAsset asset) {
    switch (asset.kind) {
      case AssetKind.model:
        _selectedModel = asset;
        break;
      case AssetKind.motion:
        _selectedMotion = asset;
        break;
      case AssetKind.camera:
        _selectedCamera = asset;
        break;
      case AssetKind.audio:
        _selectedAudio = asset;
        break;
      case AssetKind.face:
      case AssetKind.other:
        break;
    }
    notifyListeners();
  }

  void _restoreSelections() {
    _selectedModel ??= _assets
        .where((asset) => asset.kind == AssetKind.model)
        .cast<LibraryAsset?>()
        .firstWhere((asset) => asset != null, orElse: () => null);
    _selectedMotion ??= _assets
        .where((asset) => asset.kind == AssetKind.motion)
        .cast<LibraryAsset?>()
        .firstWhere((asset) => asset != null, orElse: () => null);
    _selectedCamera ??= _assets
        .where((asset) => asset.kind == AssetKind.camera)
        .cast<LibraryAsset?>()
        .firstWhere((asset) => asset != null, orElse: () => null);
    _selectedAudio ??= _assets
        .where((asset) => asset.kind == AssetKind.audio)
        .cast<LibraryAsset?>()
        .firstWhere((asset) => asset != null, orElse: () => null);
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
