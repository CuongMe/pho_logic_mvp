import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../board/board_game.dart';
import '../board/tile_component.dart';
import '../board/match_burst_particle.dart';
import '../../audio/sfx_manager.dart';

/// Visual effects for Party Popper (101/102) special tiles
/// Implements a sprite shake effect using SequenceEffect of MoveByEffect offsets
/// Then spawns a projectile that shoots out in the direction of the party popper orientation
class PartyPopperVfx {
  /// Play the Party Popper shake VFX
  /// 
  /// Parameters:
  /// - game: The BoardGame instance
  /// - coord: The coord where the Party Popper is located
  /// - partyPopperType: The type of party popper (101 = horizontal, 102 = vertical)
  /// 
  /// Must abort quietly if TileComponent is null/removed
  static Future<void> play({
    required BoardGame game,
    required TileComponent tile,
    required int partyPopperType,
  }) async {
    DebugLogger.vfx('Starting shake effect at coord=${tile.coord}, instanceId=${tile.instanceId}', vfxType: 'PartyPopper');
    
    // Play party popper sound immediately (fire-and-forget)
    SfxManager.instance.play(SfxType.partyPopperLaunch);
    
    DebugLogger.vfx('Tile found, starting shake animation', vfxType: 'PartyPopper');
    
    // Store original position
    final originalPosition = tile.position.clone();
    
    // Create shake effect: SequenceEffect of several tiny MoveByEffect offsets
    // Reduced shake values to minimize drift
    final random = math.Random();
    final shakeSteps = <Effect>[];
    
    // Generate 8-12 shake steps for a more visible shake effect
    final numShakes = 8 + random.nextInt(5); // 8-12 shakes
    
    for (int i = 0; i < numShakes; i++) {
      // Reduced offset between ±1.5 and ±3 pixels (smaller to reduce drift)
      final offsetX = (1.5 + random.nextDouble() * 1.5) * (random.nextBool() ? 1 : -1);
      final offsetY = (1.5 + random.nextDouble() * 1.5) * (random.nextBool() ? 1 : -1);
      
      // Random duration between 30-50ms
      final duration = 0.030 + random.nextDouble() * 0.020; // 30-50ms
      
      // Create offset vector
      final offset = Vector2(offsetX, offsetY);
      
      shakeSteps.add(
        MoveByEffect(
          offset,
          EffectController(duration: duration),
        ),
      );
    }
    
    // Final step: restore exact original position
    shakeSteps.add(
      MoveToEffect(
        originalPosition,
        EffectController(duration: 0.03), // 30ms to restore
      ),
    );
    
    // Create sequence effect
    final shakeEffect = SequenceEffect(shakeSteps);
    
    DebugLogger.vfx('Adding shake effect with $numShakes shakes', vfxType: 'PartyPopper');
    tile.add(shakeEffect);
    
    // Wait for effect to complete (with timeout)
    // Calculate more accurate total duration based on actual shake durations
    final totalDuration = numShakes * 0.040 + 0.03; // Average 40ms per shake + restore
    DebugLogger.vfx('Waiting for shake to complete (estimated ${totalDuration}s)', vfxType: 'PartyPopper');
    try {
      await shakeEffect.completed.timeout(
        Duration(milliseconds: (totalDuration * 1000).round() + 200),
        onTimeout: () {
          // Timeout - component may have been removed
          DebugLogger.warn('Shake effect timeout', category: 'PartyPopperVfx');
        },
      );
    } catch (e) {
      // Effect may have been removed - abort quietly
      DebugLogger.error('Shake effect error: $e', category: 'PartyPopperVfx');
    }
    
    // Ensure position is restored (safety check)
    final coord = tile.coord; // Get coord from tile
    if (!tile.isRemoved && game.children.contains(tile)) {
      tile.position = originalPosition;
      DebugLogger.vfx('Shake completed, position restored at $coord', vfxType: 'PartyPopper');
    } else {
      DebugLogger.vfx('Tile was removed during shake at $coord', vfxType: 'PartyPopper');
      return; // Can't spawn projectile if tile is gone
    }
    
    // Calculate activation cells based on party popper type
    // 101 = horizontal (clears row), 102 = vertical (clears column)
    // Stop projectiles when they hit blockers
    final activationCells = <Coord>{};
    
    if (partyPopperType == 101) {
      // Horizontal: get all cells in the same row, but stop at blockers
      // Left direction (decreasing col)
      for (int col = coord.col - 1; col >= 0; col--) {
        final cellCoord = Coord(coord.row, col);
        // Stop if cell is not playable (void)
        if (!game.isPlayableCell(cellCoord)) break;
        // Stop if cell has a blocker (projectile can't pass)
        final cell = game.gridModel.cells[cellCoord.row][cellCoord.col];
        if (cell.isBlocked) break;
        activationCells.add(cellCoord);
      }
      // Right direction (increasing col)
      for (int col = coord.col + 1; col < game.cols; col++) {
        final cellCoord = Coord(coord.row, col);
        // Stop if cell is not playable (void)
        if (!game.isPlayableCell(cellCoord)) break;
        // Stop if cell has a blocker (projectile can't pass)
        final cell = game.gridModel.cells[cellCoord.row][cellCoord.col];
        if (cell.isBlocked) break;
        activationCells.add(cellCoord);
      }
    } else if (partyPopperType == 102) {
      // Vertical: get all cells in the same column, but stop at blockers
      // Up direction (decreasing row)
      for (int row = coord.row - 1; row >= 0; row--) {
        final cellCoord = Coord(row, coord.col);
        // Stop if cell is not playable (void)
        if (!game.isPlayableCell(cellCoord)) break;
        // Stop if cell has a blocker (projectile can't pass)
        final cell = game.gridModel.cells[cellCoord.row][cellCoord.col];
        if (cell.isBlocked) break;
        activationCells.add(cellCoord);
      }
      // Down direction (increasing row)
      for (int row = coord.row + 1; row < game.rows; row++) {
        final cellCoord = Coord(row, coord.col);
        // Stop if cell is not playable (void)
        if (!game.isPlayableCell(cellCoord)) break;
        // Stop if cell has a blocker (projectile can't pass)
        final cell = game.gridModel.cells[cellCoord.row][cellCoord.col];
        if (cell.isBlocked) break;
        activationCells.add(cellCoord);
      }
    }
    
    // Spawn projectiles in both directions after shake animation
    // VFX will clear tiles as projectiles reach them (exact visual timing)
    await _spawnProjectiles(
      game: game,
      startPosition: originalPosition,
      partyPopperType: partyPopperType,
      coord: coord,
      activationCells: activationCells,
    );
    
    // Clear the Party Popper tile itself after all projectiles complete
    // (it's a special tile, so it won't be counted as a victim for objectives)
    await game.clearTilesAtCoords({coord});
  }
  
