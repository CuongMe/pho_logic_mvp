import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

class TileAtlasFrame {
  final ui.Image image;
  final ui.Rect frameRect;
  final ui.Rect spriteSourceRect;
  final ui.Size sourceSize;
  final bool rotated;

  const TileAtlasFrame({
    required this.image,
    required this.frameRect,
    required this.spriteSourceRect,
    required this.sourceSize,
    required this.rotated,
  });
}

class TileAtlasData {
  final Map<String, TileAtlasFrame> frames;

  const TileAtlasData({required this.frames});
}

class TileAtlasLoader {
  static const String atlasImageAssetPath = 'assets/sprites/texture.png';
  static const String atlasJsonAssetPath = 'assets/sprites/texture.json';

  static const Set<String> _atlasFrameNameHints = {
    'banh_mi.png',
    'banh_xeo.png',
    'ca_phe_trung.png',
    'goi_cuon.png',
    'pho_bowl.png',
    'rau_muong.png',
  };

  static TileAtlasData? _cachedData;
  static Future<TileAtlasData>? _pendingLoad;

  static String frameNameFromAssetPath(String assetPath) {
    final parts = assetPath.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? assetPath : parts.last;
  }

  static bool isLikelyAtlasManagedAsset(String assetPath) {
    return _atlasFrameNameHints.contains(frameNameFromAssetPath(assetPath));
  }

  static TileAtlasFrame? frameForAssetPath(
      TileAtlasData data, String assetPath) {
    final frameName = frameNameFromAssetPath(assetPath);
    return data.frames[frameName];
  }

  static Future<TileAtlasData> load() {
    final cached = _cachedData;
    if (cached != null) {
      return Future.value(cached);
    }

    final pending = _pendingLoad;
    if (pending != null) {
      return pending;
    }

    final loadFuture = _loadInternal();
    _pendingLoad = loadFuture;
    return loadFuture;
  }

  static Future<TileAtlasData> _loadInternal() async {
    try {
      final jsonRaw = await rootBundle.loadString(atlasJsonAssetPath);
      final decoded = jsonDecode(jsonRaw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Tile atlas JSON root must be an object');
      }

      final framesJson = decoded['frames'];
      if (framesJson is! Map<String, dynamic>) {
        throw const FormatException('Tile atlas JSON "frames" must be an object');
      }

      final atlasBytes = await rootBundle.load(atlasImageAssetPath);
      final image = await _decodeImage(atlasBytes);

      final frames = <String, TileAtlasFrame>{};
      for (final entry in framesJson.entries) {
        final frameData = entry.value;
        if (frameData is! Map<String, dynamic>) {
          continue;
        }

        final frameRect = _readRect(frameData['frame']);
        final spriteSourceRect = _readRect(frameData['spriteSourceSize']);
        final sourceSize = _readSize(frameData['sourceSize']);
        final rotated = frameData['rotated'] == true;

        frames[entry.key] = TileAtlasFrame(
          image: image,
          frameRect: frameRect,
          spriteSourceRect: spriteSourceRect,
          sourceSize: sourceSize,
          rotated: rotated,
        );
      }

      final data = TileAtlasData(frames: frames);
      _cachedData = data;
      _pendingLoad = null;
      return data;
    } catch (e) {
      _pendingLoad = null;
      rethrow;
    }
  }

  static Future<ui.Image> _decodeImage(ByteData bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
    );
    try {
      final frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } finally {
      codec.dispose();
    }
  }

  static ui.Rect _readRect(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Expected rect object with x/y/w/h');
    }

    return ui.Rect.fromLTWH(
      _readNum(value['x']),
      _readNum(value['y']),
      _readNum(value['w']),
      _readNum(value['h']),
    );
  }

  static ui.Size _readSize(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Expected size object with w/h');
    }

    return ui.Size(
      _readNum(value['w']),
      _readNum(value['h']),
    );
  }

  static double _readNum(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    throw const FormatException('Expected numeric atlas field');
  }
}
