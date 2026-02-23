import 'dart:math' as math;
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import '../model/coord.dart';
import '../board/board_game.dart';
import '../board/tile_component.dart';
import '../../audio/sfx_manager.dart';

/// Visual effects for DragonFly (105) special tile
/// Sequence:
/// 1) Spin in place using RotateEffect.to (full circle rotation)
/// 2) Rotate sprite to face target using RotateEffect.to
/// 3) Fly to destination target with MoveToEffect
/// Note: Burst is spawned by the clear system, not here (to avoid double-spawning)
class DragonFlyVfx {
  /// Play the DragonFly VFX sequence
  /// 
  /// Parameters:
  /// - game: The BoardGame instance
  /// - sourceTile: The tile component for the DragonFly (passed directly to avoid coord lookup issues)
  /// - targetCoord: The coord where the DragonFly should fly to
  /// 
  /// Must abort quietly if TileComponent is null/removed
  static Future<void> play({
    required BoardGame game,
    required TileComponent sourceTile,
    required Coord targetCoord,
  }) async {
    
    // Play dragonfly sound immediately (fire-and-forget)
    SfxManager.instance.play(SfxType.dragonFlyLaunch);
    
    // Store original position and angle
    final originalPosition = sourceTile.position.clone();
    final originalAngle = sourceTile.angle;
    
    // Get target position
    final targetPosition = game.coordToWorld(targetCoord);
    
    // Step 1: Spin in place using RotateEffect.to (full circle rotation)
    // Rotate by a full circle (2*pi radians = 360 degrees) from current angle
    final spinDuration = 0.3; // 300ms
    final spinTargetAngle = originalAngle + 2 * math.pi; // Full circle from original angle
    
    final spinEffect = RotateEffect.to(
      spinTargetAngle,
      EffectController(duration: spinDuration),
    );
    
    sourceTile.add(spinEffect);
    await spinEffect.completed.timeout(
      Duration(milliseconds: (spinDuration * 1000).round() + 100),
      onTimeout: () {
        // Timeout - component may have been removed
      },
    );
    
    // Check if component still exists
    if (sourceTile.isRemoved || !game.children.contains(sourceTile)) {
      return; // Abort quietly
    }
    
    // Step 2: Rotate sprite to face the target using RotateEffect.to
    // Calculate angle from source to target
    // atan2(dy, dx) returns angle where 0 = east (right), increases counter-clockwise
    // Flame's RotateEffect uses angles where 0 = north (up), increases clockwise
    // To point HEAD toward target: add pi/2 (instead of subtracting) to flip 180 degrees
    final dx = targetPosition.x - originalPosition.x;
    final dy = targetPosition.y - originalPosition.y;
    // Calculate direction angle (0 = east, increases counter-clockwise)
    final directionAngle = math.atan2(dy, dx);
    // Convert to Flame convention and flip to point head (not tail) toward target
    // Add pi/2 instead of subtracting to rotate 180 degrees
    // Normalize to [0, 2*pi) range
    var targetAngle = directionAngle + math.pi / 2;
    if (targetAngle < 0) {
      targetAngle += 2 * math.pi;
    } else if (targetAngle >= 2 * math.pi) {
      targetAngle -= 2 * math.pi;
    }
    
    final rotateDuration = 0.2; // 200ms to rotate
    final rotateEffect = RotateEffect.to(
      targetAngle,
      EffectController(duration: rotateDuration),
    );
    
    sourceTile.add(rotateEffect);
    await rotateEffect.completed.timeout(
      Duration(milliseconds: (rotateDuration * 1000).round() + 100),
      onTimeout: () {
        // Timeout - component may have been removed
      },
    );
    
    // Check if component still exists
    if (sourceTile.isRemoved || !game.children.contains(sourceTile)) {
      return; // Abort quietly
    }
    
    // Step 3: Fly to destination target
    final flyDuration = 0.4; // 400ms
    
    final flyEffect = MoveToEffect(
      targetPosition,
      EffectController(duration: flyDuration, curve: Curves.easeOut),
    );
    
    sourceTile.add(flyEffect);
    await flyEffect.completed.timeout(
      Duration(milliseconds: (flyDuration * 1000).round() + 100),
      onTimeout: () {
        // Timeout - component may have been removed
      },
    );
    
    // Note: Burst is spawned by the clear system (board_game.dart) when the tile is actually cleared
    // This avoids double-spawning bursts
  }
}
