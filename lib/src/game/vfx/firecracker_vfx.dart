import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../board/board_game.dart';
import '../board/tile_component.dart';
import '../board/match_burst_particle.dart';
import '../../audio/sfx_manager.dart';

/// Visual effects for Firecracker (104) special tile
/// Implements a scaling explosion effect that starts small and expands to clear a 3x3 area
class FirecrackerVfx {
  /// Play the Firecracker explosion VFX
  /// 
  /// Parameters:
  /// - game: The BoardGame instance
  /// - tile: The tile component for the Firecracker (passed directly to avoid coord lookup issues)
  /// 
  /// Must abort quietly if TileComponent is null/removed
  static Future<void> play({
    required BoardGame game,
    required TileComponent tile,
  }) async {
    DebugLogger.vfx('Starting explosion effect at coord=${tile.coord}, instanceId=${tile.instanceId}', vfxType: 'Firecracker');
    
    // Play firecracker sound immediately (fire-and-forget)
    SfxManager.instance.play(SfxType.firecracker);
    
    DebugLogger.vfx('Tile found, starting explosion animation', vfxType: 'Firecracker');
    
    // Store original position (center of the firecracker tile)
    final centerPosition = tile.position.clone();
    
    // Load firecracker particle sprite
    String assetPath = 'sprites/particles/firecracker_particle.png';
    Sprite? firecrackerSprite;
    try {
      final image = await game.images.load(assetPath);
      firecrackerSprite = Sprite(image);
    } catch (e) {
      DebugLogger.error('Failed to load firecracker sprite: $e', category: 'FirecrackerVfx');
      return;
    }
    
    // Calculate target size: needs to cover 3x3 area (3 tiles)
    // Make it bigger for more visual impact
    final targetSize = game.tileSize * 5.0; // 5x for bigger particle
    
    // Start size: very small (10% of tile size)
    final startSize = game.tileSize * 0.1;
    
    // Create firecracker particle component
    // IMPORTANT: Each call creates a NEW component - do NOT reuse or clear existing ones
    // This allows multiple firecracker explosions to play simultaneously (e.g., 104+104 combo)
    final firecracker = SpriteComponent(
      sprite: firecrackerSprite,
      size: Vector2(startSize, startSize),
      anchor: Anchor.center,
    )
      ..position = centerPosition.clone()
      ..priority = 15; // Render above tiles but below UI
    
    // Add this specific instance to the game
    // Multiple instances can coexist (each has its own lifecycle)
    game.add(firecracker);
    
    // Animation durations
    final expandDuration = 0.3; // 300ms to expand (faster, more punchy)
    final fadeOutDuration = 0.25; // 250ms fade out (smoother dissipation)
    final fadeStartAt = 0.7; // Start fade at 70% through expansion (overlap for natural feel)
    
    // Create size effect: scale from small to large
    final sizeEffect = SizeEffect.to(
      Vector2(targetSize, targetSize),
      EffectController(
        duration: expandDuration,
        curve: Curves.easeOut,
      ),
    );
    
    firecracker.add(sizeEffect);
    
    // Calculate which tiles will be cleared (3x3 area) for particle spawning
    final coord = tile.coord;
    final clearedCoords = <Coord>[];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        final row = coord.row + dr;
        final col = coord.col + dc;
        if (row >= 0 && row < game.rows && col >= 0 && col < game.cols) {
          final cellCoord = Coord(row, col);
          if (game.isPlayableCell(cellCoord)) {
            clearedCoords.add(cellCoord);
          }
        }
      }
    }
    
    // Spawn particles at visual timing (60% through expansion) - does NOT mutate GridModel
    // All tile clearing is handled by BoardController._emitCellsCleared()
    // Particles spawn when explosion is near visual peak for better impact
    final clearStartDelay = expandDuration * 0.6;
    
    // Capture tile types BEFORE clearing (for particle spawning)
    final tileTypesByCoord = <Coord, int>{};
    for (final clearCoord in clearedCoords) {
      if (clearCoord.row >= 0 && clearCoord.row < game.rows &&
          clearCoord.col >= 0 && clearCoord.col < game.cols) {
        final cell = game.gridModel.cells[clearCoord.row][clearCoord.col];
        if (cell.tileTypeId != null) {
          tileTypesByCoord[clearCoord] = cell.tileTypeId!;
        }
      }
    }
    
    // Prevent double bursts: Firecracker VFX spawns bursts timed to explosion,
    // so suppress the automatic burst spawning from BoardGame callback for these coords.
    game.suppressAutoBurstForCoords(tileTypesByCoord.keys);
    
    Future.delayed(Duration(milliseconds: (clearStartDelay * 1000).round()), () async {
      // Clear tiles at exact burst moment (synchronized with visual impact)
      // This ensures tiles disappear when particles burst, not before or after
      await game.clearTilesAtCoords(tileTypesByCoord.keys.toSet());
      
      // Spawn burst effects for all tiles simultaneously as explosion expands
      // Use captured tile types (tiles were just cleared)
      for (final entry in tileTypesByCoord.entries) {
        final clearCoord = entry.key;
        final tileTypeId = entry.value;
        final tilePosition = game.coordToWorld(clearCoord);
        
        // Get crumb sprite for this tile type (if it's a regular tile < 101)
        Sprite? crumbSprite;
        if (tileTypeId < 101) {
          crumbSprite = game.crumbParticleByTileId[tileTypeId];
        }
        
        // Get sparkle sprite
        final sparkleSprite = game.sparkleSpriteForVfx;
        
        // Check if this is a special tile (>= 101)
        final isSpecialTile = tileTypeId >= 101;
        
        // Spawn burst effect(s) at the tile position
        if (crumbSprite != null || sparkleSprite != null) {
          if (isSpecialTile) {
            // Special tiles get multiple bursts for more visual impact
            for (int i = 0; i < 3; i++) {
              final offsetX = (i - 1) * game.tileSize * 0.15;
              final offsetY = (i - 1) * game.tileSize * 0.15;
              final burstPosition = tilePosition + Vector2(offsetX, offsetY);
              
              spawnMatchBurst(
                game: game,
                center: burstPosition,
                tileSize: game.tileSize,
                crumbSprite: crumbSprite,
                sparkleSprite: sparkleSprite,
                isSpecialClear: true,
              );
            }
          } else {
            // Regular tiles get single burst
            spawnMatchBurst(
              game: game,
              center: tilePosition,
              tileSize: game.tileSize,
              crumbSprite: crumbSprite,
              sparkleSprite: sparkleSprite,
              isSpecialClear: true,
            );
          }
        }
      }
    });
    
    // Start fade at 70% through expansion (overlap for natural dissipation)
    final fadeStartDelay = expandDuration * fadeStartAt;
    await Future.delayed(Duration(milliseconds: (fadeStartDelay * 1000).round()));
    
    // Fade out (overlaps with last 30% of expansion)
    final fadeEffect = OpacityEffect.to(
      0.0,
      EffectController(
        duration: fadeOutDuration,
        curve: Curves.easeIn,
      ),
    );
    
    firecracker.add(fadeEffect);
    
    // Wait for fade out, then remove
    try {
      await fadeEffect.completed.timeout(
        Duration(milliseconds: (fadeOutDuration * 1000).round() + 50),
        onTimeout: () {
          // Timeout - component may have been removed
        },
      );
    } catch (e) {
      // Effect may have been removed
    }
    
    // Remove ONLY this specific firecracker particle instance
    // Do NOT remove other active firecracker effects - each instance manages its own lifecycle
    if (!firecracker.isRemoved && game.children.contains(firecracker)) {
      firecracker.removeFromParent();
    }
    
    DebugLogger.vfx('Explosion effect completed at ${tile.coord}', vfxType: 'Firecracker');
  }
}
