import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../infrastructure/host_bridge.dart';
import '../export/export_controller.dart';
import '../export/export_models.dart';
import '../library/asset_models.dart';
import '../library/resource_library_controller.dart';
import 'mmd_scene.dart';
import 'player_controller.dart';

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
  bool _railExpanded = true;

  @override
  void initState() {
    super.initState();
    _bridge = HostBridge();
    _library = ResourceLibraryController(_bridge)..load();
    _player = PlayerController();
    _export = ExportController(_bridge);
    _library.addListener(_syncTimeline);
  }

  @override
  void dispose() {
    _library.removeListener(_syncTimeline);
    _library.dispose();
    _player.dispose();
    super.dispose();
  }

  void _syncTimeline() {
    _player.applyMotion(_library.selectedMotion, _library.selectedCamera);
    if (_library.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_library.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_library, _player]),
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final railWidth = compact
                    ? (_railExpanded ? constraints.maxWidth.clamp(280, 340).toDouble() : 72.0)
                    : (_railExpanded ? 312.0 : 88.0);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: MmdSceneViewport(
                        player: _player,
                        model: _library.selectedModel,
                        motion: _library.selectedMotion,
                        camera: _library.selectedCamera,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: railWidth,
                      child: _LibraryRail(
                        expanded: _railExpanded,
                        compact: compact,
                        controller: _library,
                        onToggle: () {
                          setState(() => _railExpanded = !_railExpanded);
                        },
                      ),
                    ),
                    Positioned(
                      left: railWidth + AppSpacing.x4,
                      right: compact ? AppSpacing.x4 : 116,
                      top: AppSpacing.x4,
                      child: _TopBar(
                        model: _library.selectedModel,
                        motion: _library.selectedMotion,
                        busy: _library.busy,
                      ),
                    ),
                    Positioned(
                      right: AppSpacing.x4,
                      top: compact ? null : 96,
                      bottom: compact ? 112 : 120,
                      width: compact ? 64 : 88,
                      child: _CameraControls(player: _player, compact: compact),
                    ),
                    Positioned(
                      left: railWidth + AppSpacing.x4,
                      right: AppSpacing.x4,
                      bottom: AppSpacing.x4,
                      child: _TransportBar(
                        player: _player,
                        canExport: _library.selectedModel != null,
                        onExport: () => _showExportSheet(context),
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

  Future<void> _showExportSheet(BuildContext context) async {
    final model = _library.selectedModel;
    if (model == null) return;
    var settings = const ExportSettings();
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
                    const Text(
                      'Export job',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
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
                        setSheetState(() {
                          settings = settings.copyWith(fps: int.parse(value));
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Bitrate ${settings.videoBitrateMbps} Mbps'),
                    Slider(
                      min: 4,
                      max: 24,
                      divisions: 10,
                      value: settings.videoBitrateMbps.toDouble(),
                      onChanged: (value) {
                        setSheetState(() {
                          settings = settings.copyWith(videoBitrateMbps: value.round());
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Creates a render job spec for the future native nanoem video backend.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(this.context);
                          final navigator = Navigator.of(context);
                          final job = await _export.createRenderJob(
                            settings: settings,
                            model: model,
                            motion: _library.selectedMotion,
                            camera: _library.selectedCamera,
                            audio: _library.selectedAudio,
                          );
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Render job saved: ${job.path}')),
                          );
                        },
                        icon: const Icon(Icons.outbox_rounded),
                        label: const Text('Create job'),
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
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.model,
    required this.motion,
    required this.busy,
  });

  final LibraryAsset? model;
  final LibraryAsset? motion;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.78),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.view_in_ar_rounded, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Danxe',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    icon: Icons.person_rounded,
                    label: model?.name ?? 'No model',
                  ),
                  _StatusChip(
                    icon: Icons.timeline_rounded,
                    label: motion?.name ?? 'No motion',
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: busy
                  ? const SizedBox.square(
                      key: ValueKey('busy'),
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded, key: ValueKey('ready'), size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryRail extends StatelessWidget {
  const _LibraryRail({
    required this.expanded,
    required this.compact,
    required this.controller,
    required this.onToggle,
  });

  final bool expanded;
  final bool compact;
  final ResourceLibraryController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.94),
        border: const Border(right: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        right: false,
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: expanded ? 'Collapse library' : 'Open library',
                    onPressed: onToggle,
                    icon: Icon(expanded ? Icons.menu_open_rounded : Icons.menu_rounded),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Library',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: expanded
                  ? _ExpandedLibrary(controller: controller)
                  : _CollapsedLibrary(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedLibrary extends StatelessWidget {
  const _CollapsedLibrary({required this.controller});

  final ResourceLibraryController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: AssetKind.values.take(5).map((kind) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IconButton.filledTonal(
            tooltip: kind.label,
            onPressed: () => controller.importKind(kind),
            icon: Icon(_iconForKind(kind)),
          ),
        );
      }).toList(),
    );
  }
}

class _ExpandedLibrary extends StatelessWidget {
  const _ExpandedLibrary({required this.controller});

  final ResourceLibraryController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AssetKind.values.take(5).map((kind) {
            return SizedBox(
              height: 48,
              child: FilledButton.tonalIcon(
                onPressed: controller.busy ? null : () => controller.importKind(kind),
                icon: Icon(_iconForKind(kind), size: 18),
                label: Text(kind.name),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        for (final kind in AssetKind.values.take(5)) ...[
          _SectionHeader(kind: kind, count: controller.byKind(kind).length),
          const SizedBox(height: 8),
          if (controller.byKind(kind).isEmpty)
            const _EmptyLibraryRow()
          else
            ...controller.byKind(kind).map(
                  (asset) => _AssetTile(
                    asset: asset,
                    selected: _isSelected(controller, asset),
                    onTap: () => controller.select(asset),
                    onDelete: () => controller.delete(asset),
                  ),
                ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  bool _isSelected(ResourceLibraryController controller, LibraryAsset asset) {
    return controller.selectedModel?.id == asset.id ||
        controller.selectedMotion?.id == asset.id ||
        controller.selectedCamera?.id == asset.id ||
        controller.selectedAudio?.id == asset.id;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.kind, required this.count});

  final AssetKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_iconForKind(kind), size: 18, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            kind.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text('$count', style: const TextStyle(color: AppColors.textMuted)),
      ],
    );
  }
}

class _EmptyLibraryRow extends StatelessWidget {
  const _EmptyLibraryRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Empty',
        style: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final LibraryAsset asset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primary.withOpacity(0.28) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                Icon(_iconForKind(asset.kind), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${asset.fileCount} files  ${_formatBytes(asset.totalBytes)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraControls extends StatelessWidget {
  const _CameraControls({required this.player, required this.compact});

  final PlayerController player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.78),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            IconButton(
              tooltip: 'Reset camera',
              onPressed: player.resetCamera,
              icon: const Icon(Icons.center_focus_strong_rounded),
            ),
            const Divider(color: AppColors.line),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  min: -180,
                  max: 180,
                  value: player.yaw,
                  onChanged: (value) => player.orbit(yaw: value),
                ),
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  min: 1.4,
                  max: 12,
                  value: player.distance,
                  onChanged: (value) => player.orbit(distance: value),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Pitch up',
              onPressed: () => player.orbit(pitch: player.pitch + 4),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Pitch down',
              onPressed: () => player.orbit(pitch: player.pitch - 4),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.player,
    required this.canExport,
    required this.onExport,
  });

  final PlayerController player;
  final bool canExport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.86),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Row(
          children: [
            IconButton.filled(
              tooltip: player.playing ? 'Pause' : 'Play',
              onPressed: player.toggle,
              icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            const SizedBox(width: 8),
            Text(
              player.timeLabel,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Slider(
                min: 0,
                max: player.duration,
                value: player.position.clamp(0, player.duration).toDouble(),
                onChanged: player.seek,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: DropdownButton<double>(
                isExpanded: true,
                value: player.speed,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                  DropdownMenuItem(value: 1.0, child: Text('1x')),
                  DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                  DropdownMenuItem(value: 2.0, child: Text('2x')),
                ],
                onChanged: (value) {
                  if (value != null) player.setSpeed(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: canExport ? onExport : null,
              icon: const Icon(Icons.movie_creation_rounded),
              label: const Text('Export'),
            ),
          ],
        ),
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
                .map(
                  (option) => ButtonSegment<String>(
                    value: option,
                    label: Text(option),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
