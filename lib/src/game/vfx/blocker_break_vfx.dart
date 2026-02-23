import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import 'package:pho_logic/src/audio/sfx_manager.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../board/board_game.dart';
import '../board/blocker_component.dart';

/// Visual effects for blocker break (scooter running away)
class BlockerBreakVfx {
  /// Play the blocker break VFX
  /// 
  /// Parameters:
  /// - game: The BoardGame instance
  /// - coord: The coord where the blocker is located
  /// - blocker: The BlockerComponent to animate
  /// 
  /// Animation sequence:
  /// 1. Scooter runs off screen (random left or right)
  /// 2. Particle pops up at original position (random particle 1 or 2)
  /// 3. Particle fades and falls with gravity
  static Future<void> play({
    required BoardGame game,
    required Coord coord,
    required BlockerComponent blocker,
  }) async {
    final rng = math.Random();
    
    // Random direction: true = run left, false = run right
    final runLeft = rng.nextBool();
    
    // Random particle: scooter_particle_1.png or scooter_particle_2.png
    final particleAsset = rng.nextBool() 
        ? 'sprites/particles/scooter_particle_1.png'
        : 'sprites/particles/scooter_particle_2.png';
    
    DebugLogger.vfx(
      'Blocker break at $coord: runLeft=$runLeft, particle=$particleAsset',
      vfxType: 'BlockerBreak'
    );
    
    // Calculate scooter's original position
    final scooterPosition = blocker.position.clone();
    
    // Step 1: Animate scooter running off screen
    final offScreenX = runLeft 
      ? -game.tileSize * 2  // Run off to the left
      : game.size.x + game.tileSize * 2;  // Run off to the right
    // Use constant speed (px/sec) for more natural running
    const runSpeed = 120.0; // pixels per second (slower)
    final distance = (offScreenX - blocker.position.x).abs();
    final scooterRunDuration = math.max(0.5, distance / runSpeed);
    
    // Flip scooter if running left
    if (runLeft) {
      blocker.flipHorizontally();
    }
    
    // Animate scooter moving off screen
    final moveEffect = MoveToEffect(
      Vector2(offScreenX, blocker.position.y),
      EffectController(duration: scooterRunDuration, curve: Curves.easeOut),
      onComplete: () {
        // Remove scooter component after it runs off screen (if still mounted)
        if (blocker.isMounted) {
          blocker.removeFromParent();
        }
        DebugLogger.vfx('Scooter ran off screen at $coord', vfxType: 'BlockerBreak');
      },
    );
    
    blocker.add(moveEffect);
    
    // Add rotation shake effect while running to show movement (doesn't conflict with MoveToEffect)
    _addRotationShakeEffect(blocker, scooterRunDuration);
    
    // Play scooter SFX just before the animation starts (100ms earlier)
    await Future.delayed(const Duration(milliseconds: 100));
    SfxManager.instance.playConfigured(SfxType.scooter);
    
    // Step 2: Spawn particle at original scooter position (run in parallel)
    // Fire-and-forget so scooter and particle start at the same time
    // ignore: unawaited_futures
    _spawnParticle(
      game: game,
      position: scooterPosition,
      assetPath: particleAsset,
      coord: coord,
      runLeft: runLeft,
    );
    
    // Wait for scooter to finish running off screen
    await Future.delayed(Duration(milliseconds: (scooterRunDuration * 1000).round()));
  }
  
