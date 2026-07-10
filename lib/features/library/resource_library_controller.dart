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
  List<AppliedModelSlot> _modelSlots = const [];
  String? _activeModelSlotId;
  LibraryAsset? _selectedMotion;
  LibraryAsset? _selectedCamera;
  LibraryAsset? _selectedAudio;
  LibraryAsset? _selectedFace;

  bool get busy => _busy;
  String? get error => _error;
  List<LibraryAsset> get assets => _assets;
  List<AppliedModelSlot> get modelSlots => _modelSlots;
  AppliedModelSlot? get activeModelSlot {
    if (_modelSlots.isEmpty) return null;
    for (final slot in _modelSlots) {
      if (slot.id == _activeModelSlotId) return slot;
    }
    return _modelSlots.first;
  }

  LibraryAsset? get selectedModel => activeModelSlot?.model;
  LibraryAsset? get selectedMotion {
    final active = activeModelSlot;
    return active == null ? _selectedMotion : active.motion;
  }

  LibraryAsset? get selectedCamera => _selectedCamera;
  LibraryAsset? get selectedAudio => _selectedAudio;
  LibraryAsset? get selectedFace {
    final active = activeModelSlot;
    return active == null ? _selectedFace : active.face;
  }

  String get sceneSignature {
    final modelPart = _modelSlots
        .map((slot) => [
              slot.id,
              slot.model.id,
              slot.motion?.id ?? '',
              slot.face?.id ?? '',
            ].join('@'))
        .join('|');
    return [
      modelPart,
      _selectedCamera?.id,
      _selectedAudio?.id,
    ].join(':');
  }

  List<DanceAssetPackage> get dancePackages {
    final grouped = <String, List<LibraryAsset>>{};
    for (final asset in _assets) {
      if (asset.packageId.isEmpty) continue;
      if (asset.kind != AssetKind.motion &&
          asset.kind != AssetKind.audio &&
          asset.kind != AssetKind.face &&
          asset.kind != AssetKind.camera) {
        continue;
      }
      grouped.putIfAbsent(asset.packageId, () => <LibraryAsset>[]).add(asset);
    }

    final packages = grouped.entries.map((entry) {
      final assets = entry.value;
      LibraryAsset? firstOf(AssetKind kind) {
        for (final asset in assets) {
          if (asset.kind == kind) return asset;
        }
        return null;
      }

      final fallbackName = assets.first.packageName.isNotEmpty
          ? assets.first.packageName
          : assets.first.name.split('.').first;
      return DanceAssetPackage(
        id: entry.key,
        name: fallbackName,
        motion: firstOf(AssetKind.motion),
        audio: firstOf(AssetKind.audio),
        face: firstOf(AssetKind.face),
        camera: firstOf(AssetKind.camera),
      );
    }).where((bundle) => bundle.canApply).toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return packages;
  }

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
      if (asset.kind == AssetKind.model) {
        _modelSlots = _modelSlots.where((slot) => slot.model.id != asset.id).toList();
      } else {
        _modelSlots = _modelSlots
            .map(
              (slot) => slot.copyWith(
                clearMotion: slot.motion?.id == asset.id,
                clearFace: slot.face?.id == asset.id,
              ),
            )
            .toList(growable: false);
      }
      if (_selectedMotion?.id == asset.id) _selectedMotion = null;
      if (_selectedCamera?.id == asset.id) _selectedCamera = null;
      if (_selectedAudio?.id == asset.id) _selectedAudio = null;
      if (_selectedFace?.id == asset.id) _selectedFace = null;
      _normalizeActiveModel();
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
        toggleModel(asset);
        return;
      case AssetKind.motion:
        _assignToActiveModel(motion: asset, notify: false);
        break;
      case AssetKind.camera:
        _selectedCamera = asset;
        break;
      case AssetKind.audio:
        _selectedAudio = asset;
        break;
      case AssetKind.face:
        _assignToActiveModel(face: asset, notify: false);
        break;
      case AssetKind.other:
        break;
    }
    notifyListeners();
  }

  void applyDancePackage(DanceAssetPackage bundle) {
    _assignToActiveModel(motion: bundle.motion, face: bundle.face, notify: false);
    _selectedAudio = bundle.audio;
    notifyListeners();
  }

  bool isModelApplied(LibraryAsset asset) {
    return _modelSlots.any((slot) => slot.model.id == asset.id);
  }

  void setActiveModelSlot(String id) {
    if (_modelSlots.any((slot) => slot.id == id)) {
      _activeModelSlotId = id;
      notifyListeners();
    }
  }

  void toggleModel(LibraryAsset asset) {
    final existing = _modelSlots.where((slot) => slot.model.id == asset.id).toList();
    if (existing.isNotEmpty) {
      final removedId = existing.first.id;
      _modelSlots = _modelSlots.where((slot) => slot.id != removedId).toList(growable: false);
      if (_activeModelSlotId == removedId) {
        _activeModelSlotId = _modelSlots.isEmpty ? null : _modelSlots.first.id;
      }
    } else {
      final slot = AppliedModelSlot(
        id: asset.id,
        model: asset,
        motion: _modelSlots.isEmpty ? _selectedMotion : null,
        face: _modelSlots.isEmpty ? _selectedFace : null,
      );
      _modelSlots = [..._modelSlots, slot];
      _activeModelSlotId = slot.id;
    }
    notifyListeners();
  }

  void updateModelTransform(String id, {double? x, double? y, double? z}) {
    _modelSlots = _modelSlots
        .map((slot) => slot.id == id ? slot.copyWith(x: x, y: y, z: z) : slot)
        .toList(growable: false);
    notifyListeners();
  }

  void clearSelection(AssetKind kind) {
    switch (kind) {
      case AssetKind.model:
        _modelSlots = const [];
        _activeModelSlotId = null;
        break;
      case AssetKind.motion:
        _assignToActiveModel(clearMotion: true, notify: false);
        break;
      case AssetKind.camera:
        _selectedCamera = null;
        break;
      case AssetKind.audio:
        _selectedAudio = null;
        break;
      case AssetKind.face:
        _assignToActiveModel(clearFace: true, notify: false);
        break;
      case AssetKind.other:
        break;
    }
    notifyListeners();
  }

  void clearScene() {
    _modelSlots = const [];
    _activeModelSlotId = null;
    _selectedMotion = null;
    _selectedCamera = null;
    _selectedAudio = null;
    _selectedFace = null;
    notifyListeners();
  }

  void _replaceAsset(LibraryAsset updated) {
    _assets = _assets.map((asset) => asset.id == updated.id ? updated : asset).toList();
    _modelSlots = _modelSlots
        .map(
          (slot) => slot.copyWith(
            model: updated.kind == AssetKind.model && slot.model.id == updated.id ? updated : null,
            motion: updated.kind == AssetKind.motion && slot.motion?.id == updated.id ? updated : null,
            face: updated.kind == AssetKind.face && slot.face?.id == updated.id ? updated : null,
          ),
        )
        .toList(growable: false);
    if (_selectedMotion?.id == updated.id) _selectedMotion = updated;
    if (_selectedCamera?.id == updated.id) _selectedCamera = updated;
    if (_selectedAudio?.id == updated.id) _selectedAudio = updated;
    if (_selectedFace?.id == updated.id) _selectedFace = updated;
  }

  void _restoreSelections() {
    _modelSlots = _modelSlots
        .map((slot) {
          final model = _existingSelection(slot.model, AssetKind.model);
          if (model == null) return null;
          final motion = _existingSelection(slot.motion, AssetKind.motion);
          final face = _existingSelection(slot.face, AssetKind.face);
          return slot.copyWith(
            model: model,
            motion: motion,
            face: face,
            clearMotion: slot.motion != null && motion == null,
            clearFace: slot.face != null && face == null,
          );
        })
        .whereType<AppliedModelSlot>()
        .toList(growable: false);
    _normalizeActiveModel();
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

  void _assignToActiveModel({
    LibraryAsset? motion,
    LibraryAsset? face,
    bool clearMotion = false,
    bool clearFace = false,
    bool notify = true,
  }) {
    final active = activeModelSlot;
    if (active == null) {
      if (motion != null) _selectedMotion = motion;
      if (face != null) _selectedFace = face;
      if (clearMotion) _selectedMotion = null;
      if (clearFace) _selectedFace = null;
      if (notify) notifyListeners();
      return;
    }
    _modelSlots = _modelSlots
        .map(
          (slot) => slot.id == active.id
              ? slot.copyWith(
                  motion: motion,
                  face: face,
                  clearMotion: clearMotion,
                  clearFace: clearFace,
                )
              : slot,
        )
        .toList(growable: false);
    if (notify) notifyListeners();
  }

  void _normalizeActiveModel() {
    if (_modelSlots.isEmpty) {
      _activeModelSlotId = null;
      return;
    }
    if (!_modelSlots.any((slot) => slot.id == _activeModelSlotId)) {
      _activeModelSlotId = _modelSlots.first.id;
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
