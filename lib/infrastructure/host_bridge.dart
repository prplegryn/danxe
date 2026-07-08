import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../features/library/asset_models.dart';

class HostBridge {
  static const MethodChannel _channel = MethodChannel('danxe/host');

  Future<Directory> getLibraryRoot() async {
    final path = await _channel.invokeMethod<String>('getLibraryRoot');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Android library root is unavailable');
    }
    return Directory(path);
  }

  Future<List<LibraryAsset>> scanLibrary() async {
    final payload = await _channel.invokeMethod<String>('scanLibrary');
    final decoded = jsonDecode(payload ?? '[]') as List<dynamic>;
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => LibraryAsset.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  Future<LibraryAsset?> importAsset(AssetKind kind) async {
    final payload = await _channel.invokeMethod<String>(
      'importAsset',
      <String, Object?>{'kind': kind.name},
    );
    if (payload == null || payload.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    return LibraryAsset.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> deleteAsset(LibraryAsset asset) {
    return _channel.invokeMethod<void>(
      'deleteAsset',
      <String, Object?>{'kind': asset.kind.name, 'id': asset.id},
    );
  }
}

