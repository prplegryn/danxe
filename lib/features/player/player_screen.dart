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
    exposure: 0.98,
    contrast: 1.18,
    saturation: 1.20,
    brightness: 1.0,
    dehaze: 0.07,
    ambient: 0.92,
    key: 1.34,
    rim: 0.24,
    specular: 0.48,
    shininess: 32,
    toon: 1.0,
    texture: 1.16,
    floor: true,
  );

  static const clear = _LookSettings(
    preset: 'clear',
    enabled: true,
    exposure: 1.0,
    contrast: 1.22,
    saturation: 1.14,
    brightness: 1.02,
    dehaze: 0.08,
    ambient: 0.98,
    key: 1.42,
    rim: 0.20,
    specular: 0.44,
    shininess: 30,
    toon: 1.0,
    texture: 1.18,
    floor: true,
  );

  static const vivid = _LookSettings(
    preset: 'vivid',
    enabled: true,
    exposure: 1.0,
    contrast: 1.34,
    saturation: 1.52,
    brightness: 1.0,
    dehaze: 0.13,
    ambient: 0.84,
    key: 1.48,
    rim: 0.34,
    specular: 0.58,
    shininess: 40,
    toon: 1.06,
    texture: 1.38,
    floor: true,
  );

  static const stage = _LookSettings(
    preset: 'stage',
    enabled: true,
    exposure: 1.02,
    contrast: 1.30,
    saturation: 1.30,
    brightness: 1.0,
    dehaze: 0.11,
    ambient: 0.70,
    key: 1.68,
    rim: 0.62,
    specular: 0.68,
    shininess: 46,
    toon: 1.04,
    texture: 1.26,
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

enum _FloatingPanelKind {
  scene,
  library,
  camera,
  view,
  look,
  placement,
  export,
  logs,
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
  _FloatingPanelKind? _activePanel;
  AssetKind _libraryKind = AssetKind.model;
  String _libraryQuery = '';
  LibraryAsset? _libraryDetail;
  String _assetDraftName = '';
  String? _pendingDeleteAssetId;
  ExportSettings _exportSettings = const ExportSettings();
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
      animation: Listenable.merge([_library, _player, _logs]),
      builder: (context, _) {
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final safe = MediaQuery.paddingOf(context);
              final keyboard = MediaQuery.viewInsetsOf(context).bottom;
              final landscape = constraints.maxWidth >= 640 &&
                  constraints.maxWidth > constraints.maxHeight;
              final edge = landscape ? 10.0 : 12.0;
              final safeContentWidth = constraints.maxWidth - safe.left - safe.right;
              final portraitPanelWidth = constraints.maxWidth -
                  safe.left -
                  safe.right -
                  edge -
                  68;
              final panelWidth = landscape
                  ? (safeContentWidth * 0.38).clamp(268.0, 300.0).toDouble()
                  : (portraitPanelWidth > 320 ? 320.0 : portraitPanelWidth);
              final portraitAvailableHeight = constraints.maxHeight -
                  safe.top -
                  safe.bottom -
                  keyboard -
                  156;
              final desiredPortraitPanelHeight = switch (_activePanel) {
                _FloatingPanelKind.camera => 330.0,
                _FloatingPanelKind.view => 360.0,
                _FloatingPanelKind.logs => 330.0,
                _FloatingPanelKind.export => 390.0,
                _ => 400.0,
              };
              final portraitPanelHeight =
                  portraitAvailableHeight < desiredPortraitPanelHeight
                      ? portraitAvailableHeight
                      : desiredPortraitPanelHeight;
              final landscapePanelHeight = constraints.maxHeight -
                  safe.top -
                  safe.bottom -
                  70;
              final panelHeight = landscape
                  ? landscapePanelHeight
                  : portraitPanelHeight;
              final landscapeTransportSpace = safeContentWidth - panelWidth - 40;
              final transportWidth = landscape
                  ? (landscapeTransportSpace > 450
                      ? 450.0
                      : landscapeTransportSpace)
                  : safeContentWidth - edge * 2;
              final landscapeStatusSpace = safeContentWidth - 342;
              final statusWidth = landscape
                  ? landscapeStatusSpace.clamp(140.0, 250.0).toDouble()
                  : (safeContentWidth - edge > 276
                      ? 276.0
                      : safeContentWidth - edge);
              final verticalRailSpace = constraints.maxHeight -
                  safe.top -
                  safe.bottom -
                  140;
              final verticalRailExtent = verticalRailSpace > 312
                  ? 312.0
                  : verticalRailSpace;

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
                      top: safe.top + (landscape ? 9 : 12),
                      left: safe.left + edge,
                      child: _FloatingSceneChip(
                        models: _library.modelSlots,
                        activeModel: _library.activeModelSlot,
                        player: _player,
                        busy: _library.busy,
                        maxWidth: statusWidth,
                        onPressed: () => _toggleFloatingPanel(_FloatingPanelKind.scene),
                        onHide: _hideUi,
                      ),
                    ),
                    if (_activePanel != null && panelWidth > 0 && panelHeight > 0)
                      Positioned(
                        key: ValueKey(_activePanel),
                        left: landscape ? null : safe.left + edge,
                        right: landscape ? safe.right + edge : null,
                        top: landscape ? safe.top + 60 : null,
                        bottom: landscape
                            ? safe.bottom + 10
                            : safe.bottom + keyboard + 76,
                        width: panelWidth,
                        height: panelHeight,
                        child: _FloatingInspector(
                          kind: _activePanel!,
                          onClose: _closeFloatingPanel,
                          child: _buildFloatingPanel(_activePanel!),
                        ),
                      ),
                    if (transportWidth > 0)
                      Positioned(
                        left: safe.left + edge,
                        bottom: safe.bottom + 10,
                        width: transportWidth,
                        child: _FloatingTransportBar(
                          player: _player,
                          exporting: _exporting,
                          onToggle: _togglePlayback,
                          onSeek: _seek,
                          onSpeed: _setSpeed,
                        ),
                      ),
                    if (landscape || verticalRailExtent >= 40)
                      Positioned(
                        top: landscape ? safe.top + 9 : safe.top + 68,
                        right: safe.right + edge,
                        child: _FloatingToolRail(
                          horizontal: landscape,
                          maxExtent: landscape ? null : verticalRailExtent,
                          active: _activePanel,
                          hasModels: _library.modelSlots.isNotEmpty,
                          canExport: _library.modelSlots.any((slot) => slot.hasRenderableModel),
                          onSelected: _toggleFloatingPanel,
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

  void _toggleFloatingPanel(_FloatingPanelKind kind) {
    if (kind == _FloatingPanelKind.placement && _library.modelSlots.isEmpty) {
      _showMessage('Apply a model before editing placement.');
      return;
    }
    if (kind == _FloatingPanelKind.export &&
        !_library.modelSlots.any((slot) => slot.hasRenderableModel)) {
      _showMessage('Apply a renderable model before exporting.');
      return;
    }
    setState(() {
      if (_activePanel == kind) {
        _activePanel = null;
        return;
      }
      _activePanel = kind;
      _pendingDeleteAssetId = null;
      if (kind == _FloatingPanelKind.export) {
        _exportSettings = ExportSettings(
          durationSeconds: _player.duration > 0
              ? _player.duration.round().clamp(1, 600).toInt()
              : 10,
        );
      }
    });
  }

  void _closeFloatingPanel() {
    setState(() {
      _activePanel = null;
      _libraryDetail = null;
      _pendingDeleteAssetId = null;
    });
  }

  void _openLibraryPanel(AssetKind kind) {
    setState(() {
      _activePanel = _FloatingPanelKind.library;
      _libraryKind = kind;
      _libraryQuery = '';
      _libraryDetail = null;
      _pendingDeleteAssetId = null;
    });
  }

  void _openLibraryDetail(LibraryAsset asset) {
    setState(() {
      _libraryDetail = asset;
      _assetDraftName = asset.name;
      _pendingDeleteAssetId = null;
    });
  }

  Widget _buildFloatingPanel(_FloatingPanelKind kind) {
    return switch (kind) {
      _FloatingPanelKind.scene => _buildScenePanel(),
      _FloatingPanelKind.library => _buildLibraryPanel(),
      _FloatingPanelKind.camera => _buildCameraPanel(),
      _FloatingPanelKind.view => _buildViewPanel(),
      _FloatingPanelKind.look => _buildLookPanel(),
      _FloatingPanelKind.placement => _buildPlacementPanel(),
      _FloatingPanelKind.export => _buildExportPanel(),
      _FloatingPanelKind.logs => _buildLogsPanel(),
    };
  }

  Widget _buildScenePanel() {
    final models = _library.modelSlots;
    final active = _library.activeModelSlot;
    final packages = _library.dancePackages;
    final modelValue = models.isEmpty
        ? 'Not selected'
        : models.map((slot) => slot.model.name).join(', ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (models.length > 1) ...[
          const _InspectorSectionLabel('Target model'),
          const SizedBox(height: 7),
          _ModelEditTabs(
            slots: models,
            activeId: active?.id,
            onSelected: _library.setActiveModelSlot,
          ),
          const SizedBox(height: 10),
        ],
        _InspectorBindingRow(
          icon: _iconForKind(AssetKind.model),
          label: 'Models',
          value: modelValue,
          active: models.isNotEmpty,
          onPressed: () => _openLibraryPanel(AssetKind.model),
          onClear: models.isEmpty
              ? null
              : () => _library.clearSelection(AssetKind.model),
        ),
        _InspectorBindingRow(
          icon: _iconForKind(AssetKind.motion),
          label: 'Motion',
          value: _library.selectedMotion?.name ?? 'Not selected',
          active: _library.selectedMotion != null,
          onPressed: () => _openLibraryPanel(AssetKind.motion),
          onClear: _library.selectedMotion == null
              ? null
              : () => _library.clearSelection(AssetKind.motion),
        ),
        _InspectorBindingRow(
          icon: _iconForKind(AssetKind.face),
          label: 'Face',
          value: _library.selectedFace?.name ?? 'Not selected',
          active: _library.selectedFace != null,
          onPressed: () => _openLibraryPanel(AssetKind.face),
          onClear: _library.selectedFace == null
              ? null
              : () => _library.clearSelection(AssetKind.face),
        ),
        _InspectorBindingRow(
          icon: _iconForKind(AssetKind.camera),
          label: 'Camera',
          value: _library.selectedCamera?.name ?? 'Manual camera',
          active: _library.selectedCamera != null,
          onPressed: () => _openLibraryPanel(AssetKind.camera),
          onClear: _library.selectedCamera == null
              ? null
              : () => _library.clearSelection(AssetKind.camera),
        ),
        _InspectorBindingRow(
          icon: _iconForKind(AssetKind.audio),
          label: 'Audio',
          value: _library.selectedAudio?.name ?? 'No audio',
          active: _library.selectedAudio != null,
          onPressed: () => _openLibraryPanel(AssetKind.audio),
          onClear: _library.selectedAudio == null
              ? null
              : () => _library.clearSelection(AssetKind.audio),
        ),
        if (packages.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _InspectorSectionLabel('Dance packages'),
          const SizedBox(height: 7),
          for (final bundle in packages)
            _InspectorPackageRow(
              bundle: bundle,
              onPressed: () {
                _library.applyDancePackage(bundle);
                _logs.info('apply', 'Applied dance package ${bundle.name}.');
              },
            ),
        ],
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: models.isEmpty &&
                  _library.selectedMotion == null &&
                  _library.selectedCamera == null &&
                  _library.selectedAudio == null &&
                  _library.selectedFace == null
              ? null
              : () {
                  _library.clearScene();
                  _logs.info('apply', 'Scene bindings cleared.');
                },
          icon: const Icon(Icons.layers_clear_outlined, size: 18),
          label: const Text('Clear scene'),
        ),
      ],
    );
  }

  Widget _buildLibraryPanel() {
    final detail = _currentLibraryDetail();
    if (_libraryDetail != null) {
      return _buildLibraryDetailPanel(detail);
    }
    final normalizedQuery = _libraryQuery.trim().toLowerCase();
    final assets = _library.byKind(_libraryKind).where((asset) {
      if (normalizedQuery.isEmpty) return true;
      return asset.name.toLowerCase().contains(normalizedQuery) ||
          asset.sourceName.toLowerCase().contains(normalizedQuery) ||
          _assetCapability(asset).toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);
    const kinds = [
      AssetKind.model,
      AssetKind.motion,
      AssetKind.camera,
      AssetKind.audio,
      AssetKind.face,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_library.assets.length} imported resources',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
            _TinyActionButton(
              tooltip: 'Reload library',
              icon: Icons.refresh_rounded,
              onPressed: _library.busy ? null : _library.load,
            ),
            const SizedBox(width: 5),
            _TinyActionButton(
              tooltip: 'Import ${_libraryKind.label.toLowerCase()}',
              icon: Icons.add_rounded,
              emphasized: true,
              onPressed: _library.busy ? null : () => _import(_libraryKind),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kinds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 5),
            itemBuilder: (context, index) {
              final kind = kinds[index];
              return _LibraryKindButton(
                kind: kind,
                count: _library.byKind(kind).length,
                selected: kind == _libraryKind,
                onPressed: () {
                  setState(() {
                    _libraryKind = kind;
                    _libraryQuery = '';
                    _pendingDeleteAssetId = null;
                  });
                },
              );
            },
          ),
        ),
        if ((_libraryKind == AssetKind.motion || _libraryKind == AssetKind.face) &&
            _library.modelSlots.length > 1) ...[
          const SizedBox(height: 9),
          _ModelEditTabs(
            slots: _library.modelSlots,
            activeId: _library.activeModelSlot?.id,
            onSelected: _library.setActiveModelSlot,
          ),
        ],
        const SizedBox(height: 9),
        TextFormField(
          key: ValueKey(_libraryKind),
          initialValue: _libraryQuery,
          onChanged: (value) => setState(() => _libraryQuery = value),
          decoration: InputDecoration(
            hintText: 'Search ${_libraryKind.label.toLowerCase()}',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            isDense: true,
          ),
        ),
        const SizedBox(height: 9),
        if (assets.isEmpty)
          _InspectorEmpty(
            icon: normalizedQuery.isEmpty
                ? _iconForKind(_libraryKind)
                : Icons.search_off_rounded,
            message: normalizedQuery.isEmpty
                ? 'No ${_libraryKind.label.toLowerCase()} imported yet.'
                : 'No matching resources.',
            actionLabel: normalizedQuery.isEmpty ? 'Import' : null,
            onAction: normalizedQuery.isEmpty ? () => _import(_libraryKind) : null,
          )
        else
          for (final asset in assets)
            _InspectorAssetRow(
              asset: asset,
              selected: _isSelected(asset),
              onPressed: () => _applyAsset(asset),
              onDetails: () => _openLibraryDetail(asset),
            ),
      ],
    );
  }

  LibraryAsset? _currentLibraryDetail() {
    final current = _libraryDetail;
    if (current == null) return null;
    for (final asset in _library.assets) {
      if (asset.id == current.id) return asset;
    }
    return null;
  }

  Widget _buildLibraryDetailPanel(LibraryAsset? asset) {
    if (asset == null) {
      return _InspectorEmpty(
        icon: Icons.folder_off_outlined,
        message: 'This resource is no longer in the library.',
        actionLabel: 'Back',
        onAction: () => setState(() => _libraryDetail = null),
      );
    }
    final confirmingDelete = _pendingDeleteAssetId == asset.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _libraryDetail = null;
                _pendingDeleteAssetId = null;
              });
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Library'),
          ),
        ),
        const SizedBox(height: 4),
        _CompactResourceIdentity(asset: asset),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('${asset.id}:${asset.name}'),
          initialValue: _assetDraftName,
          onChanged: (value) => _assetDraftName = value,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Display name',
            prefixIcon: Icon(Icons.edit_outlined, size: 19),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        _CompactMetadata(asset: asset),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _library.busy
              ? null
              : () async {
                  final updated = await _library.rename(asset, _assetDraftName);
                  if (!mounted || updated == null) return;
                  setState(() {
                    _libraryDetail = updated;
                    _assetDraftName = updated.name;
                  });
                  _logs.info('library', 'Renamed ${asset.name} to ${updated.name}.');
                },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save name'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: _library.busy
              ? null
              : () async {
                  final updated = await _library.rescan(asset);
                  if (!mounted || updated == null) return;
                  setState(() {
                    _libraryDetail = updated;
                    _assetDraftName = updated.name;
                  });
                  _logs.info('library', 'Rescanned ${updated.name}.');
                },
          icon: const Icon(Icons.manage_search_rounded, size: 18),
          label: const Text('Rescan files'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: _library.busy
              ? null
              : () async {
                  if (!confirmingDelete) {
                    setState(() => _pendingDeleteAssetId = asset.id);
                    return;
                  }
                  await _library.delete(asset);
                  if (!mounted) return;
                  setState(() {
                    _libraryDetail = null;
                    _pendingDeleteAssetId = null;
                  });
                  _logs.warning('library', 'Deleted ${asset.name}.');
                },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(
              color: AppColors.danger.withOpacity(confirmingDelete ? 0.92 : 0.48),
            ),
          ),
          icon: Icon(
            confirmingDelete ? Icons.warning_amber_rounded : Icons.delete_outline_rounded,
            size: 18,
          ),
          label: Text(confirmingDelete ? 'Tap again to delete' : 'Delete resource'),
        ),
      ],
    );
  }

  Widget _buildCameraPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      children: [
        if (_library.selectedCamera != null) ...[
          const _CompactNotice(
            icon: Icons.movie_filter_outlined,
            text: 'A camera motion is active. Manual changes take control immediately.',
          ),
          const SizedBox(height: 9),
        ],
        Row(
          children: [
            Expanded(
              child: _CompactActionTile(
                icon: Icons.accessibility_new_rounded,
                label: 'Full body',
                onPressed: () => _applyCameraPreset('fullFront'),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _CompactActionTile(
                icon: Icons.portrait_rounded,
                label: 'Half body',
                onPressed: () => _applyCameraPreset('halfFront'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: _InspectorSectionLabel('Manual orbit')),
            _TinyActionButton(
              tooltip: 'Reset camera',
              icon: Icons.center_focus_strong_rounded,
              onPressed: () {
                _player.resetCamera();
                _pushCamera();
                _logs.info('camera', 'Camera reset.');
              },
            ),
          ],
        ),
        const SizedBox(height: 7),
        _CompactValueSlider(
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
        _CompactValueSlider(
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
        _CompactValueSlider(
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
  }

  Widget _buildViewPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      children: [
        _CompactSwitchRow(
          icon: Icons.grid_4x4_rounded,
          label: 'Reference grid',
          value: _gridVisible,
          onChanged: (_) => _toggleGrid(),
        ),
        _CompactSwitchRow(
          icon: Icons.crop_square_rounded,
          label: 'Solid floor',
          value: _floorVisible,
          onChanged: (_) => _toggleFloor(),
        ),
        const SizedBox(height: 12),
        _InspectorSectionLabel(
          _modelParts.isEmpty
              ? 'Model parts'
              : 'Model parts · ${_modelParts.length}',
        ),
        const SizedBox(height: 7),
        if (_modelParts.isEmpty)
          const _CompactNotice(
            icon: Icons.layers_outlined,
            text: 'Material visibility appears after a model finishes loading.',
          )
        else
          for (final part in _modelParts)
            _CompactPartRow(
              part: part,
              onChanged: () => _togglePartVisibility(part),
            ),
      ],
    );
  }

  Widget _buildLookPanel() {
    void update(_LookSettings next, {bool log = false}) {
      _setLook(next, log: log);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      children: [
        _CompactSwitchRow(
          icon: Icons.tonality_rounded,
          label: 'Color enhancement',
          value: _look.enabled,
          onChanged: (value) => update(_look.copyWith(enabled: value)),
        ),
        const SizedBox(height: 11),
        const _InspectorSectionLabel('Presets'),
        const SizedBox(height: 7),
        _CompactPresetRow(
          selected: _look.preset,
          onSelected: (preset) {
            update(_LookSettings.forPreset(preset, _look), log: true);
          },
        ),
        const SizedBox(height: 12),
        const _InspectorSectionLabel('Image'),
        const SizedBox(height: 7),
        _CompactValueSlider(
          label: 'Exposure',
          value: _look.exposure,
          min: 0.70,
          max: 1.60,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(exposure: value)),
        ),
        _CompactValueSlider(
          label: 'Contrast',
          value: _look.contrast,
          min: 0.75,
          max: 2.0,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(contrast: value)),
        ),
        _CompactValueSlider(
          label: 'Saturation',
          value: _look.saturation,
          min: 0.5,
          max: 2.5,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(saturation: value)),
        ),
        _CompactValueSlider(
          label: 'Dehaze',
          value: _look.dehaze,
          min: 0,
          max: 0.45,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(dehaze: value)),
        ),
        _CompactValueSlider(
          label: 'Texture',
          value: _look.texture,
          min: 0.5,
          max: 2.0,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(texture: value)),
        ),
        const SizedBox(height: 8),
        const _InspectorSectionLabel('Lighting'),
        const SizedBox(height: 7),
        _CompactValueSlider(
          label: 'Ambient',
          value: _look.ambient,
          min: 0.2,
          max: 2.4,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(ambient: value)),
        ),
        _CompactValueSlider(
          label: 'Key light',
          value: _look.key,
          min: 0.2,
          max: 3.2,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(key: value)),
        ),
        _CompactValueSlider(
          label: 'Rim light',
          value: _look.rim,
          min: 0,
          max: 1.8,
          precision: 2,
          onChanged: (value) => update(_look.copyWith(rim: value)),
        ),
      ],
    );
  }

  Widget _buildPlacementPanel() {
    final active = _library.activeModelSlot;
    if (active == null) {
      return const _InspectorEmpty(
        icon: Icons.open_with_rounded,
        message: 'Apply a model before editing placement.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      children: [
        if (_library.modelSlots.length > 1) ...[
          _ModelEditTabs(
            slots: _library.modelSlots,
            activeId: active.id,
            onSelected: _library.setActiveModelSlot,
          ),
          const SizedBox(height: 10),
        ],
        _CompactNudgeGrid(
          onMove: (x, y, z) => _moveActiveModel(x: x, y: y, z: z),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                active.model.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => _setActiveModelTransform(
                active.copyWith(x: 0, y: 0, z: 0),
              ),
              icon: const Icon(Icons.center_focus_strong_rounded, size: 17),
              label: const Text('Reset'),
            ),
          ],
        ),
        _CompactValueSlider(
          label: 'X',
          value: active.x,
          min: -50,
          max: 50,
          precision: 1,
          accent: AppColors.danger,
          onChanged: (value) => _setActiveModelTransform(active.copyWith(x: value)),
        ),
        _CompactValueSlider(
          label: 'Y',
          value: active.y,
          min: -20,
          max: 80,
          precision: 1,
          accent: AppColors.success,
          onChanged: (value) => _setActiveModelTransform(active.copyWith(y: value)),
        ),
        _CompactValueSlider(
          label: 'Z',
          value: active.z,
          min: -50,
          max: 50,
          precision: 1,
          accent: AppColors.accent,
          onChanged: (value) => _setActiveModelTransform(active.copyWith(z: value)),
        ),
      ],
    );
  }

  Widget _buildExportPanel() {
    final screen = _currentScreenExportSize(context);
    final screenSize = '${screen.width}x${screen.height}';
    final duration = _player.duration > 0
        ? _player.duration.round().clamp(1, 600).toInt()
        : 10;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      children: [
        const _CompactNotice(
          icon: Icons.schedule_rounded,
          text: 'Recording runs in real time. Keep Danxe open until it finishes.',
        ),
        const SizedBox(height: 10),
        _CompactChoiceRow(
          label: 'Frame',
          value: '${_exportSettings.width}x${_exportSettings.height}',
          options: [
            const _ChoiceValue('1920x1080', '16:9'),
            const _ChoiceValue('1080x1920', '9:16'),
            const _ChoiceValue('1280x720', '720p'),
            _ChoiceValue(screenSize, 'Screen'),
          ],
          onSelected: (value) {
            final size = value.split('x').map(int.parse).toList(growable: false);
            setState(() {
              _exportSettings = _exportSettings.copyWith(
                width: size[0],
                height: size[1],
              );
            });
          },
        ),
        _CompactChoiceRow(
          label: 'FPS',
          value: '${_exportSettings.fps}',
          options: const [
            _ChoiceValue('30', '30'),
            _ChoiceValue('60', '60'),
          ],
          onSelected: (value) {
            setState(() {
              _exportSettings = _exportSettings.copyWith(fps: int.parse(value));
            });
          },
        ),
        _CompactChoiceRow(
          label: 'Bitrate',
          value: '${_exportSettings.videoBitrateMbps}',
          options: const [
            _ChoiceValue('12', '12M'),
            _ChoiceValue('16', '16M'),
            _ChoiceValue('24', '24M'),
          ],
          onSelected: (value) {
            setState(() {
              _exportSettings = _exportSettings.copyWith(
                videoBitrateMbps: int.parse(value),
              );
            });
          },
        ),
        _CompactChoiceRow(
          label: 'Length',
          value: '${_exportSettings.durationSeconds}',
          options: [
            const _ChoiceValue('10', '10s'),
            const _ChoiceValue('30', '30s'),
            _ChoiceValue('$duration', 'Full'),
          ],
          onSelected: (value) {
            setState(() {
              _exportSettings = _exportSettings.copyWith(
                durationSeconds: int.parse(value),
              );
            });
          },
        ),
        const SizedBox(height: 9),
        FilledButton.icon(
          onPressed: _exporting ? null : _startFloatingExport,
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.movie_creation_outlined, size: 19),
          label: Text(_exporting ? 'Recording…' : 'Record video'),
        ),
      ],
    );
  }

  Future<void> _startFloatingExport() async {
    final models = _library.modelSlots
        .where((slot) => slot.hasRenderableModel)
        .toList(growable: false);
    if (models.isEmpty || _exporting) return;
    final model = models.first.model;
    setState(() => _exporting = true);
    _logs.info(
      'export',
      'Started ${_exportSettings.width}x${_exportSettings.height} ${_exportSettings.fps}fps.',
    );
    try {
      final job = await _export.exportVideo(
        settings: _exportSettings,
        model: model,
        motion: _library.selectedMotion,
        camera: _library.selectedCamera,
        audio: _library.selectedAudio,
      );
      if (!mounted) return;
      _logs.info('export', 'Video exported to ${job.path}.');
      _showMessage('Video exported: ${job.path}');
    } on Object catch (error) {
      if (mounted) setState(() => _exporting = false);
      _logs.error('export', error.toString());
      _showMessage(error.toString());
    }
  }

  Widget _buildLogsPanel() {
    final entries = _logs.entries;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${entries.length} recent events',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ),
              _TinyActionButton(
                tooltip: 'Copy log',
                icon: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _logs.dump()));
                  _showMessage('Log copied.');
                },
              ),
              const SizedBox(width: 5),
              _TinyActionButton(
                tooltip: 'Clear log',
                icon: Icons.delete_sweep_outlined,
                onPressed: entries.isEmpty ? null : _logs.clear,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? const _InspectorEmpty(
                  icon: Icons.receipt_long_outlined,
                  message: 'No log entries.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) => _CompactLogLine(entry: entries[index]),
                ),
        ),
      ],
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
    setState(() {
      _activePanel = null;
      _libraryDetail = null;
      _pendingDeleteAssetId = null;
      _uiHidden = true;
    });
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
    final wasSelected = _isSelected(asset);
    final activeBefore = _library.activeModelSlot;
    if (asset.kind != AssetKind.model && wasSelected) {
      _library.clearSelection(asset.kind);
      _logs.info('apply', 'Cleared ${asset.kind.name}: ${asset.name}.');
      return;
    }
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

