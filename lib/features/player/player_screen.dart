import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_tokens.dart';
import '../../infrastructure/host_bridge.dart';
import '../export/export_controller.dart';
import '../export/export_models.dart';
import '../library/asset_models.dart';
import '../library/resource_library_controller.dart';
import '../logs/app_log_controller.dart';
import 'player_controller.dart';

enum _QuickMenu { view, camera, apply }

class _LookSettings {
  const _LookSettings({
    required this.preset,
    required this.enabled,
    required this.exposure,
    required this.contrast,
    required this.saturation,
    required this.brightness,
    required this.dehaze,
    required this.ambient,
    required this.key,
    required this.rim,
    required this.specular,
    required this.shininess,
    required this.toon,
    required this.texture,
    required this.floor,
  });

  final String preset;
  final bool enabled;
  final double exposure;
  final double contrast;
  final double saturation;
  final double brightness;
  final double dehaze;
  final double ambient;
  final double key;
  final double rim;
  final double specular;
  final double shininess;
  final double toon;
  final double texture;
  final bool floor;

  static const balanced = _LookSettings(
    preset: 'balanced',
    enabled: true,
    exposure: 1.03,
    contrast: 1.26,
    saturation: 1.36,
    brightness: 1.03,
    dehaze: 0.11,
    ambient: 1.16,
    key: 1.72,
    rim: 0.52,
    specular: 0.56,
    shininess: 34,
    toon: 1.16,
    texture: 1.30,
    floor: true,
  );

  static const clear = _LookSettings(
    preset: 'clear',
    enabled: true,
    exposure: 1.04,
    contrast: 1.30,
    saturation: 1.30,
    brightness: 1.06,
    dehaze: 0.12,
    ambient: 1.22,
    key: 1.78,
    rim: 0.42,
    specular: 0.46,
    shininess: 30,
    toon: 1.08,
    texture: 1.30,
    floor: true,
  );

  static const vivid = _LookSettings(
    preset: 'vivid',
    enabled: true,
    exposure: 1.05,
    contrast: 1.42,
    saturation: 1.74,
    brightness: 1.04,
    dehaze: 0.17,
    ambient: 1.02,
    key: 1.92,
    rim: 0.70,
    specular: 0.68,
    shininess: 44,
    toon: 1.28,
    texture: 1.58,
    floor: true,
  );

  static const stage = _LookSettings(
    preset: 'stage',
    enabled: true,
    exposure: 1.08,
    contrast: 1.36,
    saturation: 1.46,
    brightness: 1.02,
    dehaze: 0.15,
    ambient: 0.88,
    key: 2.25,
    rim: 1.08,
    specular: 0.80,
    shininess: 54,
    toon: 1.18,
    texture: 1.40,
    floor: true,
  );

  static _LookSettings forPreset(String preset, _LookSettings current) {
    final next = switch (preset) {
      'clear' => clear,
      'vivid' => vivid,
      'stage' => stage,
      _ => balanced,
    };
    return next.copyWith(enabled: current.enabled, floor: current.floor);
  }

  String get presetLabel {
    return switch (preset) {
      'clear' => 'Clear',
      'vivid' => 'Vivid',
      'stage' => 'Stage',
      _ => 'Balanced',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'preset': preset,
      'enabled': enabled,
      'exposure': exposure,
      'contrast': contrast,
      'saturation': saturation,
      'brightness': brightness,
      'dehaze': dehaze,
      'ambient': ambient,
      'key': key,
      'rim': rim,
      'specular': specular,
      'shininess': shininess,
      'toon': toon,
      'texture': texture,
      'floor': floor,
    };
  }

