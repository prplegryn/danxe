enum AssetKind {
  model,
  motion,
  camera,
  audio,
  face,
  other;

  static AssetKind fromName(String value) {
    return AssetKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => AssetKind.other,
    );
  }

  String get label {
    switch (this) {
      case AssetKind.model:
        return 'Models';
      case AssetKind.motion:
        return 'Motions';
      case AssetKind.camera:
        return 'Cameras';
      case AssetKind.audio:
        return 'Audio';
      case AssetKind.face:
        return 'Face';
      case AssetKind.other:
        return 'Other';
    }
  }
}

class LibraryAsset {
  const LibraryAsset({
    required this.id,
    required this.kind,
    required this.name,
    required this.path,
    required this.sourcePath,
    required this.sourceName,
    required this.fileCount,
    required this.totalBytes,
    required this.pmxCandidates,
    required this.motionCandidates,
    required this.textureCandidates,
    required this.audioCandidates,
    this.packageId = '',
    this.packageName = '',
  });

  final String id;
  final AssetKind kind;
  final String name;
  final String path;
  final String sourcePath;
  final String sourceName;
  final int fileCount;
  final int totalBytes;
  final List<String> pmxCandidates;
  final List<String> motionCandidates;
  final List<String> textureCandidates;
  final List<String> audioCandidates;
  final String packageId;
  final String packageName;

  bool get hasRenderableModel => pmxCandidates.isNotEmpty;
  bool get hasMotion => motionCandidates.isNotEmpty;
  bool get hasAudio => audioCandidates.isNotEmpty;

  factory LibraryAsset.fromJson(Map<String, Object?> json) {
    return LibraryAsset(
      id: json['id'] as String? ?? '',
      kind: AssetKind.fromName(json['kind'] as String? ?? 'other'),
      name: json['name'] as String? ?? 'Untitled',
      path: json['path'] as String? ?? '',
      sourcePath: json['sourcePath'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      pmxCandidates: _stringList(json['pmxCandidates']),
      motionCandidates: _stringList(json['motionCandidates']),
      textureCandidates: _stringList(json['textureCandidates']),
      audioCandidates: _stringList(json['audioCandidates']),
      packageId: json['packageId'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'name': name,
      'path': path,
      'sourcePath': sourcePath,
      'sourceName': sourceName,
      'fileCount': fileCount,
      'totalBytes': totalBytes,
      'pmxCandidates': pmxCandidates,
      'motionCandidates': motionCandidates,
      'textureCandidates': textureCandidates,
      'audioCandidates': audioCandidates,
      'packageId': packageId,
      'packageName': packageName,
    };
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }
}

class DanceAssetPackage {
  const DanceAssetPackage({
    required this.id,
    required this.name,
    this.motion,
    this.audio,
    this.face,
    this.camera,
  });

  final String id;
  final String name;
  final LibraryAsset? motion;
  final LibraryAsset? audio;
  final LibraryAsset? face;
  final LibraryAsset? camera;

  bool get canApply => motion != null || audio != null || face != null;

  String get summary {
    final parts = <String>[
      if (motion != null) 'Motion',
      if (audio != null) 'Audio',
      if (face != null) 'Face',
      if (camera != null) 'Camera ignored',
    ];
    return parts.isEmpty ? 'No playable assets' : parts.join(' / ');
  }
}

class AppliedModelSlot {
  const AppliedModelSlot({
    required this.id,
    required this.model,
    this.motion,
    this.face,
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  final String id;
  final LibraryAsset model;
  final LibraryAsset? motion;
  final LibraryAsset? face;
  final double x;
  final double y;
  final double z;

  bool get hasRenderableModel => model.hasRenderableModel;

  AppliedModelSlot copyWith({
    LibraryAsset? model,
    LibraryAsset? motion,
    bool clearMotion = false,
    LibraryAsset? face,
    bool clearFace = false,
    double? x,
    double? y,
    double? z,
  }) {
    return AppliedModelSlot(
      id: id,
      model: model ?? this.model,
      motion: clearMotion ? null : motion ?? this.motion,
      face: clearFace ? null : face ?? this.face,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
    );
  }
}