  /// Spawn and animate party popper projectiles in both directions
  /// Clears tiles as projectiles pass through them
  static Future<void> _spawnProjectiles({
    required BoardGame game,
    required Vector2 startPosition,
    required int partyPopperType,
    required Coord coord,
    required Set<Coord> activationCells,
  }) async {
    // Load projectile sprite
    String assetPath = 'sprites/particles/party_popper_projectile.png';
    Sprite? projectileSprite;
    try {
      final image = await game.images.load(assetPath);
      projectileSprite = Sprite(image);
    } catch (e) {
      DebugLogger.error('Failed to load projectile sprite: $e', category: 'PartyPopperVfx');
      return;
    }
    
    // Organize activation cells by direction
    List<Coord> leftCells = [];
    List<Coord> rightCells = [];
    List<Coord> upCells = [];
    List<Coord> downCells = [];
    
    if (partyPopperType == 101) {
      // Horizontal: separate into left and right
      for (final cellCoord in activationCells) {
        if (cellCoord.row == coord.row) {
          if (cellCoord.col < coord.col) {
            leftCells.add(cellCoord);
          } else if (cellCoord.col > coord.col) {
            rightCells.add(cellCoord);
          }
        }
      }
      // Sort: left cells descending (farthest first), right cells ascending
      leftCells.sort((a, b) => b.col.compareTo(a.col));
      rightCells.sort((a, b) => a.col.compareTo(b.col));
    } else if (partyPopperType == 102) {
      // Vertical: separate into up and down
      for (final cellCoord in activationCells) {
        if (cellCoord.col == coord.col) {
          if (cellCoord.row < coord.row) {
            upCells.add(cellCoord);
          } else if (cellCoord.row > coord.row) {
            downCells.add(cellCoord);
          }
        }
      }
      // Sort: up cells descending (farthest first), down cells ascending
      upCells.sort((a, b) => b.row.compareTo(a.row));
      downCells.sort((a, b) => a.row.compareTo(b.row));
    }
    
    // Spawn projectiles in both directions
    final futures = <Future<void>>[];
    
    if (partyPopperType == 101) {
      // Horizontal: left and right
      if (leftCells.isNotEmpty) {
        futures.add(_spawnProjectileInDirection(
          game: game,
          sprite: projectileSprite,
          startPosition: startPosition,
          direction: Vector2(-1, 0), // Left
          rotationAngle: math.pi, // 180 degrees (flip horizontally)
          targetCoords: leftCells,
          coordToWorld: game.coordToWorld,
        ));
      }
      if (rightCells.isNotEmpty) {
        futures.add(_spawnProjectileInDirection(
          game: game,
          sprite: projectileSprite,
          startPosition: startPosition,
          direction: Vector2(1, 0), // Right
          rotationAngle: 0.0, // Default orientation
          targetCoords: rightCells,
          coordToWorld: game.coordToWorld,
        ));
      }
    } else if (partyPopperType == 102) {
      // Vertical: up and down
      if (upCells.isNotEmpty) {
        futures.add(_spawnProjectileInDirection(
          game: game,
          sprite: projectileSprite,
          startPosition: startPosition,
          direction: Vector2(0, -1), // Up
          rotationAngle: -math.pi / 2, // -90 degrees (rotate counter-clockwise)
          targetCoords: upCells,
          coordToWorld: game.coordToWorld,
        ));
      }
      if (downCells.isNotEmpty) {
        futures.add(_spawnProjectileInDirection(
          game: game,
          sprite: projectileSprite,
          startPosition: startPosition,
          direction: Vector2(0, 1), // Down
          rotationAngle: math.pi / 2, // 90 degrees clockwise
          targetCoords: downCells,
          coordToWorld: game.coordToWorld,
        ));
      }
    }
    
    // Wait for all projectiles to complete
    await Future.wait(futures);
  }
  