  _LookSettings copyWith({
    String? preset,
    bool? enabled,
    double? exposure,
    double? contrast,
    double? saturation,
    double? brightness,
    double? dehaze,
    double? ambient,
    double? key,
    double? rim,
    double? specular,
    double? shininess,
    double? toon,
    double? texture,
    bool? floor,
  }) {
    return _LookSettings(
      preset: preset ?? this.preset,
      enabled: enabled ?? this.enabled,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      brightness: brightness ?? this.brightness,
      dehaze: dehaze ?? this.dehaze,
      ambient: ambient ?? this.ambient,
      key: key ?? this.key,
      rim: rim ?? this.rim,
      specular: specular ?? this.specular,
      shininess: shininess ?? this.shininess,
      toon: toon ?? this.toon,
      texture: texture ?? this.texture,
      floor: floor ?? this.floor,
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final HostBridge _bridge;
  late final ResourceLibraryController _library;
  late final PlayerController _player;
  late final ExportController _export;
  late final AppLogController _logs;

  bool _exporting = false;
  bool _uiHidden = false;
  bool _editMode = false;
  bool _lookOpen = false;
  bool _gridVisible = true;
  bool _floorVisible = false;
  _LookSettings _look = _LookSettings.balanced;
  _QuickMenu? _openQuickMenu;
  List<ViewerPart> _modelParts = const [];
  String? _lastSceneSignature;
  String? _lastLibraryError;

  @override
  void initState() {
    super.initState();
    _logs = AppLogController()..info('app', 'Danxe started.');
    _bridge = HostBridge()..setViewerEventHandler(_onViewerEvent);
    _library = ResourceLibraryController(_bridge)..load();
    _player = PlayerController();
    _export = ExportController(_bridge);
    _library.addListener(_syncScene);
  }

  @override
  void dispose() {
    _bridge.setViewerEventHandler(null);
    _library.removeListener(_syncScene);
    _library.dispose();
    _player.dispose();
    _logs.dispose();
    super.dispose();
  }

  Future<void> _onViewerEvent(ViewerEvent event) async {
    if (!mounted) return;
    setState(() {
      if (event.type == 'exportComplete' || event.type == 'exportError') {
        _exporting = false;
      }
      if (event.type == 'parts') {
        _modelParts = event.parts;
      }
      if (event.values.containsKey('gridVisible')) {
        _gridVisible = event.values['gridVisible'] as bool? ?? _gridVisible;
      }
      if (event.values.containsKey('floorVisible')) {
        _floorVisible = event.values['floorVisible'] as bool? ?? _floorVisible;
      }
      _player.applyViewerEvent(event);
    });

    switch (event.type) {
      case 'parts':
        _logs.info('renderer', 'Model parts listed: ${event.parts.length}.');
        break;
      case 'loaded':
        _logs.info('renderer', 'Scene loaded.');
        break;
      case 'message':
        if ((event.message ?? '').isNotEmpty) {
          _logs.info('renderer', event.message!);
        }
        break;
      case 'error':
      case 'exportError':
        _logs.error('renderer', event.message ?? 'Renderer failed.');
        _showMessage(event.message ?? 'Renderer failed.');
        break;
      case 'exportComplete':
        if (event.path != null) {
          _logs.info('export', 'Video exported to ${event.path}.');
          _showMessage('Video exported: ${event.path}');
        }
        break;
      case 'exportStarted':
        final audioLabel = event.values['audio'] == true ? 'audio' : 'no audio';
        _logs.info(
          'export',
          'Recording ${event.values['width']}x${event.values['height']} ${event.values['fps']}fps ${event.values['mimeType']} $audioLabel.',
        );
        break;
    }
  }

  void _syncScene() {
    final error = _library.error;
    if (error != null && error != _lastLibraryError) {
      _lastLibraryError = error;
      _logs.error('library', error);
      _showMessage(error);
    }

    final signature = _library.sceneSignature;
    if (signature == _lastSceneSignature) return;
    _lastSceneSignature = signature;
    if (mounted) {
      setState(() => _modelParts = const []);
    }

    final models = _library.modelSlots;
    if (models.isEmpty) {
      _player.setIdle('Choose a model from Apply.');
      _bridge.viewerClear().catchError((Object error) {
        _logs.error('renderer', error.toString());
      });
      return;
    }
    final renderableModels = models.where((slot) => slot.hasRenderableModel).toList(growable: false);
    for (final slot in models.where((slot) => !slot.hasRenderableModel)) {
      _logs.error('apply', '${slot.model.name} has no PMX or PMD file.');
    }
    if (renderableModels.isEmpty) {
      _player.setError('Selected models have no PMX or PMD file.');
      _bridge.viewerClear().catchError((Object error) {
        _logs.error('renderer', error.toString());
      });
      return;
    }

    final names = renderableModels.map((slot) => slot.model.name).join(', ');
    _player.setLoading('Loading ${renderableModels.length} model${renderableModels.length == 1 ? '' : 's'}...');
    _logs.info('apply', 'Loading models: $names.');
    _bridge
        .viewerLoadScene(
          models: renderableModels,
          camera: _library.selectedCamera,
          audio: _library.selectedAudio,
        )
        .catchError((Object error) {
      if (!mounted) return;
      _player.setError(error.toString());
      _logs.error('renderer', error.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_library, _player]),
      builder: (context, _) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, _) {
              final safe = MediaQuery.paddingOf(context);
              final bottom = safe.bottom + 16;

              return Stack(
                children: [
                  const Positioned.fill(child: NativeMmdViewport()),
                  if (_uiHidden)
                    Positioned(
                      top: safe.top + 10,
                      right: safe.right + 10,
                      child: _RestoreUiButton(onPressed: _showUi),
                    )
                  else ...[
                    Positioned(
                      left: 16,
                      bottom: bottom,
                      child: _MiniTransportCapsule(
                        player: _player,
                        exporting: _exporting,
                        canExport: _library.modelSlots.any((slot) => slot.hasRenderableModel),
                        onToggle: _togglePlayback,
                        onExport: () {
                          _closeQuickMenu();
                          _showExportSheet();
                        },
                      ),
                    ),
                    if (_editMode && _library.modelSlots.isNotEmpty)
                      Positioned(
                        top: safe.top + 12,
                        left: 16,
                        right: 16,
                        child: _ModelEditTabs(
                          slots: _library.modelSlots,
                          activeId: _library.activeModelSlot?.id,
                          onSelected: _library.setActiveModelSlot,
                        ),
                      ),
                    if (_editMode && _library.activeModelSlot != null)
                      Positioned(
                        top: safe.top + 112,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _ModelTransformGizmo(
                            onMove: (x, y, z) => _moveActiveModel(x: x, y: y, z: z),
                          ),
                        ),
                      ),
                    if (_editMode && _library.activeModelSlot != null)
                      Positioned(
                        left: 16,
                        right: 84,
                        bottom: bottom + 72,
                        child: _ModelTransformPanel(
                          slot: _library.activeModelSlot!,
                          onChanged: _setActiveModelTransform,
                        ),
                      ),
                    Positioned(
                      left: 16,
                      bottom: bottom + 66,
                      child: _LookFloatingControls(
                        open: _lookOpen,
                        look: _look,
                        onToggle: _toggleLookControls,
                        onChanged: (look) => _setLook(look),
                        onPreset: (look) => _setLook(look, log: true),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: bottom,
                      child: _QuickActionDock(
                        openMenu: _openQuickMenu,
                        onToggleMenu: _toggleQuickMenu,
                        onApplyKind: _openAssetPickerFromDock,
                        onOpenLibrary: _openLibraryFromDock,
                        onOpenDancePackages: _openDancePackagesFromDock,
                        editMode: _editMode,
                        onToggleEditMode: _toggleEditMode,
                        onHideUi: _hideUi,
                        onToggleGrid: _toggleGrid,
                        onToggleFloor: _toggleFloor,
                        onTogglePart: _togglePartVisibility,
                        onLog: () {
                          _closeQuickMenu();
                          _showLogSheet();
                        },
                        onCameraPreset: _applyCameraPreset,
                        gridVisible: _gridVisible,
                        floorVisible: _floorVisible,
                        modelParts: _modelParts,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _togglePlayback() async {
    if (!_player.loaded) return;
    if (_player.playing) {
      await _bridge.viewerPause();
      _player.markPlaying(false);
      _logs.info('player', 'Paused.');
    } else {
      await _bridge.viewerPlay();
      _player.markPlaying(true);
      _logs.info('player', 'Playing.');
    }
  }

  Future<void> _seek(double value) async {
    _player.seek(value);
    await _bridge.viewerSeek(value);
  }

  Future<void> _setSpeed(double value) async {
    _player.setSpeed(value);
    await _bridge.viewerSetSpeed(value);
    _logs.info('player', 'Speed set to ${value}x.');
  }

  Future<void> _pushCamera() async {
    await _bridge.viewerSetCamera(
      yaw: _player.yaw,
      pitch: _player.pitch,
      distance: _player.distance,
    );
  }

  void _toggleQuickMenu(_QuickMenu menu) {
    setState(() {
      _lookOpen = false;
      _editMode = false;
      _openQuickMenu = _openQuickMenu == menu ? null : menu;
    });
  }

  void _toggleLookControls() {
    setState(() {
      _openQuickMenu = null;
      _editMode = false;
      _lookOpen = !_lookOpen;
    });
  }

  void _toggleEditMode() {
    setState(() {
      _openQuickMenu = null;
      _lookOpen = false;
      _editMode = !_editMode;
    });
  }

  void _closeQuickMenu() {
    if (_openQuickMenu == null && !_lookOpen) return;
    setState(() {
      _openQuickMenu = null;
      _lookOpen = false;
    });
  }

  void _hideUi() {
    setState(() {
      _openQuickMenu = null;
      _lookOpen = false;
      _editMode = false;
      _uiHidden = true;
    });
  }

  void _showUi() {
    setState(() => _uiHidden = false);
  }

  void _openAssetPickerFromDock(AssetKind kind) {
    _closeQuickMenu();
    _showAssetPicker(kind);
  }

  void _openLibraryFromDock() {
    _closeQuickMenu();
    _showLibraryManager();
  }

  void _openDancePackagesFromDock() {
    _closeQuickMenu();
    _showDancePackagePicker();
  }

  void _moveActiveModel({double x = 0, double y = 0, double z = 0}) {
    final slot = _library.activeModelSlot;
    if (slot == null) return;
    _setActiveModelTransform(
      slot.copyWith(
        x: _clampModelAxis(slot.x + x),
        y: _clampModelAxis(slot.y + y, min: -20, max: 80),
        z: _clampModelAxis(slot.z + z),
      ),
    );
  }

  void _setActiveModelTransform(AppliedModelSlot next) {
    _library.updateModelTransform(
      next.id,
      x: _clampModelAxis(next.x),
      y: _clampModelAxis(next.y, min: -20, max: 80),
      z: _clampModelAxis(next.z),
    );
    _bridge
        .viewerSetModelTransform(
          id: next.id,
          x: _clampModelAxis(next.x),
          y: _clampModelAxis(next.y, min: -20, max: 80),
          z: _clampModelAxis(next.z),
        )
        .catchError((Object error) {
      _logs.error('edit', error.toString());
    });
  }

  double _clampModelAxis(double value, {double min = -50, double max = 50}) {
    return value.clamp(min, max).toDouble();
  }

  Future<void> _toggleGrid() async {
    final nextGrid = !_gridVisible;
    await _setViewOptions(gridVisible: nextGrid, floorVisible: false);
  }

  Future<void> _toggleFloor() async {
    final nextFloor = !_floorVisible;
    await _setViewOptions(
      gridVisible: nextFloor ? false : _gridVisible,
      floorVisible: nextFloor,
    );
  }

  Future<void> _setViewOptions({
    required bool gridVisible,
    required bool floorVisible,
  }) async {
    final normalizedGrid = floorVisible ? false : gridVisible;
    setState(() {
      _gridVisible = normalizedGrid;
      _floorVisible = floorVisible;
    });
    try {
      await _bridge.viewerSetViewOptions(
        gridVisible: normalizedGrid,
        floorVisible: floorVisible,
      );
      _logs.info(
        'view',
        'Grid=${normalizedGrid ? 'on' : 'off'}, floor=${floorVisible ? 'on' : 'off'}.',
      );
    } on Object catch (error) {
      _logs.error('view', error.toString());
    }
  }

  void _togglePartVisibility(ViewerPart part) {
    final nextVisible = !part.visible;
    setState(() {
      _modelParts = _modelParts
          .map((item) => item.id == part.id
              ? ViewerPart(id: item.id, name: item.name, visible: nextVisible)
              : item)
          .toList(growable: false);
    });
    _bridge.viewerSetPartVisibility(part.id, nextVisible).catchError((Object error) {
      _logs.error('view', error.toString());
    });
    _logs.info('view', '${nextVisible ? 'Showed' : 'Hid'} ${part.name}.');
  }

  Future<void> _applyCameraPreset(String preset) async {
    _closeQuickMenu();
    await _bridge.viewerSetCameraPreset(preset);
    _logs.info('camera', preset == 'halfFront' ? 'Applied half-front preset.' : 'Applied full-front preset.');
  }

  void _setLook(_LookSettings look, {bool log = false}) {
    setState(() => _look = look);
    _bridge.viewerSetLook(look.toJson()).catchError((Object error) {
      _logs.error('look', error.toString());
    });
    if (log) {
      _logs.info('look', 'Applied ${look.presetLabel} look.');
    }
  }

  Future<void> _showApplySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SheetHeader(title: 'Apply assets'),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width < 480 ? 2 : 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.32,
                      children: [
                        _ApplyTile(
                          icon: _iconForKind(AssetKind.model),
                          title: 'Model',
                          value: _library.selectedModel?.name ?? 'None',
                          onTap: () => _openPickerFromSheet(context, AssetKind.model),
                        ),
                        _ApplyTile(
                          icon: _iconForKind(AssetKind.motion),
                          title: 'Motion',
                          value: _library.selectedMotion?.name ?? 'None',
                          onTap: () => _openPickerFromSheet(context, AssetKind.motion),
                        ),
                        _ApplyTile(
                          icon: _iconForKind(AssetKind.camera),
                          title: 'Camera',
                          value: _library.selectedCamera?.name ?? 'None',
                          onTap: () => _openPickerFromSheet(context, AssetKind.camera),
                        ),
                        _ApplyTile(
                          icon: _iconForKind(AssetKind.audio),
                          title: 'Audio',
                          value: _library.selectedAudio?.name ?? 'None',
                          onTap: () => _openPickerFromSheet(context, AssetKind.audio),
                        ),
                        _ApplyTile(
                          icon: _iconForKind(AssetKind.face),
                          title: 'Face',
                          value: _library.selectedFace?.name ?? 'None',
                          onTap: () => _openPickerFromSheet(context, AssetKind.face),
                        ),
                        _ApplyTile(
                          icon: Icons.inventory_2_rounded,
                          title: 'Library',
                          value: '${_library.assets.length} assets',
                          onTap: () => _openLibraryFromSheet(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _library.clearScene();
                          _logs.info('apply', 'Scene bindings cleared.');
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.layers_clear_rounded),
                        label: const Text('Clear current scene'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openPickerFromSheet(BuildContext sheetContext, AssetKind kind) {
    Navigator.of(sheetContext).pop();
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _showAssetPicker(kind);
    });
  }

  void _openLibraryFromSheet(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _showLibraryManager();
    });
  }

  Future<void> _showAssetPicker(AssetKind kind) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                final assets = _library.byKind(kind);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetHeader(
                        title: 'Apply ${kind.label}',
                        action: FilledButton.icon(
                          onPressed: _library.busy ? null : () => _import(kind),
                          icon: _library.busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_rounded),
                          label: const Text('Import'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if ((kind == AssetKind.motion || kind == AssetKind.face) &&
                          _library.modelSlots.isNotEmpty) ...[
                        _ModelEditTabs(
                          slots: _library.modelSlots,
                          activeId: _library.activeModelSlot?.id,
                          onSelected: _library.setActiveModelSlot,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: assets.isEmpty
                            ? _EmptyAssets(kind: kind, onImport: () => _import(kind))
                            : ListView.separated(
                                itemCount: assets.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final asset = assets[index];
                                  return _AssetRow(
                                    asset: asset,
                                    selected: kind == AssetKind.model
                                        ? _library.isModelApplied(asset)
                                        : _isSelected(asset),
                                    showCheckbox: kind == AssetKind.model,
                                    onTap: () {
                                      _applyAsset(asset);
                                      if (kind != AssetKind.model &&
                                          kind != AssetKind.motion &&
                                          kind != AssetKind.face) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                                    onEdit: () => _showAssetEditor(asset),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDancePackagePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.66,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                final packages = _library.dancePackages;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetHeader(title: 'Dance packages'),
                      const SizedBox(height: 12),
                      if (_library.modelSlots.isNotEmpty) ...[
                        _ModelEditTabs(
                          slots: _library.modelSlots,
                          activeId: _library.activeModelSlot?.id,
                          onSelected: _library.setActiveModelSlot,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: packages.isEmpty
                            ? Center(
                                child: Text(
                                  'Import a motion/audio zip first.',
                                  style: TextStyle(color: AppColors.textMuted.withOpacity(0.86)),
                                ),
                              )
                            : ListView.separated(
                                itemCount: packages.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final bundle = packages[index];
                                  return _DancePackageRow(
                                    bundle: bundle,
                                    onTap: () {
                                      final target = _library.activeModelSlot?.model.name;
                                      _library.applyDancePackage(bundle);
                                      _logs.info(
                                        'apply',
                                        target == null
                                            ? 'Applied dance package ${bundle.name} without camera.'
                                            : 'Applied dance package ${bundle.name} to $target without camera.',
                                      );
                                      Navigator.of(context).pop();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLibraryManager() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                return DefaultTabController(
                  length: 5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SheetHeader(
                          title: 'Library',
                          action: IconButton.filledTonal(
                            tooltip: 'Reload library',
                            onPressed: _library.busy ? null : () => _library.load(),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const TabBar(
                          isScrollable: true,
                          tabs: [
                            Tab(text: 'Models'),
                            Tab(text: 'Motion'),
                            Tab(text: 'Camera'),
                            Tab(text: 'Audio'),
                            Tab(text: 'Face'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _LibraryKindTab(
                                kind: AssetKind.model,
                                controller: _library,
                                selected: _isSelected,
                                onImport: () => _import(AssetKind.model),
                                onApply: _applyAsset,
                                onEdit: _showAssetEditor,
                              ),
                              _LibraryKindTab(
                                kind: AssetKind.motion,
                                controller: _library,
                                selected: _isSelected,
                                onImport: () => _import(AssetKind.motion),
                                onApply: _applyAsset,
                                onEdit: _showAssetEditor,
                              ),
                              _LibraryKindTab(
                                kind: AssetKind.camera,
                                controller: _library,
                                selected: _isSelected,
                                onImport: () => _import(AssetKind.camera),
                                onApply: _applyAsset,
                                onEdit: _showAssetEditor,
                              ),
                              _LibraryKindTab(
                                kind: AssetKind.audio,
                                controller: _library,
                                selected: _isSelected,
                                onImport: () => _import(AssetKind.audio),
                                onApply: _applyAsset,
                                onEdit: _showAssetEditor,
                              ),
                              _LibraryKindTab(
                                kind: AssetKind.face,
                                controller: _library,
                                selected: _isSelected,
                                onImport: () => _import(AssetKind.face),
                                onApply: _applyAsset,
                                onEdit: _showAssetEditor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAssetEditor(LibraryAsset initialAsset) async {
    final nameController = TextEditingController(text: initialAsset.name);
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        builder: (context) {
          return SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                final asset = _library.assets.firstWhere(
                  (item) => item.id == initialAsset.id,
                  orElse: () => initialAsset,
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    MediaQuery.viewInsetsOf(context).bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetHeader(title: 'Edit asset'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 12),
                      _DetailLine(label: 'Kind', value: asset.kind.label),
                      _DetailLine(label: 'Files', value: '${asset.fileCount} files'),
                      _DetailLine(label: 'Size', value: _formatBytes(asset.totalBytes)),
                      _DetailLine(label: 'Source', value: asset.sourceName),
                      _DetailLine(label: 'Detected', value: _assetCapability(asset)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _library.busy
                                ? null
                                : () async {
                                    final updated = await _library.rename(
                                      asset,
                                      nameController.text,
                                    );
                                    if (updated != null) {
                                      _logs.info('library', 'Renamed ${asset.name} to ${updated.name}.');
                                    }
                                  },
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Save'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _library.busy
                                ? null
                                : () async {
                                    final updated = await _library.rescan(asset);
                                    if (updated != null) {
                                      _logs.info('library', 'Rescanned ${updated.name}.');
                                    }
                                  },
                            icon: const Icon(Icons.manage_search_rounded),
                            label: const Text('Rescan'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _library.busy
                                ? null
                                : () async {
                                    final confirmed = await _confirmDelete(asset);
                                    if (!confirmed || !mounted) return;
                                    await _library.delete(asset);
                                    _logs.warning('library', 'Deleted ${asset.name}.');
                                    if (mounted) Navigator.of(context).pop();
                                  },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      nameController.dispose();
    }
  }

  Future<bool> _confirmDelete(LibraryAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete asset'),
          content: Text('Delete "${asset.name}" from the internal library?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _showLogSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _logs,
              builder: (context, _) {
                final entries = _logs.entries;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetHeader(
                        title: 'Recent log',
                        action: Wrap(
                          spacing: 8,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Copy log',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _logs.dump()));
                                _showMessage('Log copied.');
                              },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Clear log',
                              onPressed: _logs.clear,
                              icon: const Icon(Icons.clear_all_rounded),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: entries.isEmpty
                            ? const Center(
                                child: Text(
                                  'No log entries.',
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: entries.length,
                                separatorBuilder: (context, index) => const Divider(
                                  color: AppColors.line,
                                  height: 18,
                                ),
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  return _LogLine(entry: entry);
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCameraSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: _player,
            builder: (context, _) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SheetHeader(
                      title: 'Camera',
                      action: IconButton.filledTonal(
                        tooltip: 'Reset camera',
                        onPressed: () {
                          _player.resetCamera();
                          _pushCamera();
                          _logs.info('camera', 'Camera reset.');
                        },
                        icon: const Icon(Icons.center_focus_strong_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CameraSlider(
                      label: 'Yaw',
                      value: _player.yaw,
                      min: -180,
                      max: 180,
                      onChanged: (value) {
                        _player.orbit(yaw: value);
                        _pushCamera();
                      },
                    ),
                    _CameraSlider(
                      label: 'Pitch',
                      value: _player.pitch,
                      min: -80,
                      max: 80,
                      onChanged: (value) {
                        _player.orbit(pitch: value);
                        _pushCamera();
                      },
                    ),
                    _CameraSlider(
                      label: 'Distance',
                      value: _player.distance,
                      min: 1.4,
                      max: 80,
                      onChanged: (value) {
                        _player.orbit(distance: value);
                        _pushCamera();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showExportSheet() async {
    final models = _library.modelSlots.where((slot) => slot.hasRenderableModel).toList(growable: false);
    if (models.isEmpty) return;
    final model = models.first.model;
    final screenExportSize = _currentScreenExportSize(context);
    final sizeLabels = <String, String>{
      '1920x1080': '16:9',
      '1080x1920': '9:16',
      '1280x720': '720p',
    };
    final screenKey = '${screenExportSize.width}x${screenExportSize.height}';
    sizeLabels[screenKey] = sizeLabels.containsKey(screenKey)
        ? '${sizeLabels[screenKey]}/Scr'
        : 'Screen';
    var settings = ExportSettings(
      durationSeconds: _player.duration > 0
          ? _player.duration.round().clamp(1, 600).toInt()
          : 10,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SheetHeader(title: 'Export video'),
                    const SizedBox(height: 12),
                    _SegmentedExportRow(
                      label: 'Size',
                      value: '${settings.width}x${settings.height}',
                      options: sizeLabels.keys.toList(growable: false),
                      labels: sizeLabels,
                      onSelected: (value) {
                        final parts = value.split('x').map(int.parse).toList();
                        setSheetState(() {
                          settings = settings.copyWith(width: parts[0], height: parts[1]);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _SegmentedExportRow(
                      label: 'FPS',
                      value: '${settings.fps}',
                      options: const ['30', '60'],
                      onSelected: (value) {
                        setSheetState(() => settings = settings.copyWith(fps: int.parse(value)));
                      },
                    ),
                    const SizedBox(height: 12),
                    _SegmentedExportRow(
                      label: 'Bitrate',
                      value: '${settings.videoBitrateMbps}',
                      options: const ['12', '16', '24'],
                      labels: const {'12': '12M', '16': '16M', '24': '24M'},
                      onSelected: (value) {
                        setSheetState(() {
                          settings = settings.copyWith(videoBitrateMbps: int.parse(value));
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _SegmentedExportRow(
                      label: 'Length',
                      value: '${settings.durationSeconds}',
                      options: [
                        '10',
                        '30',
                        '${_player.duration > 0 ? _player.duration.round().clamp(1, 600) : 10}',
                      ],
                      onSelected: (value) {
                        setSheetState(() {
                          settings = settings.copyWith(durationSeconds: int.parse(value));
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _exporting
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(this.context);
                                final navigator = Navigator.of(context);
                                setState(() => _exporting = true);
                                _logs.info('export', 'Started ${settings.width}x${settings.height} ${settings.fps}fps.');
                                try {
                                  final job = await _export.exportVideo(
                                    settings: settings,
                                    model: model,
                                    motion: _library.selectedMotion,
                                    camera: _library.selectedCamera,
                                    audio: _library.selectedAudio,
                                  );
                                  if (navigator.canPop()) navigator.pop();
                                  _logs.info('export', 'Video exported to ${job.path}.');
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Video exported: ${job.path}')),
                                  );
                                } catch (error) {
                                  if (mounted) setState(() => _exporting = false);
                                  _logs.error('export', error.toString());
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(error.toString())),
                                  );
                                }
                              },
                        icon: _exporting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.movie_creation_rounded),
                        label: Text(_exporting ? 'Recording...' : 'Record video'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  ({int width, int height}) _currentScreenExportSize(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final aspect = size.width / (size.height <= 0 ? 1.0 : size.height);
    if (aspect >= 1) {
      final height = 1080;
      return (width: _even(height * aspect), height: height);
    }
    final width = 1080;
    return (width: width, height: _even(width / aspect));
  }

  int _even(double value) {
    final rounded = (value / 2).round() * 2;
    return rounded < 2 ? 2 : rounded;
  }

  Future<void> _import(AssetKind kind) async {
    final imported = await _library.importKind(kind);
    if (imported.isNotEmpty) {
      final names = imported.map((asset) => asset.name).join(', ');
      _logs.info('library', 'Imported ${imported.length} resource${imported.length == 1 ? '' : 's'}: $names.');
      if (kind == AssetKind.face) {
        _logs.info('apply', 'Face VMD is ready to apply.');
      }
    }
  }

  void _applyAsset(LibraryAsset asset) {
    final wasApplied = asset.kind == AssetKind.model && _library.isModelApplied(asset);
    final activeBefore = _library.activeModelSlot;
    _library.select(asset);
    if (asset.kind == AssetKind.model) {
      _logs.info('apply', '${wasApplied ? 'Removed' : 'Applied'} model: ${asset.name}.');
      return;
    }
    final target = activeBefore?.model.name;
    _logs.info(
      'apply',
      target == null
          ? 'Applied ${asset.kind.name}: ${asset.name}.'
          : 'Applied ${asset.kind.name} to $target: ${asset.name}.',
    );
    if (asset.kind == AssetKind.face) {
      _logs.info('apply', 'Face VMD will be merged into the model animation.');
    }
  }

  bool _isSelected(LibraryAsset asset) {
    return (asset.kind == AssetKind.model && _library.isModelApplied(asset)) ||
        _library.selectedMotion?.id == asset.id ||
        _library.selectedCamera?.id == asset.id ||
        _library.selectedAudio?.id == asset.id ||
        _library.selectedFace?.id == asset.id;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class NativeMmdViewport extends StatelessWidget {
  const NativeMmdViewport({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: Text('Android MMD renderer required.')),
      );
    }
    return AndroidView(
      viewType: 'danxe/mmd_view',
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

class _SceneHud extends StatelessWidget {
  const _SceneHud({
    required this.model,
    required this.motion,
    required this.camera,
    required this.audio,
    required this.face,
    required this.player,
    required this.busy,
  });

  final LibraryAsset? model;
  final LibraryAsset? motion;
  final LibraryAsset? camera;
  final LibraryAsset? audio;
  final LibraryAsset? face;
  final PlayerController player;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final status = player.error ??
        player.message ??
        (player.loaded ? 'Ready' : 'Waiting');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: _Panel(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_rounded, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model?.name ?? 'No model applied',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _sceneSubtitle(motion, camera, audio, face, status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (busy || player.loading)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                player.loaded ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: player.loaded ? AppColors.success : AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  String _sceneSubtitle(
    LibraryAsset? motion,
    LibraryAsset? camera,
    LibraryAsset? audio,
    LibraryAsset? face,
    String status,
  ) {
    final parts = <String>[
      status,
      if (motion != null) 'Motion: ${motion.name}',
      if (camera != null) 'Camera: ${camera.name}',
      if (audio != null) 'Audio: ${audio.name}',
      if (face != null) 'Face: ${face.name}',
    ];
    return parts.join('  /  ');
  }
}

class _MiniTransportCapsule extends StatelessWidget {
  const _MiniTransportCapsule({
    required this.player,
    required this.exporting,
    required this.canExport,
    required this.onToggle,
    required this.onExport,
  });

  final PlayerController player;
  final bool exporting;
  final bool canExport;
  final VoidCallback onToggle;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.9),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleIconButton(
              tooltip: player.playing ? 'Pause' : 'Play',
              icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              selected: player.playing,
              onPressed: player.loaded ? onToggle : null,
            ),
            const SizedBox(width: 6),
            _CircleIconButton(
              tooltip: 'Export',
              icon: exporting ? null : Icons.file_download_rounded,
              busy: exporting,
              onPressed: canExport && player.loaded && !exporting ? onExport : null,
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                player.timeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LookFloatingControls extends StatelessWidget {
  const _LookFloatingControls({
    required this.open,
    required this.look,
    required this.onToggle,
    required this.onChanged,
    required this.onPreset,
  });

  final bool open;
  final _LookSettings look;
  final VoidCallback onToggle;
  final ValueChanged<_LookSettings> onChanged;
  final ValueChanged<_LookSettings> onPreset;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sliderWidth = (size.width - 32).clamp(236.0, 336.0).toDouble();
    final maxListHeight = (size.height * 0.48).clamp(220.0, 372.0).toDouble();
    final presetMaxWidth = (size.width - 82).clamp(180.0, 336.0).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.bottomLeft,
            heightFactor: open ? 1 : 0,
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: sliderWidth,
                maxHeight: maxListHeight,
              ),
              child: SingleChildScrollView(
                reverse: true,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _control(
                      icon: Icons.filter_b_and_w_rounded,
                      label: 'Haze',
                      value: look.dehaze,
                      min: 0,
                      max: 0.45,
                      onChanged: (value) => onChanged(look.copyWith(dehaze: value)),
                    ),
                    _control(
                      icon: Icons.palette_rounded,
                      label: 'Sat',
                      value: look.saturation,
                      min: 0.50,
                      max: 2.50,
                      onChanged: (value) => onChanged(look.copyWith(saturation: value)),
                    ),
                    _control(
                      icon: Icons.contrast_rounded,
                      label: 'Ctr',
                      value: look.contrast,
                      min: 0.75,
                      max: 2.00,
                      onChanged: (value) => onChanged(look.copyWith(contrast: value)),
                    ),
                    _control(
                      icon: Icons.texture_rounded,
                      label: 'Tex',
                      value: look.texture,
                      min: 0.50,
                      max: 2.00,
                      onChanged: (value) => onChanged(look.copyWith(texture: value)),
                    ),
                    _control(
                      icon: Icons.exposure_rounded,
                      label: 'Exp',
                      value: look.exposure,
                      min: 0.70,
                      max: 1.60,
                      onChanged: (value) => onChanged(look.copyWith(exposure: value)),
                    ),
                    _control(
                      icon: Icons.light_mode_rounded,
                      label: 'Amb',
                      value: look.ambient,
                      min: 0.2,
                      max: 2.4,
                      onChanged: (value) => onChanged(look.copyWith(ambient: value)),
                    ),
                    _control(
                      icon: Icons.flashlight_on_rounded,
                      label: 'Key',
                      value: look.key,
                      min: 0.2,
                      max: 3.2,
                      onChanged: (value) => onChanged(look.copyWith(key: value)),
                    ),
                    _control(
                      icon: Icons.flare_rounded,
                      label: 'Rim',
                      value: look.rim,
                      min: 0,
                      max: 1.8,
                      onChanged: (value) => onChanged(look.copyWith(rim: value)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(height: open ? 10 : 0),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleIconButton(
              tooltip: 'Look',
              icon: Icons.auto_awesome_rounded,
              selected: open,
              onPressed: onToggle,
            ),
            ClipRect(
              child: AnimatedAlign(
                alignment: Alignment.centerLeft,
                widthFactor: open ? 1 : 0,
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: presetMaxWidth),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LookPresetButton(
                            tooltip: 'Balanced',
                            icon: Icons.tonality_rounded,
                            selected: look.preset == 'balanced',
                            onPressed: () => onPreset(_LookSettings.forPreset('balanced', look)),
                          ),
                          const SizedBox(width: 8),
                          _LookPresetButton(
                            tooltip: 'Clear',
                            icon: Icons.wb_sunny_rounded,
                            selected: look.preset == 'clear',
                            onPressed: () => onPreset(_LookSettings.forPreset('clear', look)),
                          ),
                          const SizedBox(width: 8),
                          _LookPresetButton(
                            tooltip: 'Vivid',
                            icon: Icons.palette_rounded,
                            selected: look.preset == 'vivid',
                            onPressed: () => onPreset(_LookSettings.forPreset('vivid', look)),
                          ),
                          const SizedBox(width: 8),
                          _LookPresetButton(
                            tooltip: 'Stage',
                            icon: Icons.flare_rounded,
                            selected: look.preset == 'stage',
                            onPressed: () => onPreset(_LookSettings.forPreset('stage', look)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _control({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _FloatingLookSlider(
        icon: icon,
        label: label,
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

class _FloatingLookSlider extends StatelessWidget {
  const _FloatingLookSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withOpacity(0.72),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: AppColors.text),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                min: min,
                max: max,
                value: clampedValue,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                clampedValue.toStringAsFixed(clampedValue >= 10 ? 0 : 2),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _LookPresetButton extends StatelessWidget {
  const _LookPresetButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: selected
              ? AppColors.primary
              : AppColors.surfaceHigh.withOpacity(0.72),
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.line),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _QuickActionDock extends StatelessWidget {
  const _QuickActionDock({
    required this.openMenu,
    required this.onToggleMenu,
    required this.onApplyKind,
    required this.onOpenLibrary,
    required this.onOpenDancePackages,
    required this.editMode,
    required this.onToggleEditMode,
    required this.onHideUi,
    required this.onToggleGrid,
    required this.onToggleFloor,
    required this.onTogglePart,
    required this.onLog,
    required this.onCameraPreset,
    required this.gridVisible,
    required this.floorVisible,
    required this.modelParts,
  });

  final _QuickMenu? openMenu;
  final ValueChanged<_QuickMenu> onToggleMenu;
  final ValueChanged<AssetKind> onApplyKind;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenDancePackages;
  final bool editMode;
  final VoidCallback onToggleEditMode;
  final VoidCallback onHideUi;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleFloor;
  final ValueChanged<ViewerPart> onTogglePart;
  final VoidCallback onLog;
  final ValueChanged<String> onCameraPreset;
  final bool gridVisible;
  final bool floorVisible;
  final List<ViewerPart> modelParts;

  @override
  Widget build(BuildContext context) {
    final maxActionsWidth = MediaQuery.sizeOf(context).width - 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _CircleIconButton(
          tooltip: 'Edit model placement',
          icon: Icons.open_with_rounded,
          selected: editMode,
          onPressed: onToggleEditMode,
        ),
        const SizedBox(height: 12),
        _ViewActionDock(
          open: openMenu == _QuickMenu.view,
          maxActionsWidth: maxActionsWidth,
          modelParts: modelParts,
          gridVisible: gridVisible,
          floorVisible: floorVisible,
          onToggleMenu: () => onToggleMenu(_QuickMenu.view),
          onHideUi: onHideUi,
          onToggleGrid: onToggleGrid,
          onToggleFloor: onToggleFloor,
          onTogglePart: onTogglePart,
        ),
        const SizedBox(height: 12),
        _ExpandableDockRow(
          maxActionsWidth: maxActionsWidth,
          open: openMenu == _QuickMenu.camera,
          actions: [
            _CircleIconButton(
              tooltip: 'Full front',
              icon: Icons.accessibility_new_rounded,
              onPressed: () => onCameraPreset('fullFront'),
            ),
            _CircleIconButton(
              tooltip: 'Half front',
              icon: Icons.portrait_rounded,
              onPressed: () => onCameraPreset('halfFront'),
            ),
          ],
          anchor: _CircleIconButton(
            tooltip: 'Camera presets',
            icon: Icons.video_camera_front_rounded,
            selected: openMenu == _QuickMenu.camera,
            onPressed: () => onToggleMenu(_QuickMenu.camera),
          ),
        ),
        const SizedBox(height: 12),
        _ExpandableDockRow(
          maxActionsWidth: maxActionsWidth,
          open: openMenu == _QuickMenu.apply,
          actions: [
            _CircleIconButton(
              tooltip: 'Apply model',
              icon: _iconForKind(AssetKind.model),
              onPressed: () => onApplyKind(AssetKind.model),
            ),
            _CircleIconButton(
              tooltip: 'Apply motion',
              icon: _iconForKind(AssetKind.motion),
              onPressed: () => onApplyKind(AssetKind.motion),
            ),
            _CircleIconButton(
              tooltip: 'Apply camera',
              icon: _iconForKind(AssetKind.camera),
              onPressed: () => onApplyKind(AssetKind.camera),
            ),
            _CircleIconButton(
              tooltip: 'Apply audio',
              icon: _iconForKind(AssetKind.audio),
              onPressed: () => onApplyKind(AssetKind.audio),
            ),
            _CircleIconButton(
              tooltip: 'Apply face',
              icon: _iconForKind(AssetKind.face),
              onPressed: () => onApplyKind(AssetKind.face),
            ),
            _CircleIconButton(
              tooltip: 'Library',
              icon: Icons.inventory_2_rounded,
              onPressed: onOpenLibrary,
            ),
            _CircleIconButton(
              tooltip: 'Dance packages',
              icon: Icons.playlist_play_rounded,
              onPressed: onOpenDancePackages,
            ),
          ],
          anchor: _CircleIconButton(
            tooltip: 'Apply',
            icon: Icons.layers_rounded,
            selected: openMenu == _QuickMenu.apply,
            onPressed: () => onToggleMenu(_QuickMenu.apply),
          ),
        ),
        const SizedBox(height: 12),
        _CircleIconButton(
          tooltip: 'Log',
          icon: Icons.receipt_long_rounded,
          onPressed: onLog,
        ),
      ],
    );
  }
}

class _ViewActionDock extends StatelessWidget {
  const _ViewActionDock({
    required this.open,
    required this.maxActionsWidth,
    required this.modelParts,
    required this.gridVisible,
    required this.floorVisible,
    required this.onToggleMenu,
    required this.onHideUi,
    required this.onToggleGrid,
    required this.onToggleFloor,
    required this.onTogglePart,
  });

  final bool open;
  final double maxActionsWidth;
  final List<ViewerPart> modelParts;
  final bool gridVisible;
  final bool floorVisible;
  final VoidCallback onToggleMenu;
  final VoidCallback onHideUi;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleFloor;
  final ValueChanged<ViewerPart> onTogglePart;

  @override
  Widget build(BuildContext context) {
    final panelHeight = (MediaQuery.sizeOf(context).height * 0.36).clamp(188.0, 286.0).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.bottomRight,
            heightFactor: open ? 1 : 0,
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PartVisibilityPanel(
                parts: modelParts,
                maxHeight: panelHeight,
                onTogglePart: onTogglePart,
              ),
            ),
          ),
        ),
        _ExpandableDockRow(
          maxActionsWidth: maxActionsWidth,
          open: open,
          actions: [
            _CircleIconButton(
              tooltip: 'Hide UI',
              icon: Icons.visibility_off_rounded,
              onPressed: onHideUi,
            ),
            _CircleIconButton(
              tooltip: 'Grid',
              icon: Icons.grid_4x4_rounded,
              selected: gridVisible,
              onPressed: onToggleGrid,
            ),
            _CircleIconButton(
              tooltip: 'Floor',
              icon: Icons.crop_square_rounded,
              selected: floorVisible,
              onPressed: onToggleFloor,
            ),
          ],
          anchor: _CircleIconButton(
            tooltip: 'View',
            icon: Icons.visibility_rounded,
            selected: open,
            onPressed: onToggleMenu,
          ),
        ),
      ],
    );
  }
}

class _PartVisibilityPanel extends StatelessWidget {
  const _PartVisibilityPanel({
    required this.parts,
    required this.maxHeight,
    required this.onTogglePart,
  });

  final List<ViewerPart> parts;
  final double maxHeight;
  final ValueChanged<ViewerPart> onTogglePart;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 40).clamp(228.0, 300.0).toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.92),
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.24),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: parts.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Text(
                  'No model parts',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: parts.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.line,
                ),
                itemBuilder: (context, index) {
                  final part = parts[index];
                  return InkWell(
                    onTap: () => onTogglePart(part),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              part.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: part.visible,
                            onChanged: (_) => onTogglePart(part),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _RestoreUiButton extends StatelessWidget {
  const _RestoreUiButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 56,
      child: Center(
        child: SizedBox.square(
          dimension: 40,
          child: IconButton(
            tooltip: 'Show UI',
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: AppColors.surfaceHigh.withOpacity(0.72),
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.line),
            ),
            icon: const Icon(Icons.visibility_rounded, size: 19),
          ),
        ),
      ),
    );
  }
}

class _ModelEditTabs extends StatelessWidget {
  const _ModelEditTabs({
    required this.slots,
    required this.activeId,
    required this.onSelected,
  });

  final List<AppliedModelSlot> slots;
  final String? activeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (final slot in slots) ...[
              _ModelEditTab(
                slot: slot,
                selected: slot.id == activeId,
                onPressed: () => onSelected(slot.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelEditTab extends StatelessWidget {
  const _ModelEditTab({
    required this.slot,
    required this.selected,
    required this.onPressed,
  });

  final AppliedModelSlot slot;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 92, maxWidth: 168),
      child: Material(
        color: selected ? AppColors.primary : AppColors.surfaceHigh.withOpacity(0.76),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.accessibility_new_rounded, size: 18),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    slot.model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelTransformGizmo extends StatelessWidget {
  const _ModelTransformGizmo({required this.onMove});

  final void Function(double x, double y, double z) onMove;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 142,
        height: 118,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 47,
              child: _GizmoArrow(
                tooltip: 'Move up',
                icon: Icons.north_rounded,
                color: AppColors.success,
                onTap: () => onMove(0, 0.1, 0),
                onDrag: (delta) => onMove(0, -delta.dy * 0.025, 0),
              ),
            ),
            Positioned(
              left: 0,
              top: 54,
              child: _GizmoArrow(
                tooltip: 'Move X',
                icon: Icons.east_rounded,
                color: AppColors.danger,
                onTap: () => onMove(0.1, 0, 0),
                onDrag: (delta) => onMove(delta.dx * 0.025, 0, 0),
              ),
            ),
            Positioned(
              right: 0,
              top: 54,
              child: _GizmoArrow(
                tooltip: 'Move depth',
                icon: Icons.south_rounded,
                color: AppColors.accent,
                onTap: () => onMove(0, 0, 0.1),
                onDrag: (delta) => onMove(0, 0, delta.dy * 0.025),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GizmoArrow extends StatelessWidget {
  const _GizmoArrow({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onDrag,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => onDrag(details.delta),
      child: SizedBox.square(
        dimension: 48,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: color.withOpacity(0.92),
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.line),
          ),
          icon: Icon(icon, size: 24),
        ),
      ),
    );
  }
}

class _ModelTransformPanel extends StatelessWidget {
  const _ModelTransformPanel({
    required this.slot,
    required this.onChanged,
  });

  final AppliedModelSlot slot;
  final ValueChanged<AppliedModelSlot> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.open_with_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slot.model.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Reset placement',
                onPressed: () => onChanged(slot.copyWith(x: 0, y: 0, z: 0)),
                icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
              ),
            ],
          ),
          _TransformAxisControl(
            label: 'X',
            value: slot.x,
            color: AppColors.danger,
            onChanged: (value) => onChanged(slot.copyWith(x: value)),
            onNudge: (delta) => onChanged(slot.copyWith(x: slot.x + delta)),
          ),
          _TransformAxisControl(
            label: 'Y',
            value: slot.y,
            color: AppColors.success,
            min: -20,
            max: 80,
            onChanged: (value) => onChanged(slot.copyWith(y: value)),
            onNudge: (delta) => onChanged(slot.copyWith(y: slot.y + delta)),
          ),
          _TransformAxisControl(
            label: 'Z',
            value: slot.z,
            color: AppColors.accent,
            onChanged: (value) => onChanged(slot.copyWith(z: value)),
            onNudge: (delta) => onChanged(slot.copyWith(z: slot.z + delta)),
          ),
        ],
      ),
    );
  }
}

class _TransformAxisControl extends StatelessWidget {
  const _TransformAxisControl({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    required this.onNudge,
    this.min = -50,
    this.max = 50,
  });

  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onNudge;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              tooltip: '$label -',
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => onNudge(-0.1),
              icon: const Icon(Icons.remove_rounded, size: 18),
            ),
          ),
          Expanded(
            child: Slider(
              min: min,
              max: max,
              value: clamped,
              onChanged: onChanged,
            ),
          ),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              tooltip: '$label +',
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => onNudge(0.1),
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              clamped.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableDockRow extends StatelessWidget {
  const _ExpandableDockRow({
    required this.open,
    required this.actions,
    required this.anchor,
    required this.maxActionsWidth,
  });

  final bool open;
  final List<Widget> actions;
  final Widget anchor;
  final double maxActionsWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.centerRight,
            widthFactor: open ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxActionsWidth.clamp(160.0, 320.0).toDouble(),
              ),
              child: SingleChildScrollView(
                reverse: true,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) const SizedBox(width: 6),
                      actions[index],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(width: open ? 10 : 0),
        ),
        anchor,
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.busy = false,
  });

  final String tooltip;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: busy ? null : onPressed,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: selected ? AppColors.primary : AppColors.surfaceHigh.withOpacity(0.94),
          disabledBackgroundColor: AppColors.surfaceHigh.withOpacity(0.48),
          foregroundColor: AppColors.text,
          disabledForegroundColor: AppColors.textMuted.withOpacity(0.52),
          side: const BorderSide(color: AppColors.line),
        ),
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 22),
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.compact,
    required this.player,
    required this.exporting,
    required this.canExport,
    required this.onToggle,
    required this.onSeek,
    required this.onSpeed,
    required this.onExport,
  });

  final bool compact;
  final PlayerController player;
  final bool exporting;
  final bool canExport;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeed;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: player.playing ? 'Pause' : 'Play',
            onPressed: player.loaded ? onToggle : null,
            icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: compact ? 58 : 96,
            child: Text(
              player.timeLabel,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: player.duration <= 0 ? 1 : player.duration,
              value: player.duration <= 0 ? 0 : player.position.clamp(0, player.duration).toDouble(),
              onChanged: player.loaded ? onSeek : null,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            _SpeedMenu(speed: player.speed, enabled: player.loaded, onSelected: onSpeed),
          ],
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Export',
            onPressed: canExport && player.loaded && !exporting ? onExport : null,
            icon: exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.movie_creation_rounded),
          ),
        ],
      ),
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({
    required this.speed,
    required this.enabled,
    required this.onSelected,
  });

  final double speed;
  final bool enabled;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      enabled: enabled,
      initialValue: speed,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 0.5, child: Text('0.5x')),
        PopupMenuItem(value: 1.0, child: Text('1x')),
        PopupMenuItem(value: 1.5, child: Text('1.5x')),
        PopupMenuItem(value: 2.0, child: Text('2x')),
      ],
      child: SizedBox(
        width: 52,
        height: 48,
        child: Center(
          child: Text(
            '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 1)}x',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(8),
      elevation: 12,
      shadowColor: Colors.black.withOpacity(0.38),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(
          width: 104,
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundToolButton extends StatelessWidget {
  const _RoundToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _ApplyTile extends StatelessWidget {
  const _ApplyTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 24),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.asset,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    this.showCheckbox = false,
  });

  final LibraryAsset asset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final bool showCheckbox;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withOpacity(0.24) : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              if (showCheckbox) ...[
                Checkbox(
                  value: selected,
                  onChanged: (_) => onTap(),
                ),
                const SizedBox(width: 4),
              ],
              Icon(_iconForKind(asset.kind), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_assetCapability(asset)}  /  ${asset.fileCount} files  /  ${_formatBytes(asset.totalBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryKindTab extends StatelessWidget {
  const _LibraryKindTab({
    required this.kind,
    required this.controller,
    required this.selected,
    required this.onImport,
    required this.onApply,
    required this.onEdit,
  });

  final AssetKind kind;
  final ResourceLibraryController controller;
  final bool Function(LibraryAsset asset) selected;
  final VoidCallback onImport;
  final ValueChanged<LibraryAsset> onApply;
  final ValueChanged<LibraryAsset> onEdit;

  @override
  Widget build(BuildContext context) {
    final assets = controller.byKind(kind);
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: controller.busy ? null : onImport,
            icon: const Icon(Icons.add_rounded),
            label: Text('Import ${kind.label}'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: assets.isEmpty
              ? _EmptyAssets(kind: kind, onImport: onImport)
              : ListView.separated(
                  itemCount: assets.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    return _AssetRow(
                      asset: asset,
                      selected: selected(asset),
                      showCheckbox: kind == AssetKind.model,
                      onTap: () => onApply(asset),
                      onEdit: () => onEdit(asset),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DancePackageRow extends StatelessWidget {
  const _DancePackageRow({
    required this.bundle,
    required this.onTap,
  });

  final DanceAssetPackage bundle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: bundle.canApply ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.playlist_play_rounded, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      bundle.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bundle.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAssets extends StatelessWidget {
  const _EmptyAssets({required this.kind, required this.onImport});

  final AssetKind kind;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconForKind(kind), size: 42, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No imported ${kind.label.toLowerCase()}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      AppLogLevel.info => AppColors.textMuted,
      AppLogLevel.warning => Colors.amberAccent,
      AppLogLevel.error => AppColors.danger,
    };
    return SelectableText(
      entry.line,
      style: TextStyle(
        color: color,
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.45,
      ),
    );
  }
}

class _CameraSlider extends StatelessWidget {
  const _CameraSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            value: value,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}

class _SegmentedExportRow extends StatelessWidget {
  const _SegmentedExportRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.labels,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final Map<String, String>? labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: SegmentedButton<String>(
            segments: options
                .toSet()
                .map(
                  (option) => ButtonSegment<String>(
                    value: option,
                    label: Text(labels?[option] ?? option),
                  ),
                )
                .toList(),
            selected: {value},
            onSelectionChanged: (selected) => onSelected(selected.first),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(8)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.88),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

IconData _iconForKind(AssetKind kind) {
  switch (kind) {
    case AssetKind.model:
      return Icons.accessibility_new_rounded;
    case AssetKind.motion:
      return Icons.directions_run_rounded;
    case AssetKind.camera:
      return Icons.videocam_rounded;
    case AssetKind.audio:
      return Icons.graphic_eq_rounded;
    case AssetKind.face:
      return Icons.face_retouching_natural_rounded;
    case AssetKind.other:
      return Icons.folder_rounded;
  }
}

String _assetCapability(LibraryAsset asset) {
  switch (asset.kind) {
    case AssetKind.model:
      return asset.pmxCandidates.isEmpty ? 'No PMX/PMD detected' : '${asset.pmxCandidates.length} PMX/PMD';
    case AssetKind.motion:
    case AssetKind.camera:
    case AssetKind.face:
      return asset.motionCandidates.isEmpty ? 'No VMD/VPD detected' : '${asset.motionCandidates.length} motion files';
    case AssetKind.audio:
      return asset.audioCandidates.isEmpty ? 'No audio detected' : '${asset.audioCandidates.length} audio files';
    case AssetKind.other:
      return '${asset.fileCount} files';
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
