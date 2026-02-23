import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../assets/tile_atlas.dart';
import '../stages/stage_data.dart';
import 'board_game.dart';

/// Sentinel values for move result (cleaner than exceptions)
enum _MoveResult {
  completed,
  removed,
}

/// Component that renders a single tile sprite instance
/// Represents a tile instance that can move and change type
class TileComponent extends SpriteComponent with HasGameReference<BoardGame> {
  final int instanceId; // Unique id per tile instance that persists as it moves
  int tileTypeId; // Which sprite/type to draw (can change)
  Coord coord; // Last committed logical coord (only updated when movement completes)
  final double tileSize;
  final Vector2 Function(Coord) coordToWorld;
  
  TileDef? _tileDef; // Cached tile definition
  TileAtlasFrame? _atlasFrame; // Cached atlas frame for regular tiles
  Coord? _targetCoord; // Where the tile is currently moving to (null if not moving)
  bool isSelected = false; // Whether this tile is currently selected (for highlighting)
  
  // Scale factor for sprite size (applies to all tiles including special tiles)
  static const double _spriteScale = 1.08; // 8% larger sprites (reduced from 1.15)
  
  // Highlight color when selected
  static const Color _highlightColor = ui.Color.fromARGB(255, 255, 254, 246); // Gold/yellow
  
  // Breathing animation for selection highlight
  double _breathPhase = 0.0; // Phase of the breathing animation (in radians)
  static const double _breathPeriod = 1.0; // Period of one breath cycle in seconds
  static const double _breathMinAlpha = 0.15; // Minimum highlight opacity
  static const double _breathMaxAlpha = 0.35; // Maximum highlight opacity
  double _cachedAlpha = 0.0; // Cached alpha value to avoid recalculating in render()

  // Reusable Paint object for selection highlighting (created once, updated per frame)
  late final Paint _highlightPaint;

  TileComponent({
    required this.instanceId,
    required this.tileTypeId,
    required this.coord,
    required this.tileSize,
    required this.coordToWorld,
  });

  /// Check if this tile is currently moving (animation in progress)
  bool get isMoving => _targetCoord != null;

  /// Get the tile definition for the current tileTypeId
  TileDef get tileDef {
    if (_tileDef == null || _tileDef!.id != tileTypeId) {
      _tileDef = game.tileDefById[tileTypeId];
      if (_tileDef == null) {
        throw StateError('TileDef not found for tileTypeId: $tileTypeId. '
            'Available tileTypeIds: ${game.tileDefById.keys.join(", ")}');
      }
    }
    return _tileDef!;
  }

  /// Move this tile to a new coordinate with animation
  /// Uses Flame MoveEffect for smooth animation
  /// Only commits coord when animation completes
  /// Supports retargeting: if already moving, cancels current animation and starts new one
  Future<void> moveToCoord(Coord newCoord, {double duration = 0.2, Curve curve = Curves.easeOut}) async {
    // If already at target and not moving, nothing to do
    if (coord == newCoord && _targetCoord == null) {
      return;
    }
    
    // If already moving to the same target, nothing to do
    if (_targetCoord == newCoord) {
      return;
    }
    
    // Collect existing Move effects to remove (safer than iterating and removing)
    final existingEffects = children.whereType<MoveEffect>().toList();
    
    // Remove old effects (if retargeting)
    // Note: We don't await their removal - we're canceling them anyway
    for (final effect in existingEffects) {
      effect.removeFromParent();
    }
    
    // Update target coord
    _targetCoord = newCoord;
    final targetPosition = coordToWorld(newCoord);
    
    // Create and add move effect
    final controller = EffectController(duration: duration, curve: curve);
    final effect = MoveToEffect(
      targetPosition,
      controller,
    )..onComplete = () {
      coord = newCoord;        // Commit coord only when animation completes
      _targetCoord = null;      // Mark as done moving
    };
    add(effect);
    
    // Wait for effect to complete OR be removed (if retargeted again)
    // Use Future.any to handle both cases - prevents deadlock if effect is removed
    // Use sentinel enum values instead of exceptions for cleaner stack traces
    final result = await Future.any([
      effect.completed.then((_) => _MoveResult.completed),
      effect.removed.then((_) => _MoveResult.removed),
    ]);
    
    // If removed (cancelled), that's expected when retargeting - just return
    // The new moveToCoord call will handle the new animation
    if (result == _MoveResult.removed) {
      return;
    }
    // Otherwise, effect completed normally - coord already updated in onComplete callback
  }

  /// Update the tile type (sprite) without destroying the component
  Future<void> setType(int newTileTypeId) async {
    if (tileTypeId == newTileTypeId) {
      return; // Already correct type
    }
    
    tileTypeId = newTileTypeId;
    _tileDef = null; // Clear cache to force reload
    
    // Reload sprite
    if (isLoaded) {
      await _loadSprite();
    }
  }

