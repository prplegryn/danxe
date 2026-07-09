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
  LibraryAsset? _selectedFace;

  bool get busy => _busy;
  String? get error => _error;
  List<LibraryAsset> get assets => _assets;
  LibraryAsset? get selectedModel => _selectedModel;
  LibraryAsset? get selectedMotion => _selectedMotion;
  LibraryAsset? get selectedCamera => _selectedCamera;
  LibraryAsset? get selectedAudio => _selectedAudio;
  LibraryAsset? get selectedFace => _selectedFace;

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

  Future<List<LibraryAsset>> importKind(AssetKind kind) async {
    _setBusy(true);
    try {
      final imported = await _bridge.importAssets(kind);
      if (imported.isNotEmpty) {
        final importedIds = imported.map((asset) => asset.id).toSet();
        _assets = [
          ..._assets.where((item) => !importedIds.contains(item.id)),
          ...imported,
        ];
      }
      _error = null;
      return imported;
    } on MissingPluginException {
      _error = 'Android file picker is unavailable in this runtime.';
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
    return const [];
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
      if (_selectedFace?.id == asset.id) _selectedFace = null;
      _error = null;
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<LibraryAsset?> rename(LibraryAsset asset, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _error = 'Asset name cannot be empty.';
      notifyListeners();
      return null;
    }
    _setBusy(true);
    try {
      final updated = await _bridge.renameAsset(asset, trimmed);
      _replaceAsset(updated);
      _error = null;
      return updated;
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
    return null;
  }

  Future<LibraryAsset?> rescan(LibraryAsset asset) async {
    _setBusy(true);
    try {
      final updated = await _bridge.rescanAsset(asset);
      _replaceAsset(updated);
      _error = null;
      return updated;
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
    return null;
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
        _selectedFace = asset;
        break;
      case AssetKind.other:
        break;
    }
    notifyListeners();
  }

  void clearSelection(AssetKind kind) {
    switch (kind) {
      case AssetKind.model:
        _selectedModel = null;
        break;
      case AssetKind.motion:
        _selectedMotion = null;
        break;
      case AssetKind.camera:
        _selectedCamera = null;
        break;
      case AssetKind.audio:
        _selectedAudio = null;
        break;
      case AssetKind.face:
        _selectedFace = null;
        break;
      case AssetKind.other:
        break;
    }
    notifyListeners();
  }

  void clearScene() {
    _selectedModel = null;
    _selectedMotion = null;
    _selectedCamera = null;
    _selectedAudio = null;
    _selectedFace = null;
    notifyListeners();
  }

  void _replaceAsset(LibraryAsset updated) {
    _assets = _assets.map((asset) => asset.id == updated.id ? updated : asset).toList();
    if (_selectedModel?.id == updated.id) _selectedModel = updated;
    if (_selectedMotion?.id == updated.id) _selectedMotion = updated;
    if (_selectedCamera?.id == updated.id) _selectedCamera = updated;
    if (_selectedAudio?.id == updated.id) _selectedAudio = updated;
    if (_selectedFace?.id == updated.id) _selectedFace = updated;
  }

  void _restoreSelections() {
    _selectedModel = _existingSelection(_selectedModel, AssetKind.model);
    _selectedMotion = _existingSelection(_selectedMotion, AssetKind.motion);
    _selectedCamera = _existingSelection(_selectedCamera, AssetKind.camera);
    _selectedAudio = _existingSelection(_selectedAudio, AssetKind.audio);
    _selectedFace = _existingSelection(_selectedFace, AssetKind.face);
  }

  LibraryAsset? _existingSelection(LibraryAsset? selected, AssetKind kind) {
    if (selected == null) return null;
    return _assets
        .where((asset) => asset.kind == kind && asset.id == selected.id)
        .cast<LibraryAsset?>()
        .firstWhere((asset) => asset != null, orElse: () => null);
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
