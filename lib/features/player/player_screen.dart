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

enum _QuickMenu { camera, apply }

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
  _QuickMenu? _openQuickMenu;
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
      _player.applyViewerEvent(event);
    });

    switch (event.type) {
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
    }
  }

  void _syncScene() {
    final error = _library.error;
    if (error != null && error != _lastLibraryError) {
      _lastLibraryError = error;
      _logs.error('library', error);
      _showMessage(error);
    }

    final signature = [
      _library.selectedModel?.id,
      _library.selectedMotion?.id,
      _library.selectedCamera?.id,
      _library.selectedAudio?.id,
      _library.selectedFace?.id,
    ].join(':');
    if (signature == _lastSceneSignature) return;
    _lastSceneSignature = signature;

    final model = _library.selectedModel;
    if (model == null) {
      _player.setIdle('Choose a model from Apply.');
      _bridge.viewerClear().catchError((Object error) {
        _logs.error('renderer', error.toString());
      });
      return;
    }
    if (!model.hasRenderableModel) {
      _player.setError('Selected model has no PMX or PMD file.');
      _logs.error('apply', '${model.name} has no PMX or PMD file.');
      _bridge.viewerClear().catchError((Object error) {
        _logs.error('renderer', error.toString());
      });
      return;
    }

    _player.setLoading('Loading ${model.name}...');
    _logs.info('apply', 'Loading ${model.name}.');
    _bridge
        .viewerLoadScene(
          model: model,
          motion: _library.selectedMotion,
          camera: _library.selectedCamera,
          audio: _library.selectedAudio,
          face: _library.selectedFace,
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
                  Positioned(
                    left: 16,
                    bottom: bottom,
                    child: _MiniTransportCapsule(
                      player: _player,
                      exporting: _exporting,
                      canExport: _library.selectedModel?.hasRenderableModel ?? false,
                      onToggle: _togglePlayback,
                      onExport: () {
                        _closeQuickMenu();
                        _showExportSheet();
                      },
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
                      onLog: () {
                        _closeQuickMenu();
                        _showLogSheet();
                      },
                      onCameraPreset: _applyCameraPreset,
                    ),
                  ),
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
      _openQuickMenu = _openQuickMenu == menu ? null : menu;
    });
  }

  void _closeQuickMenu() {
    if (_openQuickMenu == null) return;
    setState(() => _openQuickMenu = null);
  }

  void _openAssetPickerFromDock(AssetKind kind) {
    _closeQuickMenu();
    _showAssetPicker(kind);
  }

  void _openLibraryFromDock() {
    _closeQuickMenu();
    _showLibraryManager();
  }

  Future<void> _applyCameraPreset(String preset) async {
    _closeQuickMenu();
    await _bridge.viewerSetCameraPreset(preset);
    _logs.info('camera', preset == 'halfFront' ? 'Applied half-front preset.' : 'Applied full-front preset.');
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
                                    selected: _isSelected(asset),
                                    onTap: () {
                                      _applyAsset(asset);
                                      Navigator.of(context).pop();
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
    final model = _library.selectedModel;
    if (model == null || !model.hasRenderableModel) return;
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
                      options: const ['1280x720', '1920x1080', '2160x3840'],
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
                      options: const ['24', '30', '60'],
                      onSelected: (value) {
                        setSheetState(() => settings = settings.copyWith(fps: int.parse(value)));
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

  Future<void> _import(AssetKind kind) async {
    final asset = await _library.importKind(kind);
    if (asset != null) {
      _logs.info('library', 'Imported ${asset.name}.');
      if (kind == AssetKind.face) {
        _logs.info('apply', 'Face VMD is ready to apply.');
      }
    }
  }

  void _applyAsset(LibraryAsset asset) {
    _library.select(asset);
    _logs.info('apply', 'Applied ${asset.kind.name}: ${asset.name}.');
    if (asset.kind == AssetKind.face) {
      _logs.info('apply', 'Face VMD will be merged into the model animation.');
    }
  }

  bool _isSelected(LibraryAsset asset) {
    return _library.selectedModel?.id == asset.id ||
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

class _QuickActionDock extends StatelessWidget {
  const _QuickActionDock({
    required this.openMenu,
    required this.onToggleMenu,
    required this.onApplyKind,
    required this.onOpenLibrary,
    required this.onLog,
    required this.onCameraPreset,
  });

  final _QuickMenu? openMenu;
  final ValueChanged<_QuickMenu> onToggleMenu;
  final ValueChanged<AssetKind> onApplyKind;
  final VoidCallback onOpenLibrary;
  final VoidCallback onLog;
  final ValueChanged<String> onCameraPreset;

  @override
  Widget build(BuildContext context) {
    final maxActionsWidth = MediaQuery.sizeOf(context).width - 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
  });

  final LibraryAsset asset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

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
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: SegmentedButton<String>(
            segments: options
                .toSet()
                .map((option) => ButtonSegment<String>(value: option, label: Text(option)))
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
