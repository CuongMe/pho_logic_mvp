import 'dart:ui' show Canvas;
import 'package:flame/components.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../stages/stage_data.dart';
import 'board_game.dart';

/// Component that renders a single bed sprite (background layer)
class BedComponent extends SpriteComponent with HasGameReference<BoardGame> {
  final Coord coord;
  final BedType bedType;
  final double tileSize;
  final Vector2 Function(Coord) coordToWorld;

  BedComponent({
    required this.coord,
    required this.bedType,
    required this.tileSize,
    required this.coordToWorld,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Load sprite from bed type definition
    // JSON has: "assets/boards/beds/tile_bed_default.png"
    // Strip 'assets/' prefix since game.images.prefix is set to 'assets/'
    // So: "boards/beds/tile_bed_default.png" + prefix = "assets/boards/beds/tile_bed_default.png" ✓
    // Strip 'assets/' prefix if present
    String assetPath = bedType.file;
    if (assetPath.startsWith('assets/')) {
      assetPath = assetPath.substring(7); // Remove 'assets/' (7 chars)
    }
    try {
      // Load sprite using game's images cache
      // HasGameReference mixin provides access to game.images
      final image = await game.images.load(assetPath);
      sprite = Sprite(image);
    } catch (e) {
      // Log error for debugging
      DebugLogger.error('Failed to load bed sprite: ${bedType.file} (processed: $assetPath)', category: 'BedComponent');
      DebugLogger.error('Error: $e', category: 'BedComponent');
      rethrow;
    }
    
    // Set size to match tile size
    size = Vector2.all(tileSize);
    
    // Position at the center of the grid cell
    position = coordToWorld(coord);
    anchor = Anchor.center;
    
    // Beds are background layer, so render below tiles
    priority = 0;
  }

  @override
  void update(double dt) {
    // Skip update entirely - beds are static and never change
    // This saves ~50 function calls per frame on Windows
  }

}
