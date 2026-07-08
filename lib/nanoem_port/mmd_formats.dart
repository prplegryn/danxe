import '../features/library/asset_models.dart';

class MmdSceneInput {
  const MmdSceneInput({
    required this.model,
    this.motion,
    this.camera,
    this.audio,
  });

  final LibraryAsset model;
  final LibraryAsset? motion;
  final LibraryAsset? camera;
  final LibraryAsset? audio;
}

class SceneLoadReport {
  const SceneLoadReport({
    required this.accepted,
    required this.summary,
    required this.missingCapabilities,
  });

  final bool accepted;
  final String summary;
  final List<String> missingCapabilities;
}

class FrameEvaluation {
  const FrameEvaluation({
    required this.second,
    required this.cameraYaw,
    required this.cameraPitch,
    required this.cameraDistance,
  });

  final double second;
  final double cameraYaw;
  final double cameraPitch;
  final double cameraDistance;
}

