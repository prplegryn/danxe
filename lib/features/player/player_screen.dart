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
  bool _gridVisible = true;
  bool _floorVisible = false;
  _LookSettings _look = _LookSettings.balanced;
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
      _player.setIdle('Open Scene to choose a model.');
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
            builder: (context, constraints) {
              final safe = MediaQuery.paddingOf(context);
              final compact = constraints.maxWidth < 560;
              final short = constraints.maxHeight < 560;
              final side = compact ? 10.0 : 18.0;
              final bottom = safe.bottom + (short ? 8 : 12);

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
                      top: safe.top + (short ? 8 : 12),
                      left: safe.left + side,
                      right: safe.right + side,
                      child: _SceneStatusBar(
                        models: _library.modelSlots,
                        activeModel: _library.activeModelSlot,
                        player: _player,
                        busy: _library.busy,
                        onOpenScene: _showApplySheet,
                      ),
                    ),
                    Positioned(
                      left: safe.left + side,
                      right: safe.right + side,
                      bottom: bottom,
                      child: _WorkspacePanel(
                        compact: compact,
                        player: _player,
                        exporting: _exporting,
                        canExport: _library.modelSlots.any((slot) => slot.hasRenderableModel),
                        hasModels: _library.modelSlots.isNotEmpty,
                        onTogglePlayback: _togglePlayback,
                        onSeek: _seek,
                        onSpeed: _setSpeed,
                        onExport: _showExportSheet,
                        onScene: _showApplySheet,
                        onLibrary: _showLibraryManager,
                        onCamera: _showCameraSheet,
                        onView: _showViewSheet,
                        onLook: _showLookSheet,
                        onEdit: _showModelPlacementSheet,
                        onLog: _showLogSheet,
                        onHide: _hideUi,
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

  void _hideUi() {
    setState(() => _uiHidden = true);
  }

  void _showUi() {
    setState(() => _uiHidden = false);
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
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.90,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                final models = _library.modelSlots;
                final active = _library.activeModelSlot;
                final modelNames = models.map((slot) => slot.model.name).join(', ');
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetHeader(
                        title: 'Scene setup',
                        subtitle: 'Choose what is currently loaded in the viewer.',
                        action: IconButton.filledTonal(
                          tooltip: 'Open library',
                          onPressed: () => _openLibraryFromSheet(context),
                          icon: const Icon(Icons.inventory_2_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _SectionHeading(
                              title: 'Models',
                              caption: models.isEmpty
                                  ? 'Add one or more PMX/PMD models.'
                                  : '${models.length} applied · tap a chip to choose the target.',
                            ),
                            if (models.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _ModelEditTabs(
                                slots: models,
                                activeId: active?.id,
                                onSelected: _library.setActiveModelSlot,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _SceneBindingCard(
                              icon: _iconForKind(AssetKind.model),
                              title: 'Applied models',
                              scope: 'Scene',
                              value: models.isEmpty ? 'No model selected' : modelNames,
                              empty: models.isEmpty,
                              onTap: () => _openPickerFromSheet(context, AssetKind.model),
                              onClear: models.isEmpty
                                  ? null
                                  : () {
                                      _library.clearSelection(AssetKind.model);
                                      _logs.info('apply', 'Removed all models from the scene.');
                                    },
                            ),
                            const SizedBox(height: 20),
                            _SectionHeading(
                              title: 'Model bindings',
                              caption: active == null
                                  ? 'These choices will be assigned to the first model you add.'
                                  : 'Applied only to ${active.model.name}.',
                            ),
                            const SizedBox(height: 10),
                            _AdaptiveCardGrid(
                              children: [
                                _SceneBindingCard(
                                  icon: _iconForKind(AssetKind.motion),
                                  title: 'Motion',
                                  scope: active == null ? 'Next model' : 'Active model',
                                  value: _library.selectedMotion?.name ?? 'Not selected',
                                  empty: _library.selectedMotion == null,
                                  onTap: () => _openPickerFromSheet(context, AssetKind.motion),
                                  onClear: _library.selectedMotion == null
                                      ? null
                                      : () => _library.clearSelection(AssetKind.motion),
                                ),
                                _SceneBindingCard(
                                  icon: _iconForKind(AssetKind.face),
                                  title: 'Face',
                                  scope: active == null ? 'Next model' : 'Active model',
                                  value: _library.selectedFace?.name ?? 'Not selected',
                                  empty: _library.selectedFace == null,
                                  onTap: () => _openPickerFromSheet(context, AssetKind.face),
                                  onClear: _library.selectedFace == null
                                      ? null
                                      : () => _library.clearSelection(AssetKind.face),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const _SectionHeading(
                              title: 'Scene bindings',
                              caption: 'Shared by every model in the scene.',
                            ),
                            const SizedBox(height: 10),
                            _AdaptiveCardGrid(
                              children: [
                                _SceneBindingCard(
                                  icon: _iconForKind(AssetKind.camera),
                                  title: 'Camera',
                                  scope: 'Whole scene',
                                  value: _library.selectedCamera?.name ?? 'Manual camera',
                                  empty: _library.selectedCamera == null,
                                  onTap: () => _openPickerFromSheet(context, AssetKind.camera),
                                  onClear: _library.selectedCamera == null
                                      ? null
                                      : () => _library.clearSelection(AssetKind.camera),
                                ),
                                _SceneBindingCard(
                                  icon: _iconForKind(AssetKind.audio),
                                  title: 'Audio',
                                  scope: 'Whole scene',
                                  value: _library.selectedAudio?.name ?? 'No audio',
                                  empty: _library.selectedAudio == null,
                                  onTap: () => _openPickerFromSheet(context, AssetKind.audio),
                                  onClear: _library.selectedAudio == null
                                      ? null
                                      : () => _library.clearSelection(AssetKind.audio),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _SceneShortcutCard(
                              icon: Icons.playlist_play_rounded,
                              title: 'Dance packages',
                              subtitle: _library.dancePackages.isEmpty
                                  ? 'No packages imported yet'
                                  : '${_library.dancePackages.length} ready to apply',
                              onTap: () {
                                Navigator.of(context).pop();
                                Future.delayed(const Duration(milliseconds: 160), () {
                                  if (mounted) _showDancePackagePicker();
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: models.isEmpty &&
                                      _library.selectedMotion == null &&
                                      _library.selectedCamera == null &&
                                      _library.selectedAudio == null &&
                                      _library.selectedFace == null
                                  ? null
                                  : () {
                                      _library.clearScene();
                                      _logs.info('apply', 'Scene bindings cleared.');
                                      Navigator.of(context).pop();
                                    },
                              icon: const Icon(Icons.layers_clear_rounded),
                              label: const Text('Clear entire scene'),
                            ),
                          ],
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
    var query = '';
    final searchController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.92,
              child: SafeArea(
                top: false,
                child: AnimatedBuilder(
                  animation: _library,
                  builder: (context, _) {
                    final normalizedQuery = query.trim().toLowerCase();
                    final assets = _library.byKind(kind).where((asset) {
                      if (normalizedQuery.isEmpty) return true;
                      return asset.name.toLowerCase().contains(normalizedQuery) ||
                          asset.sourceName.toLowerCase().contains(normalizedQuery);
                    }).toList(growable: false);
                    final selected = _selectedAssetForKind(kind);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SheetHeader(
                            title: 'Choose ${kind.label.toLowerCase()}',
                            subtitle: kind == AssetKind.model
                                ? 'Select multiple models for the scene.'
                                : _assetScopeDescription(kind),
                            action: IconButton.filled(
                              tooltip: 'Import ${kind.label.toLowerCase()}',
                              onPressed: _library.busy ? null : () => _import(kind),
                              icon: _library.busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                if ((kind == AssetKind.motion || kind == AssetKind.face) &&
                                    _library.modelSlots.isNotEmpty) ...[
                                  _TargetModelStrip(
                                    slots: _library.modelSlots,
                                    activeId: _library.activeModelSlot?.id,
                                    onSelected: _library.setActiveModelSlot,
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (kind != AssetKind.model && selected != null) ...[
                                  _SelectedAssetBanner(
                                    asset: selected,
                                    onClear: () => _library.clearSelection(kind),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextField(
                                  controller: searchController,
                                  onChanged: (value) => setSheetState(() => query = value),
                                  decoration: InputDecoration(
                                    hintText: 'Search ${kind.label.toLowerCase()}',
                                    prefixIcon: const Icon(Icons.search_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (assets.isEmpty)
                                  SizedBox(
                                    height: 240,
                                    child: normalizedQuery.isEmpty
                                        ? _EmptyAssets(kind: kind, onImport: () => _import(kind))
                                        : const _EmptySearchResult(),
                                  )
                                else
                                  for (var index = 0; index < assets.length; index++) ...[
                                    if (index > 0) const SizedBox(height: 8),
                                    _AssetRow(
                                      asset: assets[index],
                                      selected: kind == AssetKind.model
                                          ? _library.isModelApplied(assets[index])
                                          : _isSelected(assets[index]),
                                      showCheckbox: kind == AssetKind.model,
                                      onTap: () => _applyAsset(assets[index]),
                                      onEdit: () {
                                        final asset = assets[index];
                                        Navigator.of(context).pop();
                                        Future.delayed(const Duration(milliseconds: 160), () {
                                          if (mounted) _showAssetEditor(asset);
                                        });
                                      },
                                    ),
                                  ],
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Done'),
                                ),
                              ],
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
      },
    );
    searchController.dispose();
  }

  Future<void> _showDancePackagePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                final packages = _library.dancePackages;
                final target = _library.activeModelSlot?.model.name;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetHeader(
                        title: 'Dance packages',
                        subtitle: 'Apply a matched motion, face and audio set in one step.',
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            if (_library.modelSlots.isNotEmpty) ...[
                              const _SectionHeading(
                                title: 'Target model',
                                caption: 'Motion and face go to this model; audio is shared.',
                              ),
                              const SizedBox(height: 8),
                              _ModelEditTabs(
                                slots: _library.modelSlots,
                                activeId: _library.activeModelSlot?.id,
                                onSelected: _library.setActiveModelSlot,
                              ),
                              const SizedBox(height: 12),
                            ] else ...[
                              const _InlineNotice(
                                icon: Icons.info_outline_rounded,
                                text: 'No model is applied. Motion and face will be prepared for the next model.',
                              ),
                              const SizedBox(height: 12),
                            ],
                            const _InlineNotice(
                              icon: Icons.videocam_off_outlined,
                              text: 'Camera files inside a package are detected but are not applied automatically.',
                            ),
                            const SizedBox(height: 12),
                            if (packages.isEmpty)
                              const SizedBox(height: 240, child: _DancePackageEmptyState())
                            else
                              for (var index = 0; index < packages.length; index++) ...[
                                if (index > 0) const SizedBox(height: 8),
                                _DancePackageRow(
                                  bundle: packages[index],
                                  target: target,
                                  onTap: () {
                                    final bundle = packages[index];
                                    _library.applyDancePackage(bundle);
                                    _logs.info(
                                      'apply',
                                      target == null
                                          ? 'Applied dance package ${bundle.name} without camera.'
                                          : 'Applied dance package ${bundle.name} to $target without camera.',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ],
                          ],
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
    var selectedKind = AssetKind.model;
    var query = '';
    final searchController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.94,
              child: SafeArea(
                top: false,
                child: AnimatedBuilder(
                  animation: _library,
                  builder: (context, _) {
                    final normalizedQuery = query.trim().toLowerCase();
                    final assets = _library.byKind(selectedKind).where((asset) {
                      if (normalizedQuery.isEmpty) return true;
                      return asset.name.toLowerCase().contains(normalizedQuery) ||
                          asset.sourceName.toLowerCase().contains(normalizedQuery) ||
                          _assetCapability(asset).toLowerCase().contains(normalizedQuery);
                    }).toList(growable: false);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SheetHeader(
                            title: 'Resource library',
                            subtitle: '${_library.assets.length} imported assets',
                            action: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  tooltip: 'Reload library',
                                  onPressed: _library.busy ? null : () => _library.load(),
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  tooltip: 'Import ${selectedKind.label.toLowerCase()}',
                                  onPressed: _library.busy ? null : () => _import(selectedKind),
                                  icon: _library.busy
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _LibraryCategoryBar(
                                  selected: selectedKind,
                                  counts: {
                                    for (final kind in const [
                                      AssetKind.model,
                                      AssetKind.motion,
                                      AssetKind.camera,
                                      AssetKind.audio,
                                      AssetKind.face,
                                    ])
                                      kind: _library.byKind(kind).length,
                                  },
                                  onSelected: (kind) {
                                    setSheetState(() {
                                      selectedKind = kind;
                                      query = '';
                                      searchController.clear();
                                    });
                                  },
                                ),
                                const SizedBox(height: 12),
                                if ((selectedKind == AssetKind.motion ||
                                        selectedKind == AssetKind.face) &&
                                    _library.modelSlots.isNotEmpty) ...[
                                  _TargetModelStrip(
                                    slots: _library.modelSlots,
                                    activeId: _library.activeModelSlot?.id,
                                    onSelected: _library.setActiveModelSlot,
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextField(
                                  controller: searchController,
                                  onChanged: (value) => setSheetState(() => query = value),
                                  decoration: InputDecoration(
                                    hintText: 'Search ${selectedKind.label.toLowerCase()}',
                                    prefixIcon: const Icon(Icons.search_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (assets.isEmpty)
                                  SizedBox(
                                    height: 240,
                                    child: normalizedQuery.isEmpty
                                        ? _EmptyAssets(
                                            kind: selectedKind,
                                            onImport: () => _import(selectedKind),
                                          )
                                        : const _EmptySearchResult(),
                                  )
                                else
                                  for (var index = 0; index < assets.length; index++) ...[
                                    if (index > 0) const SizedBox(height: 8),
                                    _AssetRow(
                                      asset: assets[index],
                                      selected: _isSelected(assets[index]),
                                      showCheckbox: selectedKind == AssetKind.model,
                                      onTap: () => _applyAsset(assets[index]),
                                      onEdit: () {
                                        final asset = assets[index];
                                        Navigator.of(context).pop();
                                        Future.delayed(const Duration(milliseconds: 160), () {
                                          if (mounted) _showAssetEditor(asset);
                                        });
                                      },
                                    ),
                                  ],
                              ],
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
      },
    );
    searchController.dispose();
  }

  Future<void> _showAssetEditor(LibraryAsset initialAsset) async {
    final nameController = TextEditingController(text: initialAsset.name);
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboard),
            child: FractionallySizedBox(
              heightFactor: 0.82,
              child: SafeArea(
                top: false,
                child: AnimatedBuilder(
                  animation: _library,
                  builder: (context, _) {
                    final asset = _library.assets.firstWhere(
                      (item) => item.id == initialAsset.id,
                      orElse: () => initialAsset,
                    );
                    return ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                      children: [
                        const _SheetHeader(
                          title: 'Asset details',
                          subtitle: 'Rename, rescan or remove this imported resource.',
                        ),
                        const SizedBox(height: 16),
                        _AssetIdentityCard(asset: asset),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            prefixIcon: Icon(Icons.edit_rounded),
                          ),
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: 16),
                        _DetailSurface(
                          children: [
                            _DetailLine(label: 'Type', value: asset.kind.label),
                            _DetailLine(label: 'Files', value: '${asset.fileCount} files'),
                            _DetailLine(label: 'Size', value: _formatBytes(asset.totalBytes)),
                            _DetailLine(label: 'Detected', value: _assetCapability(asset)),
                            _DetailLine(label: 'Source', value: asset.sourceName),
                          ],
                        ),
                        const SizedBox(height: 18),
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
                                    if (context.mounted) Navigator.of(context).pop();
                                    _showMessage('Saved ${updated.name}.');
                                  }
                                },
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Save name'),
                        ),
                        const SizedBox(height: 10),
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
                          label: const Text('Rescan files'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _library.busy
                              ? null
                              : () async {
                                  final confirmed = await _confirmDelete(asset);
                                  if (!confirmed || !context.mounted) return;
                                  await _library.delete(asset);
                                  _logs.warning('library', 'Deleted ${asset.name}.');
                                  if (context.mounted) Navigator.of(context).pop();
                                },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete resource'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
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
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
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
                        subtitle: '${entries.length} recent renderer and library events',
                        action: Wrap(
                          spacing: 8,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Copy log',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _logs.dump()));
                                _logs.info('app', 'Log copied to clipboard.');
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

  Future<void> _showLookSheet() async {
    var draft = _look;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void update(_LookSettings next, {bool log = false}) {
              setSheetState(() => draft = next);
              _setLook(next, log: log);
            }

            return FractionallySizedBox(
              heightFactor: 0.90,
              child: SafeArea(
                top: false,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                  children: [
                    const _SheetHeader(
                      title: 'Look & lighting',
                      subtitle: 'Tune color, contrast and stage lighting without covering the viewer.',
                    ),
                    const SizedBox(height: 16),
                    _SettingsToggleTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Enhanced look',
                      subtitle: 'Apply Danxe color and material tuning.',
                      value: draft.enabled,
                      onChanged: (value) => update(draft.copyWith(enabled: value)),
                    ),
                    const SizedBox(height: 20),
                    const _SectionHeading(
                      title: 'Presets',
                      caption: 'Start with a balanced style, then fine tune below.',
                    ),
                    const SizedBox(height: 10),
                    _LookPresetGrid(
                      look: draft,
                      onSelected: (preset) {
                        update(_LookSettings.forPreset(preset, draft), log: true);
                      },
                    ),
                    const SizedBox(height: 22),
                    const _SectionHeading(
                      title: 'Image',
                      caption: 'Changes are previewed immediately.',
                    ),
                    const SizedBox(height: 10),
                    _LookSettingsSlider(
                      label: 'Exposure',
                      icon: Icons.exposure_rounded,
                      value: draft.exposure,
                      min: 0.70,
                      max: 1.60,
                      onChanged: (value) => update(draft.copyWith(exposure: value)),
                    ),
                    _LookSettingsSlider(
                      label: 'Contrast',
                      icon: Icons.contrast_rounded,
                      value: draft.contrast,
                      min: 0.75,
                      max: 2.00,
                      onChanged: (value) => update(draft.copyWith(contrast: value)),
                    ),
                    _LookSettingsSlider(
                      label: 'Saturation',
                      icon: Icons.palette_rounded,
                      value: draft.saturation,
                      min: 0.50,
                      max: 2.50,
                      onChanged: (value) => update(draft.copyWith(saturation: value)),
                    ),
                    _LookSettingsSlider(
                      label: 'Dehaze',
                      icon: Icons.filter_b_and_w_rounded,
                      value: draft.dehaze,
                      min: 0,
                      max: 0.45,
                      onChanged: (value) => update(draft.copyWith(dehaze: value)),
                    ),
                    _LookSettingsSlider(
                      label: 'Texture',
                      icon: Icons.texture_rounded,
                      value: draft.texture,
                      min: 0.50,
                      max: 2.00,
                      onChanged: (value) => update(draft.copyWith(texture: value)),
                    ),
                    const SizedBox(height: 18),
                    const _SectionHeading(
                      title: 'Lighting',
                      caption: 'Adjust the scene lights independently.',
                    ),
                    const SizedBox(height: 10),
                    _LookSettingsSlider(
                      label: 'Ambient',
                      icon: Icons.light_mode_rounded,
                      value: draft.ambient,
                      min: 0.2,
                      max: 2.4,
                      onChanged: (value) => update(draft.copyWith(ambient: value)),
                    ),
                    _LookSettingsSlider(
                      label: 'Key light',
                      icon: Icons.flashlight_on_rounded,
                      value: draft.key,
                      min: 0.2,
                      max: 3.2,
                      onChanged: (value) => update(draft.copyWith(key: value)),
                    ),
                    _LookSettingsSlider(
                      label: 'Rim light',
                      icon: Icons.flare_rounded,
                      value: draft.rim,
                      min: 0,
                      max: 1.8,
                      onChanged: (value) => update(draft.copyWith(rim: value)),
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

  Future<void> _showViewSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.86,
              child: SafeArea(
                top: false,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                  children: [
                    const _SheetHeader(
                      title: 'Viewer options',
                      subtitle: 'Keep display controls in one predictable place.',
                    ),
                    const SizedBox(height: 16),
                    _SettingsToggleTile(
                      icon: Icons.grid_4x4_rounded,
                      title: 'Grid',
                      subtitle: 'Show the ground reference grid.',
                      value: _gridVisible,
                      onChanged: (_) async {
                        await _toggleGrid();
                        if (context.mounted) setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _SettingsToggleTile(
                      icon: Icons.crop_square_rounded,
                      title: 'Floor',
                      subtitle: 'Use the solid stage floor instead of the grid.',
                      value: _floorVisible,
                      onChanged: (_) async {
                        await _toggleFloor();
                        if (context.mounted) setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 22),
                    _SectionHeading(
                      title: 'Model parts',
                      caption: _modelParts.isEmpty
                          ? 'Part controls appear after a model finishes loading.'
                          : '${_modelParts.length} materials available.',
                    ),
                    const SizedBox(height: 10),
                    if (_modelParts.isEmpty)
                      const _InlineNotice(
                        icon: Icons.layers_outlined,
                        text: 'No model parts are available yet.',
                      )
                    else
                      _PartListSurface(
                        parts: _modelParts,
                        onToggle: (part) {
                          _togglePartVisibility(part);
                          setSheetState(() {});
                        },
                      ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _hideUi();
                      },
                      icon: const Icon(Icons.visibility_off_rounded),
                      label: const Text('Hide all controls'),
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

  Future<void> _showModelPlacementSheet() async {
    if (_library.modelSlots.isEmpty) {
      _showMessage('Apply a model before editing placement.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.90,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _library,
              builder: (context, _) {
                final active = _library.activeModelSlot;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetHeader(
                        title: 'Model placement',
                        subtitle: 'Select a model, then adjust its position in the scene.',
                      ),
                      const SizedBox(height: 12),
                      _ModelEditTabs(
                        slots: _library.modelSlots,
                        activeId: active?.id,
                        onSelected: _library.setActiveModelSlot,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: active == null
                            ? const _EmptySearchResult()
                            : ListView(
                                physics: const BouncingScrollPhysics(),
                                children: [
                                  _ModelNudgePad(
                                    onMove: (x, y, z) => _moveActiveModel(x: x, y: y, z: z),
                                  ),
                                  const SizedBox(height: 12),
                                  _ModelTransformPanel(
                                    slot: active,
                                    onChanged: _setActiveModelTransform,
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
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
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.80,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _player,
              builder: (context, _) {
                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                  children: [
                    _SheetHeader(
                      title: 'Camera controls',
                      subtitle: _library.selectedCamera == null
                          ? 'Manual camera is active.'
                          : 'A camera motion is applied. Manual changes will take control.',
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
                    const SizedBox(height: 18),
                    const _SectionHeading(
                      title: 'Quick framing',
                      caption: 'Frame every model with a consistent front view.',
                    ),
                    const SizedBox(height: 10),
                    _AdaptiveCardGrid(
                      children: [
                        _CameraPresetCard(
                          icon: Icons.accessibility_new_rounded,
                          title: 'Full body',
                          subtitle: 'Front view with the full model in frame',
                          onTap: () => _applyCameraPreset('fullFront'),
                        ),
                        _CameraPresetCard(
                          icon: Icons.portrait_rounded,
                          title: 'Half body',
                          subtitle: 'Closer front portrait framing',
                          onTap: () => _applyCameraPreset('halfFront'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _SectionHeading(
                      title: 'Manual orbit',
                      caption: 'Fine tune the viewing angle and distance.',
                    ),
                    const SizedBox(height: 10),
                    _CameraSlider(
                      label: 'Yaw',
                      value: _player.yaw,
                      min: -180,
                      max: 180,
                      suffix: '°',
                      onChanged: (value) {
                        _player.orbit(yaw: value);
                        _pushCamera();
                      },
                    ),
                    const SizedBox(height: 8),
                    _CameraSlider(
                      label: 'Pitch',
                      value: _player.pitch,
                      min: -80,
                      max: 80,
                      suffix: '°',
                      onChanged: (value) {
                        _player.orbit(pitch: value);
                        _pushCamera();
                      },
                    ),
                    const SizedBox(height: 8),
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
                );
              },
            ),
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
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.86,
              child: SafeArea(
                top: false,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                  children: [
                    const _SheetHeader(
                      title: 'Export video',
                      subtitle: 'Record the current scene to Download/danxe.',
                    ),
                    const SizedBox(height: 16),
                    const _InlineNotice(
                      icon: Icons.schedule_rounded,
                      text: 'Recording runs in real time. Keep Danxe open until the export finishes.',
                    ),
                    const SizedBox(height: 16),
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
                    FilledButton.icon(
                      onPressed: _exporting
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(this.context);
                              setState(() => _exporting = true);
                              setSheetState(() {});
                              _logs.info('export', 'Started ${settings.width}x${settings.height} ${settings.fps}fps.');
                              try {
                                final job = await _export.exportVideo(
                                  settings: settings,
                                  model: model,
                                  motion: _library.selectedMotion,
                                  camera: _library.selectedCamera,
                                  audio: _library.selectedAudio,
                                );
                                if (context.mounted) Navigator.of(context).pop();
                                _logs.info('export', 'Video exported to ${job.path}.');
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Video exported: ${job.path}')),
                                );
                              } catch (error) {
                                if (mounted) setState(() => _exporting = false);
                                if (context.mounted) setSheetState(() {});
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

  LibraryAsset? _selectedAssetForKind(AssetKind kind) {
    switch (kind) {
      case AssetKind.model:
        return _library.selectedModel;
      case AssetKind.motion:
        return _library.selectedMotion;
      case AssetKind.camera:
        return _library.selectedCamera;
      case AssetKind.audio:
        return _library.selectedAudio;
      case AssetKind.face:
        return _library.selectedFace;
      case AssetKind.other:
        return null;
    }
  }

  String _assetScopeDescription(AssetKind kind) {
    switch (kind) {
      case AssetKind.motion:
      case AssetKind.face:
        final target = _library.activeModelSlot?.model.name;
        return target == null
            ? 'Prepared for the next model you add.'
            : 'Applied to $target.';
      case AssetKind.camera:
      case AssetKind.audio:
        return 'Applied to the whole scene.';
      case AssetKind.model:
        return 'Applied to the scene.';
      case AssetKind.other:
        return 'Imported resource.';
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

class _SceneStatusBar extends StatelessWidget {
  const _SceneStatusBar({
    required this.models,
    required this.activeModel,
    required this.player,
    required this.busy,
    required this.onOpenScene,
  });

  final List<AppliedModelSlot> models;
  final AppliedModelSlot? activeModel;
  final PlayerController player;
  final bool busy;
  final VoidCallback onOpenScene;

  @override
  Widget build(BuildContext context) {
    final title = models.isEmpty
        ? 'Build your scene'
        : models.length == 1
            ? models.first.model.name
            : '${models.length} models · ${activeModel?.model.name ?? models.first.model.name}';
    final status = player.error ??
        player.message ??
        (player.loaded
            ? player.playing
                ? 'Playing · ${player.timeLabel}'
                : 'Ready · ${player.timeLabel}'
            : 'Choose assets to begin');
    final color = player.error != null
        ? AppColors.danger
        : player.loaded
            ? AppColors.success
            : AppColors.textMuted;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _Panel(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              onTap: onOpenScene,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primary, AppColors.secondary],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.view_in_ar_rounded, size: 21),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: player.error == null ? AppColors.textMuted : AppColors.danger,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (busy || player.loading)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    const SizedBox(width: 7),
                    const Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({
    required this.compact,
    required this.player,
    required this.exporting,
    required this.canExport,
    required this.hasModels,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onSpeed,
    required this.onExport,
    required this.onScene,
    required this.onLibrary,
    required this.onCamera,
    required this.onView,
    required this.onLook,
    required this.onEdit,
    required this.onLog,
    required this.onHide,
  });

  final bool compact;
  final PlayerController player;
  final bool exporting;
  final bool canExport;
  final bool hasModels;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeed;
  final VoidCallback onExport;
  final VoidCallback onScene;
  final VoidCallback onLibrary;
  final VoidCallback onCamera;
  final VoidCallback onView;
  final VoidCallback onLook;
  final VoidCallback onEdit;
  final VoidCallback onLog;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _Panel(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TransportControls(
                compact: compact,
                player: player,
                exporting: exporting,
                canExport: canExport,
                onToggle: onTogglePlayback,
                onSeek: onSeek,
                onSpeed: onSpeed,
                onExport: onExport,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Divider(height: 1),
              ),
              _WorkspaceToolBar(
                hasModels: hasModels,
                onScene: onScene,
                onLibrary: onLibrary,
                onCamera: onCamera,
                onView: onView,
                onLook: onLook,
                onEdit: onEdit,
                onLog: onLog,
                onHide: onHide,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
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
    final duration = player.duration <= 0 ? 1.0 : player.duration;
    final position = player.duration <= 0
        ? 0.0
        : player.position.clamp(0, player.duration).toDouble();
    final playButton = IconButton.filled(
      tooltip: player.playing ? 'Pause' : 'Play',
      onPressed: player.loaded ? onToggle : null,
      icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );
    final speedButton = _SpeedCycleButton(
      speed: player.speed,
      enabled: player.loaded,
      onSelected: onSpeed,
    );
    final exportButton = IconButton.filledTonal(
      tooltip: 'Export video',
      onPressed: canExport && player.loaded && !exporting ? onExport : null,
      icon: exporting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.file_download_rounded),
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              playButton,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  player.timeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              speedButton,
              const SizedBox(width: 6),
              exportButton,
            ],
          ),
          SizedBox(
            height: 30,
            child: Slider(
              min: 0,
              max: duration,
              value: position,
              onChanged: player.loaded ? onSeek : null,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        playButton,
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: Text(
            player.timeLabel,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: duration,
            value: position,
            onChanged: player.loaded ? onSeek : null,
          ),
        ),
        speedButton,
        const SizedBox(width: 6),
        exportButton,
      ],
    );
  }
}

class _SpeedCycleButton extends StatelessWidget {
  const _SpeedCycleButton({
    required this.speed,
    required this.enabled,
    required this.onSelected,
  });

  final double speed;
  final bool enabled;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    const values = [0.5, 1.0, 1.5, 2.0];
    final current = values.indexWhere((value) => (value - speed).abs() < 0.01);
    final next = values[(current < 0 ? 0 : current + 1) % values.length];
    final label = '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 1)}x';
    return SizedBox(
      width: 54,
      height: 44,
      child: TextButton(
        onPressed: enabled ? () => onSelected(next) : null,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.small),
            side: const BorderSide(color: AppColors.line),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _WorkspaceToolBar extends StatelessWidget {
  const _WorkspaceToolBar({
    required this.hasModels,
    required this.onScene,
    required this.onLibrary,
    required this.onCamera,
    required this.onView,
    required this.onLook,
    required this.onEdit,
    required this.onLog,
    required this.onHide,
  });

  final bool hasModels;
  final VoidCallback onScene;
  final VoidCallback onLibrary;
  final VoidCallback onCamera;
  final VoidCallback onView;
  final VoidCallback onLook;
  final VoidCallback onEdit;
  final VoidCallback onLog;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _WorkspaceToolButton(
            icon: Icons.layers_rounded,
            label: 'Scene',
            emphasized: true,
            onPressed: onScene,
          ),
          _WorkspaceToolButton(
            icon: Icons.inventory_2_rounded,
            label: 'Library',
            onPressed: onLibrary,
          ),
          _WorkspaceToolButton(
            icon: Icons.video_camera_front_rounded,
            label: 'Camera',
            onPressed: onCamera,
          ),
          _WorkspaceToolButton(
            icon: Icons.visibility_rounded,
            label: 'View',
            onPressed: onView,
          ),
          _WorkspaceToolButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Look',
            onPressed: onLook,
          ),
          _WorkspaceToolButton(
            icon: Icons.open_with_rounded,
            label: 'Place',
            onPressed: hasModels ? onEdit : null,
          ),
          _WorkspaceToolButton(
            icon: Icons.receipt_long_rounded,
            label: 'Logs',
            onPressed: onLog,
          ),
          _WorkspaceToolButton(
            icon: Icons.visibility_off_rounded,
            label: 'Hide',
            onPressed: onHide,
          ),
        ],
      ),
    );
  }
}

class _WorkspaceToolButton extends StatelessWidget {
  const _WorkspaceToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: emphasized
            ? AppColors.primary.withOpacity(enabled ? 0.28 : 0.12)
            : AppColors.surfaceHigh.withOpacity(enabled ? 0.74 : 0.36),
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 66),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: enabled ? AppColors.text : AppColors.textMuted.withOpacity(0.45),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: enabled ? AppColors.text : AppColors.textMuted.withOpacity(0.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: slots.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final slot = slots[index];
          return _ModelEditTab(
            slot: slot,
            selected: slot.id == activeId,
            onPressed: () => onSelected(slot.id),
          );
        },
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
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 210),
      child: Material(
        color: selected ? AppColors.primary.withOpacity(0.34) : AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                if (slot.motion != null || slot.face != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  clamped.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _NudgeButton(
                tooltip: '$label -0.1',
                icon: Icons.remove_rounded,
                onPressed: () => onNudge(-0.1),
              ),
              const SizedBox(width: 6),
              _NudgeButton(
                tooltip: '$label +0.1',
                icon: Icons.add_rounded,
                onPressed: () => onNudge(0.1),
              ),
            ],
          ),
          SizedBox(
            height: 34,
            child: Slider(
              min: min,
              max: max,
              value: clamped,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _AdaptiveCardGrid extends StatelessWidget {
  const _AdaptiveCardGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final width = columns == 2
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _SceneBindingCard extends StatelessWidget {
  const _SceneBindingCard({
    required this.icon,
    required this.title,
    required this.scope,
    required this.value,
    required this.empty,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String title;
  final String scope;
  final String value;
  final bool empty;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.text),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _ScopeBadge(label: scope),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: empty ? AppColors.textMuted : AppColors.text,
                fontSize: 13,
                height: 1.3,
                fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onClear != null)
                  TextButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
                TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(empty ? 'Choose' : 'Replace'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.46),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SceneShortcutCard extends StatelessWidget {
  const _SceneShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withOpacity(0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: BorderSide(color: AppColors.primary.withOpacity(0.46)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedAssetBanner extends StatelessWidget {
  const _SelectedAssetBanner({required this.asset, required this.onClear});

  final LibraryAsset asset;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.success.withOpacity(0.34)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 19, color: AppColors.success),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              asset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 42, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text('No matching resources.', style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _DancePackageEmptyState extends StatelessWidget {
  const _DancePackageEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_play_rounded, size: 46, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'No dance packages yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6),
            Text(
              'Import a ZIP containing motion, face or audio files from the library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCategoryBar extends StatelessWidget {
  const _LibraryCategoryBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final AssetKind selected;
  final Map<AssetKind, int> counts;
  final ValueChanged<AssetKind> onSelected;

  @override
  Widget build(BuildContext context) {
    const kinds = [
      AssetKind.model,
      AssetKind.motion,
      AssetKind.camera,
      AssetKind.audio,
      AssetKind.face,
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: kinds.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final kind = kinds[index];
          return FilterChip(
            selected: selected == kind,
            onSelected: (_) => onSelected(kind),
            avatar: Icon(_iconForKind(kind), size: 17),
            label: Text('${kind.label} ${counts[kind] ?? 0}'),
          );
        },
      ),
    );
  }
}

class _TargetModelStrip extends StatelessWidget {
  const _TargetModelStrip({
    required this.slots,
    required this.activeId,
    required this.onSelected,
  });

  final List<AppliedModelSlot> slots;
  final String? activeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.primary.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apply to model',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _ModelEditTabs(slots: slots, activeId: activeId, onSelected: onSelected),
        ],
      ),
    );
  }
}

class _AssetIdentityCard extends StatelessWidget {
  const _AssetIdentityCard({required this.asset});

  final LibraryAsset asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.22),
            AppColors.surfaceHigh,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.42),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_iconForKind(asset.kind)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _assetCapability(asset),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSurface extends StatelessWidget {
  const _DetailSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  const _SettingsToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.line),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
        secondary: Icon(icon, color: value ? AppColors.accent : AppColors.textMuted),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}

class _LookPresetGrid extends StatelessWidget {
  const _LookPresetGrid({required this.look, required this.onSelected});

  final _LookSettings look;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const presets = [
      ('balanced', 'Balanced', Icons.tonality_rounded),
      ('clear', 'Clear', Icons.wb_sunny_rounded),
      ('vivid', 'Vivid', Icons.palette_rounded),
      ('stage', 'Stage', Icons.flare_rounded),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 360 ? 2 : 1;
        final width = columns == 2
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in presets)
              SizedBox(
                width: width,
                child: _LookPresetChoice(
                  icon: preset.$3,
                  label: preset.$2,
                  selected: look.preset == preset.$1,
                  onTap: () => onSelected(preset.$1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LookPresetChoice extends StatelessWidget {
  const _LookPresetChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withOpacity(0.30) : AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 9),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (selected) const Icon(Icons.check_rounded, size: 18, color: AppColors.success),
            ],
          ),
        ),
      ),
    );
  }
}

class _LookSettingsSlider extends StatelessWidget {
  const _LookSettingsSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 9),
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(
                  clamped.toStringAsFixed(2),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 34,
              child: Slider(min: min, max: max, value: clamped, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartListSurface extends StatelessWidget {
  const _PartListSurface({required this.parts, required this.onToggle});

  final List<ViewerPart> parts;
  final ValueChanged<ViewerPart> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < parts.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                parts[index].name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              value: parts[index].visible,
              onChanged: (_) => onToggle(parts[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelNudgePad extends StatelessWidget {
  const _ModelNudgePad({required this.onMove});

  final void Function(double x, double y, double z) onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick nudge', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Move by 0.1 units. Use the sliders below for larger changes.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AxisNudgeButton(label: 'X −', color: AppColors.danger, onTap: () => onMove(-0.1, 0, 0)),
              _AxisNudgeButton(label: 'X +', color: AppColors.danger, onTap: () => onMove(0.1, 0, 0)),
              _AxisNudgeButton(label: 'Y −', color: AppColors.success, onTap: () => onMove(0, -0.1, 0)),
              _AxisNudgeButton(label: 'Y +', color: AppColors.success, onTap: () => onMove(0, 0.1, 0)),
              _AxisNudgeButton(label: 'Z −', color: AppColors.accent, onTap: () => onMove(0, 0, -0.1)),
              _AxisNudgeButton(label: 'Z +', color: AppColors.accent, onTap: () => onMove(0, 0, 0.1)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AxisNudgeButton extends StatelessWidget {
  const _AxisNudgeButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.42)),
        minimumSize: const Size(72, 42),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          backgroundColor: AppColors.background.withOpacity(0.36),
        ),
        icon: Icon(icon, size: 17),
      ),
    );
  }
}

class _CameraPresetCard extends StatelessWidget {
  const _CameraPresetCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.3),
                    ),
                  ],
                ),
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
      color: selected ? AppColors.primary.withOpacity(0.16) : AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: BorderSide(
          color: selected ? AppColors.primary.withOpacity(0.72) : AppColors.line,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.background.withOpacity(0.38),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_iconForKind(asset.kind), size: 22),
                  ),
                  if (selected)
                    const Positioned(
                      right: -3,
                      bottom: -3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.check_rounded, size: 12, color: AppColors.background),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, height: 1.25),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _AssetMetaBadge(label: _assetCapability(asset)),
                        _AssetMetaBadge(label: '${asset.fileCount} files'),
                        _AssetMetaBadge(label: _formatBytes(asset.totalBytes)),
                        if (selected)
                          _AssetMetaBadge(
                            label: showCheckbox ? 'In scene' : 'Applied',
                            accent: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Resource details',
                onPressed: onEdit,
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetMetaBadge extends StatelessWidget {
  const _AssetMetaBadge({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.success.withOpacity(0.12)
            : AppColors.background.withOpacity(0.34),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? AppColors.success : AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DancePackageRow extends StatelessWidget {
  const _DancePackageRow({
    required this.bundle,
    required this.target,
    required this.onTap,
  });

  final DanceAssetPackage bundle;
  final String? target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.playlist_play_rounded, size: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    bundle.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.25),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (bundle.motion != null) const _PackageBadge(label: 'Motion'),
                if (bundle.face != null) const _PackageBadge(label: 'Face'),
                if (bundle.audio != null) const _PackageBadge(label: 'Audio'),
                if (bundle.camera != null)
                  const _PackageBadge(label: 'Camera ignored', warning: true),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              target == null
                  ? 'Motion and face will be prepared for the next model.'
                  : 'Motion and face → $target · Audio → scene',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: bundle.canApply ? onTap : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(target == null ? 'Prepare package' : 'Apply package'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageBadge extends StatelessWidget {
  const _PackageBadge({required this.label, this.warning = false});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? Colors.amberAccent : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
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
  const _SheetHeader({required this.title, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.35,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 10),
          action!,
        ],
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
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(
                '${clamped.toStringAsFixed(1)}$suffix',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(
            height: 36,
            child: Slider(min: min, max: max, value: clamped, onChanged: onChanged),
          ),
        ],
      ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options.toSet())
                ChoiceChip(
                  label: Text(labels?[option] ?? option),
                  selected: option == value,
                  onSelected: (_) => onSelected(option),
                ),
            ],
          ),
        ],
      ),
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
        color: AppColors.surface.withOpacity(0.94),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 28,
            offset: const Offset(0, 12),
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
