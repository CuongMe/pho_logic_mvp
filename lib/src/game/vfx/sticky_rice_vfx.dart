import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../board/board_game.dart';
import '../board/tile_component.dart';
import '../board/match_burst_particle.dart';
import '../../audio/sfx_manager.dart';

/// Visual effects for Sticky Rice Bomb (103) special tile
/// Implements "bomb warning → explode outward" sequence
/// VFX only - does NOT mutate gridModel or call syncFromModel
class StickyRiceVfx {
  /// List of random colors for tiles about to be destroyed
  static const List<Color> _glowColors = [
    Color(0xFF9B59B6), // Purple
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFFF9800), // Orange
    Color(0xFF4CAF50), // Green
    Color(0xFF2196F3), // Blue
  ];

  // Timing constants (tunable)
  static const double _warnBombDur = 0.85; // Duration for bomb warning (pulse + grayscale)
  static const double _perTileTintDur = 0.3; // Duration for each tile's color tint (0.35-0.5s range)
  static const double _perTileClearDur = 0.12; // Duration for each tile's clear scale effect (0.10-0.15s range)
  static const Duration _stepGap = Duration(milliseconds: 120); // Delay between sequential steps (100-150ms range)
  
  // Rate limiter for bloop sounds
  static int _bloopCount = 0;
  static int _bloopWindowStartMs = 0;
  
  /// Check if bloop is allowed based on rate limit (max bloops per second)
  static bool _allowBloop({int maxPerSec = 8}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _bloopWindowStartMs >= 1000) {
      _bloopWindowStartMs = now;
      _bloopCount = 0;
    }
    if (_bloopCount >= maxPerSec) return false;
    _bloopCount++;
    return true;
  }

  /// Play the Sticky Rice Bomb VFX
  /// 
  /// Parameters:
  /// - game: The BoardGame instance
  /// - tile: The tile component for the Sticky Rice Bomb
  /// - activationCells: Set of coords that will be cleared by this bomb
  /// 
  /// Returns: Future that completes when VFX is done
  /// BoardController should clear activationCells and call syncFromModel after this completes
  /// 
  /// Must abort quietly if TileComponent is null/removed
  static Future<void> play({
    required BoardGame game,
    required TileComponent tile,
    required Set<Coord> activationCells,
  }) async {
    DebugLogger.vfx('Starting VFX at coord=${tile.coord}, instanceId=${tile.instanceId}', vfxType: 'StickyRice');
    DebugLogger.vfx('Will clear ${activationCells.length} tiles', vfxType: 'StickyRice');
    
    // Safety check: abort if bomb tile is removed
    if (tile.isRemoved || !game.children.contains(tile)) {
      DebugLogger.vfx('Bomb tile removed, aborting', vfxType: 'StickyRice');
      return;
    }
    
    final bombCoord = tile.coord;
    final random = math.Random();
    
    // ===== PHASE 1: BOMB WARNING =====
    DebugLogger.vfx('PHASE 1: Bomb warning (tint overlay + pulse)', vfxType: 'StickyRice');
    
    // Store base scale for relative pulse
    final baseScale = tile.scale.clone();
    
    // Remove any existing ColorEffect on bomb first (avoid stacking)
    final bombEffectsToRemove = <Component>[];
    for (final child in tile.children) {
      if (child is ColorEffect) {
        bombEffectsToRemove.add(child);
      }
    }
    for (final effect in bombEffectsToRemove) {
      effect.removeFromParent();
    }
    
    // Bomb tile: Black tint overlay ColorEffect
    final bombTintEffectBlack = ColorEffect(
      Colors.black, // Black tint overlay for warning effect
      EffectController(
        duration: _warnBombDur,
        curve: Curves.easeOut,
      ),
      opacityFrom: 0.0,
      opacityTo: 0.75,
    );
    
    // Bomb tile: Slow pulse relative to base scale (baseScale → baseScale*1.10 → baseScale)
    final bombPulseEffect = SequenceEffect([
      ScaleEffect.to(
        baseScale * 1.10,
        EffectController(
          duration: _warnBombDur / 2,
          curve: Curves.easeOut,
        ),
      ),
      ScaleEffect.to(
        baseScale,
        EffectController(
          duration: _warnBombDur / 2,
          curve: Curves.easeOut,
        ),
      ),
    ]);
    
    tile.add(bombTintEffectBlack);
    tile.add(bombPulseEffect);
    
    // Wait for bomb warning to complete
    try {
      await Future.wait([
        bombTintEffectBlack.completed,
        bombPulseEffect.completed,
      ]).timeout(
        Duration(milliseconds: (_warnBombDur * 1000).round() + 200),
        onTimeout: () {
          DebugLogger.warn('Bomb warning timeout', category: 'StickyRiceVfx');
          return <void>[];
        },
      );
    } catch (e) {
      DebugLogger.error('Bomb warning error: $e', category: 'StickyRiceVfx');
    }
    
    // Safety check: abort if bomb tile removed
    if (tile.isRemoved || !game.children.contains(tile)) {
      DebugLogger.vfx('Bomb tile removed during warning, aborting', vfxType: 'StickyRice');
      return;
    }
    
    // ===== PHASE 2: SEQUENTIAL COLOR WARNING (outward) =====
    DebugLogger.vfx('PHASE 2: Sequential color warning (outward)', vfxType: 'StickyRice');
    
    // Order coords by Manhattan distance from bomb (closest → farthest)
    // Exclude bomb and optionally filter playable cells
    final orderedCoords = activationCells
        .where((c) => c != bombCoord && game.isPlayableCell(c))
        .toList();
    orderedCoords.sort((a, b) {
      final distA = (a.row - bombCoord.row).abs() + (a.col - bombCoord.col).abs();
      final distB = (b.row - bombCoord.row).abs() + (b.col - bombCoord.col).abs();
      return distA.compareTo(distB);
    });
    
    DebugLogger.vfx('Applying color effects to ${orderedCoords.length} tiles sequentially', vfxType: 'StickyRice');
    
    // Apply color effects to target tiles SEQUENTIALLY
    for (final coord in orderedCoords) {
      // Safety check: abort if bomb tile removed
      if (tile.isRemoved || !game.children.contains(tile)) {
        DebugLogger.vfx('Bomb tile removed during color warning, aborting', vfxType: 'StickyRice');
        return;
      }
      
      // Get tile component
      final targetTile = game.getTileAt(coord);
      if (targetTile == null || targetTile.isRemoved) {
        // Tile already removed or doesn't exist - skip
        continue;
      }
      
      // Remove any existing ColorEffect (ColorEffect can't stack)
      final effectsToRemove = <Component>[];
      for (final child in targetTile.children) {
        if (child is ColorEffect) {
          effectsToRemove.add(child);
        }
      }
      for (final effect in effectsToRemove) {
        effect.removeFromParent();
      }
      
      // Pick a random color
      final glowColor = _glowColors[random.nextInt(_glowColors.length)];
      
      // Apply color effect: opacityFrom 0.0 → opacityTo 0.75 over ~0.4s
      final colorEffect = ColorEffect(
        glowColor,
        EffectController(
          duration: _perTileTintDur,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.0,
        opacityTo: 0.75,
      );
      
      targetTile.add(colorEffect);
      
      // Await completion before moving to next tile
      try {
        await colorEffect.completed.timeout(
          Duration(milliseconds: (_perTileTintDur * 1000).round() + 100),
          onTimeout: () {
            DebugLogger.warn('Color effect timeout for tile at $coord', category: 'StickyRiceVfx');
          },
        );
      } catch (e) {
        DebugLogger.error('Color effect error for tile at $coord: $e', category: 'StickyRiceVfx');
      }
    }
    
    // Safety check: abort if bomb tile removed
    if (tile.isRemoved || !game.children.contains(tile)) {
      DebugLogger.vfx('Bomb tile removed after color warning, aborting', vfxType: 'StickyRice');
      return;
    }
    
    // ===== PHASE 3: SEQUENTIAL CLEAR (outward) =====
    DebugLogger.vfx('PHASE 3: Sequential clear (outward)', vfxType: 'StickyRice');
    
    // Use same ordered coords list (outward order)
    DebugLogger.vfx('Clearing ${orderedCoords.length} tiles sequentially', vfxType: 'StickyRice');
    
    // Clear each tile sequentially
    for (final coord in orderedCoords) {
      // Safety check: abort if bomb tile removed
      if (tile.isRemoved || !game.children.contains(tile)) {
        DebugLogger.vfx('Bomb tile removed during clear, aborting', vfxType: 'StickyRice');
        return;
      }
      
      // Get tile component
      final targetTile = game.getTileAt(coord);
      if (targetTile == null || targetTile.isRemoved) {
        // Tile already removed or doesn't exist - skip
        continue;
      }
      
      // Get tile type and position before clearing (for burst effect)
      final tileTypeId = targetTile.tileTypeId;
      final tilePosition = game.coordToWorld(coord);
      
      // Get crumb sprite for this tile type (if it's a regular tile < 101)
      Sprite? crumbSprite;
      if (tileTypeId < 101) {
        crumbSprite = game.crumbParticleByTileId[tileTypeId];
      }
      
      // Get sparkle sprite
      final sparkleSprite = game.sparkleSpriteForVfx;
      
      // Spawn burst effect at the tile position
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
      
      // Play bloop for each tile cleared (with rate limiter to prevent audio crackling)
      if (_allowBloop(maxPerSec: 8)) {
        SfxManager.instance.playConfigured(SfxType.bloop);
      }
      
      // Visually clear the tile using SCALE ONLY (scale to 0.01 to make it disappear)
      // NOTE: This is VFX only - does NOT mutate gridModel
      final clearScaleEffect = ScaleEffect.to(
        Vector2.all(0.01),
        EffectController(
          duration: _perTileClearDur,
          curve: Curves.easeIn,
        ),
      );
      
      targetTile.add(clearScaleEffect);
      
      // Await clear scale effect completion
      try {
        await clearScaleEffect.completed.timeout(
          Duration(milliseconds: (_perTileClearDur * 1000).round() + 100),
          onTimeout: () {
            DebugLogger.warn('Clear scale effect timeout for tile at $coord', category: 'StickyRiceVfx');
          },
        );
      } catch (e) {
        DebugLogger.error('Clear scale effect error for tile at $coord: $e', category: 'StickyRiceVfx');
      }
      
      // Add delay between tiles for clear step separation
      await Future.delayed(_stepGap);
    }
    
    // ===== PHASE 4: BOMB CLEAR (optional final pop) =====
    DebugLogger.vfx('PHASE 4: Bomb clear', vfxType: 'StickyRice');
    
    // Play celebration sound after clearing all tiles
    SfxManager.instance.play(SfxType.yayCheer);
    
    // Safety check
    if (tile.isRemoved || !game.children.contains(tile)) {
      DebugLogger.vfx('Bomb tile removed before final clear, aborting', vfxType: 'StickyRice');
      return;
    }
    
    // Get bomb position for burst
    final bombPosition = game.coordToWorld(bombCoord);
    final bombTileTypeId = tile.tileTypeId;
    
    // Get crumb sprite for bomb (if it's a regular tile < 101, though it shouldn't be)
    Sprite? crumbSprite;
    if (bombTileTypeId < 101) {
      crumbSprite = game.crumbParticleByTileId[bombTileTypeId];
    }
    
    // Get sparkle sprite
    final sparkleSprite = game.sparkleSpriteForVfx;
    
    // Spawn burst effect at bomb position
    if (crumbSprite != null || sparkleSprite != null) {
      spawnMatchBurst(
        game: game,
        center: bombPosition,
        tileSize: game.tileSize,
        crumbSprite: crumbSprite,
        sparkleSprite: sparkleSprite,
        isSpecialClear: true,
      );
    }
    
    // Visually clear bomb using SCALE ONLY (scale to 0.01 to make it disappear)
    final bombClearScaleEffect = ScaleEffect.to(
      Vector2.all(0.01),
      EffectController(
        duration: _perTileClearDur,
        curve: Curves.easeIn,
      ),
    );
    
    tile.add(bombClearScaleEffect);
    
    // Wait for bomb clear scale effect
    try {
      await bombClearScaleEffect.completed.timeout(
        Duration(milliseconds: (_perTileClearDur * 1000).round() + 100),
        onTimeout: () {
          DebugLogger.warn('Bomb clear scale effect timeout', category: 'StickyRiceVfx');
        },
      );
    } catch (e) {
      DebugLogger.error('Bomb clear scale effect error: $e', category: 'StickyRiceVfx');
    }
    
    // ===== PHASE 5: Complete =====
    DebugLogger.vfx('PHASE 5: VFX complete', vfxType: 'StickyRice');
    DebugLogger.vfx('BoardController should now clear activationCells and call syncFromModel', vfxType: 'StickyRice');
    
    // Return - BoardController will handle clearing activationCells and calling syncFromModel
    // VFX does NOT mutate gridModel - only visual effects
  }
}
