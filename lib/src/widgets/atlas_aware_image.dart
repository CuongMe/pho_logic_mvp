import 'package:flutter/material.dart';

import '../game/assets/tile_atlas.dart';

class AtlasAwareImage extends StatelessWidget {
  final String assetPath;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  const AtlasAwareImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (!TileAtlasLoader.isLikelyAtlasManagedAsset(assetPath)) {
      return Image.asset(
        assetPath,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }

    return FutureBuilder<TileAtlasData>(
      future: TileAtlasLoader.load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null) {
          final frame = TileAtlasLoader.frameForAssetPath(data, assetPath);
          if (frame != null && !frame.rotated) {
            return CustomPaint(
              painter: _AtlasFramePainter(
                frame: frame,
                fit: fit,
              ),
              child: const SizedBox.expand(),
            );
          }
        }

        if (snapshot.connectionState == ConnectionState.done) {
          return Image.asset(
            assetPath,
            fit: fit,
            errorBuilder: errorBuilder,
          );
        }

        return const SizedBox.expand();
      },
    );
  }
}

class _AtlasFramePainter extends CustomPainter {
  final TileAtlasFrame frame;
  final BoxFit fit;

  const _AtlasFramePainter({
    required this.frame,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    if (frame.sourceSize.width <= 0 || frame.sourceSize.height <= 0) {
      return;
    }

    final fitted = applyBoxFit(fit, frame.sourceSize, size);
    final fullDestination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    final scaleX = fullDestination.width / frame.sourceSize.width;
    final scaleY = fullDestination.height / frame.sourceSize.height;
    final spriteSource = frame.spriteSourceRect;

    final destinationRect = Rect.fromLTWH(
      fullDestination.left + spriteSource.left * scaleX,
      fullDestination.top + spriteSource.top * scaleY,
      spriteSource.width * scaleX,
      spriteSource.height * scaleY,
    );

    canvas.drawImageRect(
      frame.image,
      frame.frameRect,
      destinationRect,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _AtlasFramePainter oldDelegate) {
    return oldDelegate.frame != frame || oldDelegate.fit != fit;
  }
}