  /// Spawn the message particle that pops up and fades away
  static Future<void> _spawnParticle({
    required BoardGame game,
    required Vector2 position,
    required String assetPath,
    required Coord coord,
    required bool runLeft,
  }) async {
    // Load particle sprite from cache (preloaded in BoardGame._loadParticleSprites)
    Sprite? particleSprite;
    try {
      final image = game.images.fromCache(assetPath);
      particleSprite = Sprite(image);
    } catch (e) {
      DebugLogger.error('Failed to get particle sprite from cache: $e', category: 'BlockerBreakVfx');
      return;
    }
    
    // Create particle component
    final particleSize = game.tileSize * 3.0; // Much larger for readability
    final particle = SpriteComponent(
      sprite: particleSprite,
      size: Vector2.all(particleSize),
      anchor: Anchor.center,
      position: position,
      priority: 100, // Above everything
    );
    
    game.add(particle);
    
    // Animation sequence:
    // 1. Pop up: scale 0.5 -> 1.2 while launching upward (350ms) - readable pop, slightly smaller
    // 2. Bounce arc: move up then down (600ms)
    // 3. Fall + fade: move down and fade out (variable speed)
    
    // Initial scale for pop effect
    particle.scale = Vector2.all(0.5);
    
    // Step 1: Pop up animation (scale + move for clear, readable pop)
    const popDuration = 0.35; // Longer duration for readability
    const popHeight = 2.5; // tiles worth of height
    
    // Scale: 0.5 -> 1.1 (explosive growth, slightly smaller)
    final popScaleEffect = ScaleEffect.to(
      Vector2.all(1.1),
      EffectController(duration: popDuration, curve: Curves.easeOut),
    );
    
    // Move up while popping
    final popMoveEffect = MoveByEffect(
      Vector2(0, -game.tileSize * popHeight * 0.8),
      EffectController(duration: popDuration, curve: Curves.easeOut),
    );
    
    particle.add(popScaleEffect);
    particle.add(popMoveEffect);
    
    // Wait for pop to complete
    await Future.delayed(Duration(milliseconds: (popDuration * 1000).round()));
    
    // Step 2: Bounce and rotate - particle arcs through air opposite to scooter direction
    const bounceDuration = 0.6;
    const bounceHeight = 3.0; // tiles worth of arc height
    const bounceDistance = 2.0; // tiles worth of horizontal distance
    
    // Bounce opposite to scooter direction (if scooter runs left, particle bounces right)
    final bounceX = runLeft ? game.tileSize * bounceDistance : -game.tileSize * bounceDistance;
    
    // Create arc path: up first, then down with gravity
    final arcUpEffect = MoveByEffect(
      Vector2(bounceX * 0.7, -game.tileSize * bounceHeight * 0.5),
      EffectController(duration: bounceDuration * 0.4, curve: Curves.easeOut),
    );
    
    final arcDownEffect = MoveByEffect(
      Vector2(bounceX * 0.3, game.tileSize * bounceHeight * 0.5),
      EffectController(duration: bounceDuration * 0.6, curve: Curves.easeIn),
    );
    
    particle.add(SequenceEffect([arcUpEffect, arcDownEffect]));
    
    // Wait for bounce to complete
    await Future.delayed(Duration(milliseconds: (bounceDuration * 1000).round()));
    
    // Step 3: Fall off screen with fade (random speed for variation)
    const fallDistance = 4.0; // tiles worth of fall
    // Randomize fall speed: 0.3-0.5 seconds for variety
    final rng = math.Random();
    final fallDuration = 0.3 + (rng.nextDouble() * 0.2);
    
    final fadeEffect = OpacityEffect.to(
      0.0,
      EffectController(duration: fallDuration, curve: Curves.easeIn),
    );
    
    final fallEffect = MoveByEffect(
      Vector2(0, game.tileSize * fallDistance),
      EffectController(duration: fallDuration, curve: Curves.easeIn),
      onComplete: () {
        particle.removeFromParent();
        DebugLogger.vfx('Particle removed at $coord', vfxType: 'BlockerBreak');
      },
    );
    
    particle.add(fadeEffect);
    particle.add(fallEffect);
    
    // Total VFX time: pop (150ms) + bounce (600ms) + fall (400ms) = 1155ms
    await Future.delayed(Duration(milliseconds: (fallDuration * 1000).round()));
  }
  
  /// Add rotation shake effect while running (doesn't conflict with MoveToEffect)
  /// Uses subtle rotation wobble to simulate running motion without affecting position
  static void _addRotationShakeEffect(BlockerComponent blocker, double duration) {
    const rotationAmount = 0.15; // radians (~8.5 degrees)
    const shakeFrequency = 0.08; // seconds per shake cycle
    
    // Calculate number of shake cycles
    final numShakes = (duration / shakeFrequency).toInt();
    
    final shakeEffects = <Effect>[];
    for (int i = 0; i < numShakes; i++) {
      // Rotate left/right alternately
      final rotation = (i % 2 == 0) ? rotationAmount : -rotationAmount;
      shakeEffects.add(
        RotateEffect.by(
          rotation,
          EffectController(duration: shakeFrequency / 2, curve: Curves.easeOut),
        ),
      );
    }
    
    if (shakeEffects.isNotEmpty) {
      blocker.add(SequenceEffect(shakeEffects));
    }
  }
}
