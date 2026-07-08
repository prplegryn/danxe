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
    };
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }
}

