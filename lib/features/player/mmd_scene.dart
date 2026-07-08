import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../library/asset_models.dart';
import 'player_controller.dart';

class MmdSceneViewport extends StatefulWidget {
  const MmdSceneViewport({
    required this.player,
    required this.model,
    required this.motion,
    required this.camera,
    super.key,
  });

  final PlayerController player;
  final LibraryAsset? model;
  final LibraryAsset? motion;
  final LibraryAsset? camera;

  @override
  State<MmdSceneViewport> createState() => _MmdSceneViewportState();
}

class _MmdSceneViewportState extends State<MmdSceneViewport> {
  double _startYaw = 0;
  double _startPitch = 0;
  double _startDistance = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        _startYaw = widget.player.yaw;
        _startPitch = widget.player.pitch;
        _startDistance = widget.player.distance;
      },
      onScaleUpdate: (details) {
        final focal = details.focalPointDelta;
        if (details.pointerCount > 1) {
          widget.player.orbit(
            distance: _startDistance / details.scale.clamp(0.4, 2.4).toDouble(),
          );
        } else {
          widget.player.orbit(
            yaw: _startYaw + focal.dx * 0.18,
            pitch: _startPitch - focal.dy * 0.18,
          );
        }
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: MmdScenePainter(
            model: widget.model,
            motion: widget.motion,
            camera: widget.camera,
            player: widget.player,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class MmdScenePainter extends CustomPainter {
  MmdScenePainter({
    required this.player,
    required this.model,
    required this.motion,
    required this.camera,
  }) : super(repaint: player);

  final PlayerController player;
  final LibraryAsset? model;
  final LibraryAsset? motion;
  final LibraryAsset? camera;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintGrid(canvas, size);
    _paintModelProxy(canvas, size);
    _paintOverlayText(canvas, size);
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        AppColors.background,
        Color(0xFF10172D),
        Color(0xFF071827),
      ],
      stops: const [0, 0.55, 1],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primary.withOpacity(0.20),
          AppColors.accent.withOpacity(0.08),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.68, size.height * 0.28),
          radius: size.shortestSide * 0.7,
        ),
      );
    canvas.drawRect(rect, glow);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final horizon = size.height * 0.64 + player.pitch * 1.4;
    final centerX = size.width * 0.52 + player.panX * 44;
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = -10; i <= 10; i++) {
      final spread = i * size.width / 18;
      canvas.drawLine(
        Offset(centerX + spread * 0.28, horizon),
        Offset(centerX + spread, size.height),
        paint,
      );
    }
    for (var i = 0; i < 10; i++) {
      final y = horizon + math.pow(i / 9, 1.7) * size.height * 0.36;
      canvas.drawLine(Offset(0, y.toDouble()), Offset(size.width, y.toDouble()), paint);
    }
  }

  void _paintModelProxy(Canvas canvas, Size size) {
    final hasModel = model?.hasRenderableModel ?? false;
    final center = Offset(
      size.width * 0.52 + player.panX * 60,
      size.height * 0.53 + player.panY * 60,
    );
    final scale = (size.shortestSide / player.distance).clamp(62, 180).toDouble();
    final bob = math.sin(player.position * 2.2) * (player.playing ? 3 : 0);
    final yawShift = math.sin(player.yaw * math.pi / 180) * scale * 0.18;

    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + yawShift * 0.2, center.dy + scale * 1.16),
        width: scale * 1.25,
        height: scale * 0.18,
      ),
      shadow,
    );

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: hasModel
            ? const [Color(0xFFE2E8F0), Color(0xFF8B5CF6), Color(0xFF06B6D4)]
            : const [Color(0xFF475569), Color(0xFF334155)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(
        Rect.fromCenter(center: center, width: scale, height: scale * 2),
      );

    final outline = Paint()
      ..color = Colors.black.withOpacity(0.56)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round;

    final figure = Path()
      ..moveTo(center.dx, center.dy - scale * 0.95 + bob)
      ..cubicTo(
        center.dx - scale * 0.42,
        center.dy - scale * 0.82 + bob,
        center.dx - scale * 0.54 + yawShift,
        center.dy - scale * 0.14 + bob,
        center.dx - scale * 0.28 + yawShift,
        center.dy + scale * 0.42 + bob,
      )
      ..lineTo(center.dx - scale * 0.18 + yawShift, center.dy + scale * 1.04 + bob)
      ..lineTo(center.dx + scale * 0.24 + yawShift, center.dy + scale * 1.04 + bob)
      ..lineTo(center.dx + scale * 0.32 + yawShift, center.dy + scale * 0.42 + bob)
      ..cubicTo(
        center.dx + scale * 0.54 + yawShift,
        center.dy - scale * 0.12 + bob,
        center.dx + scale * 0.40,
        center.dy - scale * 0.82 + bob,
        center.dx,
        center.dy - scale * 0.95 + bob,
      )
      ..close();

    canvas.drawPath(figure, outline);
    canvas.drawPath(figure, bodyPaint);

    final headPaint = Paint()
      ..color = hasModel ? const Color(0xFFF8FAFC) : const Color(0xFF64748B);
    canvas.drawCircle(
      Offset(center.dx, center.dy - scale * 1.12 + bob),
      scale * 0.22,
      outline,
    );
    canvas.drawCircle(
      Offset(center.dx, center.dy - scale * 1.12 + bob),
      scale * 0.2,
      headPaint,
    );

    if (hasModel) {
      _paintAssetRings(canvas, center, scale);
    }
  }

  void _paintAssetRings(Canvas canvas, Offset center, double scale) {
    final textureCount = model?.textureCandidates.length ?? 0;
    final motionCount = motion?.motionCandidates.length ?? 0;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.accent.withOpacity(0.58);
    final pulse = 1 + math.sin(player.position * 1.6) * 0.03;
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, scale * 0.12),
        width: scale * (1.3 + textureCount.clamp(0, 8).toDouble() * 0.04) * pulse,
        height: scale * 1.96 * pulse,
      ),
      ringPaint,
    );
    if (motionCount > 0 || camera != null) {
      final motionPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.primary.withOpacity(0.72);
      canvas.drawArc(
        Rect.fromCenter(
          center: center.translate(0, -scale * 0.08),
          width: scale * 1.62,
          height: scale * 2.2,
        ),
        -math.pi / 2,
        math.pi * (0.2 + (player.position / player.duration).clamp(0, 1).toDouble()),
        false,
        motionPaint,
      );
    }
  }

  void _paintOverlayText(Canvas canvas, Size size) {
    final text = model == null
        ? 'Library empty'
        : model!.hasRenderableModel
            ? model!.name
            : 'Indexed asset';
    final subtext = model == null
        ? 'Import PMX zip or motion assets'
        : '${model!.pmxCandidates.length} PMX  ${model!.textureCandidates.length} textures';
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$text\n',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: subtext,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: math.max(160, size.width - 220));
    painter.paint(canvas, Offset(size.width * 0.5 - painter.width * 0.5, size.height * 0.13));
  }

  @override
  bool shouldRepaint(covariant MmdScenePainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.motion != motion ||
        oldDelegate.camera != camera ||
        oldDelegate.player != player;
  }
}
