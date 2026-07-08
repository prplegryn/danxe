import 'mmd_formats.dart';

abstract class NanoemRenderPort {
  Future<SceneLoadReport> loadScene(MmdSceneInput input);

  Future<FrameEvaluation> evaluateFrame({
    required double second,
    required double yaw,
    required double pitch,
    required double distance,
  });
}

/// Minimal runtime port shaped after nanoem's separation of asset loading,
/// frame evaluation, and rendering. This backend indexes imported files only.
class IndexedAssetRenderPort implements NanoemRenderPort {
  const IndexedAssetRenderPort();

  @override
  Future<SceneLoadReport> loadScene(MmdSceneInput input) async {
    final modelReady = input.model.pmxCandidates.isNotEmpty;
    return SceneLoadReport(
      accepted: modelReady,
      summary: modelReady
          ? 'Indexed ${input.model.pmxCandidates.first}'
          : 'No PMX entry found',
      missingCapabilities: const [
        'native nanoem mesh decode',
        'toon and sphere material shader',
        'VMD bone and morph solver',
        'hardware video encoder pipeline',
      ],
    );
  }

  @override
  Future<FrameEvaluation> evaluateFrame({
    required double second,
    required double yaw,
    required double pitch,
    required double distance,
  }) async {
    return FrameEvaluation(
      second: second,
      cameraYaw: yaw,
      cameraPitch: pitch,
      cameraDistance: distance,
    );
  }
}
