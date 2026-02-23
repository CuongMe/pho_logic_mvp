import 'package:flame/components.dart';
import '../model/coord.dart';
import '../model/grid_model.dart';
import '../utils/debug_logger.dart';
import 'board_game.dart';

/// Component that renders a blocker overlay on a cell
/// Renders above tiles to show that the cell is blocked
class BlockerComponent extends SpriteComponent
    with HasGameReference<BoardGame> {
  final Coord coord;
  final BlockerType blockerType;
  final String filePath; // Path to blocker sprite (from JSON)
  final double tileSize;
  final Vector2 Function(Coord) coordToWorld;

  // Scale factor for blocker sprite (should cover the tile)
  static const double _blockerScale = 1.3;

  BlockerComponent({
    required this.coord,
    required this.blockerType,
    required this.filePath,
    required this.tileSize,
    required this.coordToWorld,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set size to match tile
    size = Vector2.all(tileSize * _blockerScale);

    // Center on the tile
    anchor = Anchor.center;
    position = coordToWorld(coord);

    // Set priority so blockers render above tiles (priority 10)
    priority = 15;

    // Load blocker sprite based on type
    await _loadBlockerSprite();
  }

  Future<void> _loadBlockerSprite() async {
    try {
      // Strip 'assets/' prefix if present (game.images.prefix handles it)
      String assetPath = filePath;
      if (assetPath.startsWith('assets/')) {
        assetPath = assetPath.substring('assets/'.length);
      }

      final image = await game.images.load(assetPath);
      sprite = Sprite(image);
    } catch (e) {
      DebugLogger.error('Failed to load blocker sprite from $filePath: $e',
          category: 'BlockerComponent');
    }
  }

  @override
  void update(double dt) {
    // Skip update entirely - blockers are static until they break
    // Breaking is handled by VFX system, not update loop
    // This saves ~10 function calls per frame on Windows
  }
}
