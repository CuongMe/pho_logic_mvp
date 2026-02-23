import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../board/board_game.dart';
import '../board/tile_component.dart';
import '../../audio/sfx_manager.dart';

/// Visual effects for Sticky Rice Bomb Duo (103+103 combo)
/// Implements "full-screen overlay + dual tile pulse" sequence
/// VFX only - does NOT mutate gridModel or call syncFromModel
class StickyRiceDuoVfx {
  // Timing constants
  static const double _stepDuration = 0.4; // Duration for each step (400ms)
  static const double _delayBetweenSteps = 0.15; // Clear delay between steps (150ms)

  /// Play the Sticky Rice Bomb Duo VFX
  /// 
  /// Parameters:
  /// - game: The BoardGame instance
  /// - tileA: The first tile component for the Sticky Rice Bomb
  /// - tileB: The second tile component for the Sticky Rice Bomb
  /// - activationCells: Set of coords that will be cleared (union of both bombs)
  /// 
  /// Returns: Future that completes when VFX is done
  static Future<void> play({
    required BoardGame game,
    required TileComponent tileA,
    required TileComponent tileB,
    required Set<Coord> activationCells,
  }) async {
    DebugLogger.vfx('Starting Duo VFX at coords=${tileA.coord}, ${tileB.coord}', vfxType: 'StickyRiceDuo');
    DebugLogger.vfx('Will clear ${activationCells.length} tiles', vfxType: 'StickyRiceDuo');
    
    // Play gong sound for 103+103 combo
    SfxManager.instance.playConfigured(SfxType.gong);
    
    // Safety check: abort if either tile is removed
    if (tileA.isRemoved || tileB.isRemoved || 
        !game.children.contains(tileA) || !game.children.contains(tileB)) {
      DebugLogger.vfx('One or both bomb tiles removed, aborting', vfxType: 'StickyRiceDuo');
      return;
    }
    
    // ===== SEQUENTIAL ANIMATION WITH DELAYS BETWEEN STEPS =====
    DebugLogger.vfx('Starting sequential duo VFX with delays between steps', vfxType: 'StickyRiceDuo');
    
    // Store base scales for relative pulse
    final baseScaleA = tileA.scale.clone();
    final baseScaleB = tileB.scale.clone();
    
    // Remove any existing effects on both tiles
    for (final tile in [tileA, tileB]) {
      final effectsToRemove = <Component>[];
      for (final child in tile.children) {
        if (child is Effect) {
          effectsToRemove.add(child);
        }
      }
      for (final effect in effectsToRemove) {
        effect.removeFromParent();
      }
    }
    
    // ===== STEP 1: Black tint overlay effect on both tiles =====
    DebugLogger.vfx('STEP 1: Black tint overlay on both tiles', vfxType: 'StickyRiceDuo');
    
    final tintA = SequenceEffect([
      ColorEffect(
        Colors.black,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.0,
        opacityTo: 0.75,
      ),
      ColorEffect(
        Colors.black,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeInOut,
        ),
        opacityFrom: 0.75,
        opacityTo: 0.0,
      ),
    ]);
    
    final tintB = SequenceEffect([
      ColorEffect(
        Colors.black,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.0,
        opacityTo: 0.75,
      ),
      ColorEffect(
        Colors.black,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.75,
        opacityTo: 0.0,
      ),
    ]);
    
    tileA.add(tintA);
    tileB.add(tintB);
    
    // Wait for tint effects to complete
    try {
      await Future.wait([tintA.completed, tintB.completed]).timeout(
        Duration(milliseconds: (_stepDuration * 1000).round() + 200),
        onTimeout: () {
          DebugLogger.warn('Tint step timeout', category: 'StickyRiceDuoVfx');
          return <void>[];
        },
      );
    } catch (e) {
      DebugLogger.error('Tint step error: $e', category: 'StickyRiceDuoVfx');
    }
    
    // Delay between steps
    await Future.delayed(Duration(milliseconds: (_delayBetweenSteps * 1000).round()));
    
    // ===== STEP 2: Glow effect on both tiles =====
    DebugLogger.vfx('STEP 2: Glow effect on both tiles', vfxType: 'StickyRiceDuo');
    
    final glowA = SequenceEffect([
      ColorEffect(
        const Color.fromARGB(255, 8, 8, 8),
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.0,
        opacityTo: 0.6,
      ),
      ColorEffect(
        const Color.fromARGB(255, 7, 7, 7),
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.6,
        opacityTo: 0.0,
      ),
    ]);
    
    final glowB = SequenceEffect([
      ColorEffect(
        const Color.fromARGB(255, 19, 17, 17),
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.0,
        opacityTo: 0.6,
      ),
      ColorEffect(
        const Color.fromARGB(255, 17, 16, 16),
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
        opacityFrom: 0.6,
        opacityTo: 0.0,
      ),
    ]);
    
    tileA.add(glowA);
    tileB.add(glowB);
    
    // Wait for glow effects to complete
    try {
      await Future.wait([glowA.completed, glowB.completed]).timeout(
        Duration(milliseconds: (_stepDuration * 1000).round() + 200),
        onTimeout: () {
          DebugLogger.warn('Glow step timeout', category: 'StickyRiceDuoVfx');
          return <void>[];
        },
      );
    } catch (e) {
      DebugLogger.error('Glow step error: $e', category: 'StickyRiceDuoVfx');
    }
    
    // Delay between steps
    await Future.delayed(Duration(milliseconds: (_delayBetweenSteps * 1000).round()));
    
    // ===== STEP 3: Scale pulse on both tiles =====
    DebugLogger.vfx('STEP 3: Scale pulse on both tiles', vfxType: 'StickyRiceDuo');
    
    final pulseA = SequenceEffect([
      ScaleEffect.to(
        baseScaleA * 1.12,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
      ),
      ScaleEffect.to(
        baseScaleA,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
      ),
    ]);
    
    final pulseB = SequenceEffect([
      ScaleEffect.to(
        baseScaleB * 1.12,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
      ),
      ScaleEffect.to(
        baseScaleB,
        EffectController(
          duration: _stepDuration / 2,
          curve: Curves.easeOut,
        ),
      ),
    ]);
    
    tileA.add(pulseA);
    tileB.add(pulseB);
    
    // Wait for pulse effects to complete
    try {
      await Future.wait([pulseA.completed, pulseB.completed]).timeout(
        Duration(milliseconds: (_stepDuration * 1000).round() + 200),
        onTimeout: () {
          DebugLogger.warn('Pulse step timeout', category: 'StickyRiceDuoVfx');
          return <void>[];
        },
      );
    } catch (e) {
      DebugLogger.error('Pulse step error: $e', category: 'StickyRiceDuoVfx');
    }
    
    // ===== Complete =====
    DebugLogger.vfx('All steps complete: Duo VFX finished', vfxType: 'StickyRiceDuo');
    DebugLogger.vfx('BoardController should now clear activationCells and call syncFromModel', vfxType: 'StickyRiceDuo');
    
    // Play celebration sound after completing the duo combo VFX
    SfxManager.instance.play(SfxType.yayCheer);
    
    // Return - BoardController will handle clearing activationCells and calling syncFromModel
    // VFX does NOT mutate gridModel - only visual effects
  }
}