  /// Synchronously update tile type (for debug - immediate update)
  /// Updates tileTypeId and triggers sprite reload if component is loaded
  void updateTileType(int newTileTypeId) {
    if (tileTypeId == newTileTypeId) {
      return; // Already correct type
    }
    
    tileTypeId = newTileTypeId;
    _tileDef = null; // Clear cache to force reload
    
    // Reload sprite synchronously if component is loaded
    if (isLoaded) {
      _loadSprite().catchError((e) {
        DebugLogger.error('Failed to reload sprite for tileTypeId $newTileTypeId: $e', category: 'TileComponent');
      });
    }
  }

  Future<void> _loadSprite() async {
    final def = tileDef;

    final atlasFrame = game.atlasFrameForTileAsset(def.file);
    if (atlasFrame != null) {
      if (atlasFrame.rotated) {
        throw UnsupportedError(
          'Rotated atlas frame is not supported for ${def.file}',
        );
      }
      _atlasFrame = atlasFrame;
      // SpriteComponent asserts sprite != null in onMount.
      // Keep a real sprite assigned while custom atlas render handles trimming.
      sprite = Sprite(
        atlasFrame.image,
        srcPosition: Vector2(
          atlasFrame.frameRect.left,
          atlasFrame.frameRect.top,
        ),
        srcSize: Vector2(
          atlasFrame.frameRect.width,
          atlasFrame.frameRect.height,
        ),
      );
      return;
    }

    if (tileTypeId < 101) {
      throw StateError('Atlas frame not found for regular tile: ${def.file}');
    }

    _atlasFrame = null;
    String assetPath = def.file;
    if (assetPath.startsWith('assets/')) {
      assetPath = assetPath.substring(7); // Remove 'assets/' (7 chars)
    }
    try {
      final image = await game.images.load(assetPath);
      sprite = Sprite(image);
    } catch (e) {
      DebugLogger.error('Failed to load tile sprite: ${def.file} (processed: $assetPath)', category: 'TileComponent');
      DebugLogger.error('Error: $e', category: 'TileComponent');
      rethrow;
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Initialize reusable Paint object (avoids creating new Paint every frame)
    // Use default quality settings for better Windows performance
    _highlightPaint = Paint();
    
    // Load sprite
    await _loadSprite();
    
    // Set size to match tile size with scale factor applied
    // Scale factor increases sprite size slightly (applies to all tiles including special tiles)
    size = Vector2.all(tileSize * _spriteScale);
    
    // Position at the center of the grid cell
    position = coordToWorld(coord);
    anchor = Anchor.center;
    
    // Set priority so tiles render above beds
    priority = 10;
  }

  @override
  void update(double dt) {
    // Skip update entirely if tile is not selected and not moving
    // This saves ~45-47 function calls per frame (out of 49 tiles)
    if (!isSelected && !isMoving) {
      return;
    }
    
    super.update(dt);
    
    // Only update breathing animation when selected
    if (isSelected) {
      _breathPhase += (2 * math.pi) / _breathPeriod * dt; // 2π / period * dt
      // Keep phase in reasonable range (prevent overflow)
      if (_breathPhase > 2 * math.pi) {
        _breathPhase -= 2 * math.pi;
      }
      
      // Pre-calculate alpha value for render() - moved from render to update for performance
      final sinValue = math.sin(_breathPhase);
      final t = 0.5 + 0.5 * sinValue; // ranges from 0 to 1
      _cachedAlpha = _breathMinAlpha + (_breathMaxAlpha - _breathMinAlpha) * t;
    } else {
      // Reset phase when deselected
      _breathPhase = 0.0;
      _cachedAlpha = 0.0;
    }
  }

  void _renderCurrentTile(Canvas canvas) {
    final atlasFrame = _atlasFrame;
    if (atlasFrame != null) {
      _renderAtlasTile(canvas, atlasFrame);
      return;
    }
    super.render(canvas);
  }

  void _renderAtlasTile(Canvas canvas, TileAtlasFrame atlasFrame) {
    final sourceSize = atlasFrame.sourceSize;
    if (sourceSize.width <= 0 || sourceSize.height <= 0) {
      return;
    }

    final scaleX = size.x / sourceSize.width;
    final scaleY = size.y / sourceSize.height;
    final spriteSource = atlasFrame.spriteSourceRect;

    final destinationRect = ui.Rect.fromLTWH(
      spriteSource.left * scaleX,
      spriteSource.top * scaleY,
      spriteSource.width * scaleX,
      spriteSource.height * scaleY,
    );

    canvas.drawImageRect(
      atlasFrame.image,
      atlasFrame.frameRect,
      destinationRect,
      paint,
    );
  }

  @override
  void render(Canvas canvas) {
    final hasRenderable = sprite != null || _atlasFrame != null;
    if (isSelected && hasRenderable) {
      // Use pre-calculated alpha from update() - no expensive calculations here
      _highlightPaint.colorFilter = ui.ColorFilter.mode(
        _highlightColor.withValues(alpha: _cachedAlpha),
        BlendMode.srcATop,
      );
      
      // Save canvas, apply filter, render sprite, restore
      canvas.saveLayer(null, _highlightPaint);
      _renderCurrentTile(canvas);
      canvas.restore();
    } else {
      // Normal rendering when not selected - use default rendering (no paint overhead)
      _renderCurrentTile(canvas);
    }
  }
}