class _FloatingSceneChip extends StatelessWidget {
  const _FloatingSceneChip({
    required this.models,
    required this.activeModel,
    required this.player,
    required this.busy,
    required this.maxWidth,
    required this.onPressed,
    required this.onHide,
  });

  final List<AppliedModelSlot> models;
  final AppliedModelSlot? activeModel;
  final PlayerController player;
  final bool busy;
  final double maxWidth;
  final VoidCallback onPressed;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final title = models.isEmpty
        ? 'Scene'
        : models.length == 1
            ? models.first.model.name
            : '${models.length} models · ${activeModel?.model.name ?? models.first.model.name}';
    final status = player.error ??
        (player.loading
            ? 'Loading scene…'
            : player.loaded
                ? player.playing
                    ? 'Playing · ${player.timeLabel}'
                    : 'Ready · ${player.timeLabel}'
                : 'Choose resources to begin');
    final statusColor = player.error != null
        ? AppColors.danger
        : player.loaded
            ? AppColors.success
            : AppColors.textMuted;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: AppColors.surface.withOpacity(0.96),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                onTap: onPressed,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 29,
                        height: 29,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.view_in_ar_outlined, size: 17),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: player.error == null
                                    ? AppColors.textMuted
                                    : AppColors.danger,
                                fontSize: 10,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      if (busy || player.loading)
                        const SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        )
                      else
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 34,
              height: 42,
              child: IconButton(
                tooltip: 'Hide controls',
                padding: EdgeInsets.zero,
                onPressed: onHide,
                style: IconButton.styleFrom(
                  minimumSize: const Size(34, 42),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.visibility_off_outlined, size: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingInspector extends StatelessWidget {
  const _FloatingInspector({
    required this.kind,
    required this.onClose,
    required this.child,
  });

  final _FloatingPanelKind kind;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (title, icon) = switch (kind) {
      _FloatingPanelKind.scene => ('Scene', Icons.layers_outlined),
      _FloatingPanelKind.library => ('Resources', Icons.folder_copy_outlined),
      _FloatingPanelKind.camera => ('Camera', Icons.video_camera_front_outlined),
      _FloatingPanelKind.view => ('Display', Icons.visibility_outlined),
      _FloatingPanelKind.look => ('Color & light', Icons.tonality_rounded),
      _FloatingPanelKind.placement => ('Placement', Icons.open_with_rounded),
      _FloatingPanelKind.export => ('Export', Icons.movie_creation_outlined),
      _FloatingPanelKind.logs => ('Activity', Icons.receipt_long_outlined),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 5),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 38,
                      child: IconButton(
                        tooltip: 'Close panel',
                        padding: EdgeInsets.zero,
                        onPressed: onClose,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _FloatingToolRail extends StatelessWidget {
  const _FloatingToolRail({
    required this.horizontal,
    required this.active,
    required this.hasModels,
    required this.canExport,
    required this.onSelected,
    this.maxExtent,
  });

  final bool horizontal;
  final double? maxExtent;
  final _FloatingPanelKind? active;
  final bool hasModels;
  final bool canExport;
  final ValueChanged<_FloatingPanelKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final tools = <(_FloatingPanelKind, IconData, String, bool)>[
      (_FloatingPanelKind.library, Icons.folder_copy_outlined, 'Resources', true),
      (_FloatingPanelKind.camera, Icons.video_camera_front_outlined, 'Camera', true),
      (_FloatingPanelKind.look, Icons.tonality_rounded, 'Color & light', true),
      (_FloatingPanelKind.view, Icons.visibility_outlined, 'Display', true),
      (_FloatingPanelKind.placement, Icons.open_with_rounded, 'Placement', hasModels),
      (_FloatingPanelKind.export, Icons.movie_creation_outlined, 'Export', canExport),
      (_FloatingPanelKind.logs, Icons.receipt_long_outlined, 'Activity', true),
    ];
    final content = Padding(
      padding: const EdgeInsets.all(4),
      child: Flex(
        direction: horizontal ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < tools.length; index++) ...[
            if (index > 0)
              SizedBox(width: horizontal ? 4 : 0, height: horizontal ? 0 : 4),
            _FloatingToolButton(
              icon: tools[index].$2,
              tooltip: tools[index].$3,
              selected: active == tools[index].$1,
              onPressed: tools[index].$4
                  ? () => onSelected(tools[index].$1)
                  : null,
            ),
          ],
        ],
      ),
    );
    final body = !horizontal && maxExtent != null
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxExtent!),
            child: SingleChildScrollView(child: content),
          )
        : content;
    return Material(
      color: AppColors.surface.withOpacity(0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

class _FloatingToolButton extends StatelessWidget {
  const _FloatingToolButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: selected ? AppColors.primary.withOpacity(0.28) : Colors.transparent,
          foregroundColor: selected ? AppColors.accent : AppColors.text,
          disabledForegroundColor: AppColors.textMuted.withOpacity(0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        icon: Icon(icon, size: 19),
      ),
    );
  }
}

class _FloatingTransportBar extends StatelessWidget {
  const _FloatingTransportBar({
    required this.player,
    required this.exporting,
    required this.onToggle,
    required this.onSeek,
    required this.onSpeed,
  });

  final PlayerController player;
  final bool exporting;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeed;

  @override
  Widget build(BuildContext context) {
    final duration = player.duration <= 0 ? 1.0 : player.duration;
    final position = player.duration <= 0
        ? 0.0
        : player.position.clamp(0, player.duration).toDouble();
    const speeds = [0.5, 1.0, 1.5, 2.0];
    final current = speeds.indexWhere((value) => (value - player.speed).abs() < 0.01);
    final nextSpeed = speeds[(current < 0 ? 0 : current + 1) % speeds.length];
    final speedLabel = '${player.speed.toStringAsFixed(
      player.speed == player.speed.roundToDouble() ? 0 : 1,
    )}x';
    return Material(
      color: AppColors.surface.withOpacity(0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.line),
      ),
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 38,
                child: IconButton.filled(
                  tooltip: player.playing ? 'Pause' : 'Play',
                  padding: EdgeInsets.zero,
                  onPressed: player.loaded ? onToggle : null,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                  icon: Icon(
                    player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: 67,
                child: Text(
                  exporting ? 'Recording…' : player.timeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: exporting ? AppColors.accent : AppColors.text,
                    fontSize: exporting ? 10.5 : 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    min: 0,
                    max: duration,
                    value: position,
                    onChanged: player.loaded ? onSeek : null,
                  ),
                ),
              ),
              SizedBox(
                width: 42,
                height: 34,
                child: TextButton(
                  onPressed: player.loaded ? () => onSpeed(nextSpeed) : null,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(42, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.text,
                    backgroundColor: AppColors.surfaceHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    speedLabel,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectorSectionLabel extends StatelessWidget {
  const _InspectorSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.45,
      ),
    );
  }
}

class _InspectorBindingRow extends StatelessWidget {
  const _InspectorBindingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onPressed,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 4, 7),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? AppColors.accent : AppColors.textMuted),
                const SizedBox(width: 9),
                SizedBox(
                  width: 56,
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: active ? AppColors.text : AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (onClear != null)
                  SizedBox.square(
                    dimension: 32,
                    child: IconButton(
                      tooltip: 'Clear $label',
                      padding: EdgeInsets.zero,
                      onPressed: onClear,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 15),
                    ),
                  )
                else
                  const SizedBox(width: 5),
                const Icon(Icons.chevron_right_rounded, size: 17, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorPackageRow extends StatelessWidget {
  const _InspectorPackageRow({required this.bundle, required this.onPressed});

  final DanceAssetPackage bundle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.playlist_play_rounded, size: 19, color: AppColors.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bundle.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.add_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyActionButton extends StatelessWidget {
  const _TinyActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: emphasized
              ? AppColors.primary.withOpacity(0.32)
              : AppColors.surfaceHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _LibraryKindButton extends StatelessWidget {
  const _LibraryKindButton({
    required this.kind,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final AssetKind kind;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: kind.label,
      child: Material(
        color: selected ? AppColors.primary.withOpacity(0.28) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                Icon(_iconForKind(kind), size: 17, color: selected ? AppColors.accent : null),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorEmpty extends StatelessWidget {
  const _InspectorEmpty({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppColors.textMuted),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.35),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 11),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _InspectorAssetRow extends StatelessWidget {
  const _InspectorAssetRow({
    required this.asset,
    required this.selected,
    required this.onPressed,
    required this.onDetails,
  });

  final LibraryAsset asset;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.primary.withOpacity(0.18) : AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? AppColors.primary.withOpacity(0.66) : AppColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 3, 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.48),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_iconForKind(asset.kind), size: 18),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_assetCapability(asset)} · ${_formatBytes(asset.totalBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 9.8),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                SizedBox.square(
                  dimension: 34,
                  child: IconButton(
                    tooltip: 'Resource details',
                    padding: EdgeInsets.zero,
                    onPressed: onDetails,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
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

class _CompactResourceIdentity extends StatelessWidget {
  const _CompactResourceIdentity({required this.asset});

  final LibraryAsset asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.5),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_iconForKind(asset.kind), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  _assetCapability(asset),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMetadata extends StatelessWidget {
  const _CompactMetadata({required this.asset});

  final LibraryAsset asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          _CompactMetadataLine(label: 'Type', value: asset.kind.label),
          _CompactMetadataLine(label: 'Files', value: '${asset.fileCount}'),
          _CompactMetadataLine(label: 'Size', value: _formatBytes(asset.totalBytes)),
          _CompactMetadataLine(label: 'Source', value: asset.sourceName),
        ],
      ),
    );
  }
}

class _CompactMetadataLine extends StatelessWidget {
  const _CompactMetadataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactNotice extends StatelessWidget {
  const _CompactNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActionTile extends StatelessWidget {
  const _CompactActionTile({
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
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactValueSlider extends StatelessWidget {
  const _CompactValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
    this.precision = 1,
    this.accent = AppColors.accent,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String suffix;
  final int precision;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 7, 8, 2),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${clamped.toStringAsFixed(precision)}$suffix',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 30,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  trackHeight: 2,
                  thumbColor: AppColors.text,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
                ),
                child: Slider(min: min, max: max, value: clamped, onChanged: onChanged),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSwitchRow extends StatelessWidget {
  const _CompactSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        height: 48,
        padding: const EdgeInsets.only(left: 10, right: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
            Transform.scale(
              scale: 0.78,
              child: Switch.adaptive(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactPartRow extends StatelessWidget {
  const _CompactPartRow({required this.part, required this.onChanged});

  final ViewerPart part;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Icon(
                part.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 17,
                color: part.visible ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  part.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPresetRow extends StatelessWidget {
  const _CompactPresetRow({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const presets = [
      ('balanced', 'Balanced'),
      ('clear', 'Clear'),
      ('vivid', 'Vivid'),
      ('stage', 'Stage'),
    ];
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final preset in presets)
          _CompactChoiceButton(
            label: preset.$2,
            selected: selected == preset.$1,
            onPressed: () => onSelected(preset.$1),
          ),
      ],
    );
  }
}

class _CompactNudgeGrid extends StatelessWidget {
  const _CompactNudgeGrid({required this.onMove});

  final void Function(double x, double y, double z) onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          _NudgeAxisRow(
            label: 'X',
            color: AppColors.danger,
            onMinus: () => onMove(-0.1, 0, 0),
            onPlus: () => onMove(0.1, 0, 0),
          ),
          _NudgeAxisRow(
            label: 'Y',
            color: AppColors.success,
            onMinus: () => onMove(0, -0.1, 0),
            onPlus: () => onMove(0, 0.1, 0),
          ),
          _NudgeAxisRow(
            label: 'Z',
            color: AppColors.accent,
            onMinus: () => onMove(0, 0, -0.1),
            onPlus: () => onMove(0, 0, 0.1),
          ),
        ],
      ),
    );
  }
}

class _NudgeAxisRow extends StatelessWidget {
  const _NudgeAxisRow({
    required this.label,
    required this.color,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final Color color;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 37,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: _NudgeStepButton(icon: Icons.remove_rounded, onPressed: onMinus),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _NudgeStepButton(icon: Icons.add_rounded, onPressed: onPlus),
          ),
        ],
      ),
    );
  }
}

class _NudgeStepButton extends StatelessWidget {
  const _NudgeStepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 29,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(40, 29),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 17),
      ),
    );
  }
}

class _ChoiceValue {
  const _ChoiceValue(this.value, this.label);

  final String value;
  final String label;
}

class _CompactChoiceRow extends StatelessWidget {
  const _CompactChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String value;
  final List<_ChoiceValue> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final unique = <String, _ChoiceValue>{
      for (final option in options) option.value: option,
    }.values.toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final option in unique)
                  _CompactChoiceButton(
                    label: option.label,
                    selected: option.value == value,
                    onPressed: () => onSelected(option.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactChoiceButton extends StatelessWidget {
  const _CompactChoiceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 31,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: selected ? AppColors.text : AppColors.textMuted,
          backgroundColor: selected
              ? AppColors.primary.withOpacity(0.34)
              : AppColors.background.withOpacity(0.28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(38, 31),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _CompactLogLine extends StatelessWidget {
  const _CompactLogLine({required this.entry});

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
      style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 10.5, height: 1.35),
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