  /// Spawn a single projectile in a direction and clear tiles as it passes through
  static Future<void> _spawnProjectileInDirection({
    required BoardGame game,
    required Sprite sprite,
    required Vector2 startPosition,
    required Vector2 direction,
    required double rotationAngle,
    required List<Coord> targetCoords,
    required Vector2 Function(Coord) coordToWorld,
  }) async {
    if (targetCoords.isEmpty) return;
    
    // Prevent double bursts: VFX will spawn bursts timed to projectile,
    // so suppress the automatic burst spawning from BoardGame callback for these coords.
    game.suppressAutoBurstForCoords(targetCoords);
    
    // Calculate target position (end of the path)
    final endCoord = targetCoords.last;
    final targetPosition = coordToWorld(endCoord);
    
    // Create projectile component
    final projectile = SpriteComponent(
      sprite: sprite,
      size: Vector2(game.tileSize * 1.2, game.tileSize * 1.2),
      anchor: Anchor.center,
    )
      ..position = startPosition.clone()
      ..angle = rotationAngle
      ..priority = 15; // Render above tiles but below UI
    
    game.add(projectile);
    
    // Calculate travel distance
    final travelDistance = (targetPosition - startPosition).length;
    
    // Use a fixed speed (pixels per second) so all projectiles move at the same visual speed
    // regardless of distance traveled
    const double projectileSpeed = 600.0; // pixels per second (slower)
    
    // Calculate duration based on distance and speed
    final moveDuration = travelDistance / projectileSpeed;
    
    // Animate projectile moving
    final moveEffect = MoveToEffect(
      targetPosition,
      EffectController(duration: moveDuration, curve: Curves.linear),
    );
    
    projectile.add(moveEffect);
    
    // Capture tile types BEFORE clearing (for particle spawning)
    final tileTypesByCoord = <Coord, int>{};
    for (final clearCoord in targetCoords) {
      if (clearCoord.row >= 0 && clearCoord.row < game.rows &&
          clearCoord.col >= 0 && clearCoord.col < game.cols) {
        final cell = game.gridModel.cells[clearCoord.row][clearCoord.col];
        if (cell.tileTypeId != null) {
          tileTypesByCoord[clearCoord] = cell.tileTypeId!;
        }
      }
    }
    
    // Clear tiles and spawn particles as projectile passes through them
    // VFX clears tiles via game.clearTilesAtCoords() at exact projectile timing
    // This ensures tiles disappear exactly when projectile touches them
    // Objectives count correctly via _emitCellsCleared(), particles spawn here for visual timing
    for (int i = 0; i < targetCoords.length; i++) {
      final clearCoord = targetCoords[i];
      // Calculate delay based on when projectile reaches this tile's position
      final tilePosition = coordToWorld(clearCoord);
      final distanceToTile = (tilePosition - startPosition).length;
      final clearDelay = distanceToTile / projectileSpeed; // Exact timing when projectile hits
      final burstDelay = clearDelay + 0.03; // Burst spawns 30ms after clearing
      
      // Clear tile as projectile reaches it (exact visual timing)
      Future.delayed(Duration(milliseconds: (clearDelay * 1000).round()), () async {
        await game.clearTilesAtCoords({clearCoord});
      });
      
      // Spawn burst effect slightly after clearing
      Future.delayed(Duration(milliseconds: (burstDelay * 1000).round()), () async {
        // Use captured tile type (tile may already be cleared)
        final tileTypeId = tileTypesByCoord[clearCoord];
        if (tileTypeId != null) {
          final tilePosition = coordToWorld(clearCoord);
          
          // Get crumb sprite for this tile type (if it's a regular tile < 101)
          Sprite? crumbSprite;
          if (tileTypeId < 101) {
            crumbSprite = game.crumbParticleByTileId[tileTypeId];
          }
          
          // Get sparkle sprite
          final sparkleSprite = game.sparkleSpriteForVfx;
          
          // Spawn burst effect at the cleared tile position
          if (crumbSprite != null || sparkleSprite != null) {
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
      });
    }
    
    // Wait for animation to complete, then remove
    try {
      await moveEffect.completed.timeout(
        Duration(milliseconds: (moveDuration * 1000).round() + 100),
        onTimeout: () {
          // Timeout - component may have been removed
        },
      );
    } catch (e) {
      // Effect may have been removed
    }
    
    // Remove projectile
    if (!projectile.isRemoved && game.children.contains(projectile)) {
      projectile.removeFromParent();
    }
  }
}
