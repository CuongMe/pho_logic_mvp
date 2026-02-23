import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

/// Helper function to spawn a match burst effect at a tile center
/// Creates two layers: crumbs (with gravity) and sparkles (slower, lighter)
/// Particles spawn from a ring around the tile, not from the center
/// 
/// [isSpecialClear] - If true, increases particle count and speed for more intense burst
void spawnMatchBurst({
  required FlameGame game,
  required Vector2 center,
  required double tileSize,
  required Sprite? crumbSprite,
  required Sprite? sparkleSprite,
  bool isSpecialClear = false,
}) {
  if (crumbSprite == null && sparkleSprite == null) {
    return; // No sprites available, skip burst
  }

  final rng = math.Random();

  // Layer A: Crumbs/Bits
  if (crumbSprite != null) {
    final crumbRadius = tileSize * 0.5 + 8;
    final crumbDuration = 0.8; // Shortened duration
    // Increase intensity for special clears
    final crumbMinSpeed = isSpecialClear ? 35.0 : 15.0;
    final crumbMaxSpeed = isSpecialClear ? 120.0 : 50.0;
    final crumbGravity = Vector2(0, 500);
    // Original particle counts
    final crumbCount = isSpecialClear ? 22 : 4;

    // Create crumb particles using Particle.generate
    final crumbParticle = Particle.generate(
      count: crumbCount,
      lifespan: crumbDuration,
      generator: (i) {
        // Random angle for ring position
        final angle = rng.nextDouble() * 2 * math.pi;
        
        // Spawn position on ring (relative to center)
        final spawnOffset = Vector2(
          math.cos(angle) * crumbRadius,
          math.sin(angle) * crumbRadius,
        );
        
        // Random speed for outward velocity
        final speed = crumbMinSpeed + (crumbMaxSpeed - crumbMinSpeed) * rng.nextDouble();
        
        // Velocity outward from ring position
        final velocity = Vector2(
          math.cos(angle) * speed,
          math.sin(angle) * speed,
        );
        
        // Random size 28..56 pixels (increased from 24..48)
        final size = 28.0 + 28.0 * rng.nextDouble();
        
        // Create sprite particle
        final spriteParticle = SpriteParticle(
          sprite: crumbSprite,
          size: Vector2.all(size),
        );
        
        // Apply scaling: scale down over time (appears to fade as it scales)
        final scaledParticle = ScalingParticle(
          lifespan: crumbDuration,
          to: 0.0, // Scale to 0 for fade effect
          curve: Curves.easeOut,
          child: spriteParticle,
        );
        
        // Apply movement with initial velocity and gravity
        final movedParticle = AcceleratedParticle(
          acceleration: crumbGravity,
          speed: velocity,
          child: scaledParticle,
        );
        
        // Offset from center (spawn on ring) - use TranslatedParticle for static offset
        return TranslatedParticle(
          offset: spawnOffset,
          child: movedParticle,
        );
      },
    );

    // Create crumb particle system component
    final crumbSystem = ParticleSystemComponent(
      particle: crumbParticle,
    )
      ..position = center.clone()
      ..priority = 20; // Render above tiles

    game.add(crumbSystem);

    // Auto-remove after duration + buffer
    crumbSystem.add(RemoveEffect(delay: crumbDuration + 0.2));
  }

  // Layer B: Sparkles
  if (sparkleSprite != null) {
    final sparkleRadius = tileSize * 0.5 + 12;
    final sparkleDuration = 1.0; // Shortened duration
    // Increase intensity for special clears
    final sparkleMinSpeed = isSpecialClear ? 18.0 : 8.0;
    final sparkleMaxSpeed = isSpecialClear ? 75.0 : 30.0;
    // Original particle counts
    final sparkleCount = isSpecialClear ? 11 : 2;

    // Create sparkle particles using Particle.generate
    final sparkleParticle = Particle.generate(
      count: sparkleCount,
      lifespan: sparkleDuration,
      generator: (i) {
        // Random angle for ring position
        final angle = rng.nextDouble() * 2 * math.pi;
        
        // Spawn position on ring (relative to center)
        final spawnOffset = Vector2(
          math.cos(angle) * sparkleRadius,
          math.sin(angle) * sparkleRadius,
        );
        
        // Random speed for outward velocity (slower than crumbs)
        final speed = sparkleMinSpeed + (sparkleMaxSpeed - sparkleMinSpeed) * rng.nextDouble();
        
        // Velocity outward from ring position
        final velocity = Vector2(
          math.cos(angle) * speed,
          math.sin(angle) * speed,
        );
        
        // Random size 28..56 pixels (increased from 24..48)
        final size = 28.0 + 28.0 * rng.nextDouble();
        
        // Create sprite particle
        final spriteParticle = SpriteParticle(
          sprite: sparkleSprite,
          size: Vector2.all(size),
        );
        
        // Apply scaling: scale down over time (appears to fade as it scales)
        final scaledParticle = ScalingParticle(
          lifespan: sparkleDuration,
          to: 0.0, // Scale to 0 for fade effect
          curve: Curves.easeOut,
          child: spriteParticle,
        );
        
        // Apply movement with slight or no gravity
        final movedParticle = AcceleratedParticle(
          acceleration: Vector2(0, 100), // Light gravity
          speed: velocity,
          child: scaledParticle,
        );
        
        // Offset from center (spawn on ring) - use TranslatedParticle for static offset
        return TranslatedParticle(
          offset: spawnOffset,
          child: movedParticle,
        );
      },
    );

    // Create sparkle particle system component (higher priority than crumbs)
    final sparkleSystem = ParticleSystemComponent(
      particle: sparkleParticle,
    )
      ..position = center.clone()
      ..priority = 21; // Render above crumbs

    game.add(sparkleSystem);

    // Auto-remove after duration + buffer
    sparkleSystem.add(RemoveEffect(delay: sparkleDuration + 0.2));
  }
}
