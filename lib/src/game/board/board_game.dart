import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../model/coord.dart';
import '../model/grid_model.dart';
import '../stages/stage_data.dart';
import '../assets/tile_atlas.dart';
import '../utils/debug_logger.dart';
import '../vfx/special_vfx_dispatcher.dart';
import '../vfx/blocker_break_vfx.dart';
import '../game_state_model.dart';
import 'tile_component.dart';
import 'bed_component.dart';
import 'blocker_component.dart';
import 'board_controller.dart';
import 'match_burst_particle.dart' show spawnMatchBurst;
import '../../audio/sfx_manager.dart';
import '../../audio/bgm_manager.dart';

/// Flame game that manages the board rendering
/// Renders tiles and beds in a grid layout
class BoardGame extends FlameGame with TapCallbacks {
  final int rows;
  final int cols;
  final GridModel gridModel;
  final StageData stageData;

  // Computed grid layout values
  late final double tileSize;
  late final double gridLeft;
  late final double gridTop;

  // Prebuilt lookup maps for performance
  late final Map<int, BedType> bedTypeById;
  late final Map<int, TileDef> tileDefById;

  // Registry for tile components - keyed by instanceId for stable identity
  final Map<int, TileComponent> tilesByInstanceId = {};
  // Map from coord to instanceId for selection/hit testing/swap lookup
  final Map<Coord, int> instanceAtCoord = {};
  // Reverse map: instanceId -> coord for O(1) lookup and cleanup
  final Map<int, Coord> coordByInstanceId = {};
  // Beds are static, so keep them keyed by Coord
  final Map<Coord, BedComponent> bedComponents = {};
  // Blockers are also keyed by Coord (they don't move)
  final Map<Coord, BlockerComponent> blockerComponents = {};

  // Game controller for match-3 rules
  late final BoardController controller;

  // Preloaded particle sprites
  final Map<int, Sprite> crumbParticleByTileId = {};
  Sprite? sparkleSprite;
  TileAtlasData? _tileAtlasData;

  /// Getter for sparkle sprite (for VFX)
  Sprite? get sparkleSpriteForVfx => sparkleSprite;

  // Track dragonfly target coords that should skip early bursts (VFX will handle them)
  final Set<Coord> _dragonflyTargetCoords = {};

  // Track coords that should use enhanced burst (isSpecialClear: true)
  final Set<Coord> _specialClearCoords = {};

  // Coords for which VFX will spawn bursts manually (avoid double bursts from callback).
  final Set<Coord> _suppressAutoBurstCoords = {};

  /// Mark a coord as a dragonfly target (to skip early burst)
  void markDragonflyTarget(Coord coord) {
    _dragonflyTargetCoords.add(coord);
  }

  /// Unmark a coord as a dragonfly target
  void unmarkDragonflyTarget(Coord coord) {
    _dragonflyTargetCoords.remove(coord);
  }

  /// Mark a coord for special clear burst (enhanced burst)
  void markSpecialClear(Coord coord) {
    _specialClearCoords.add(coord);
  }

  /// Unmark a coord for special clear burst
  void unmarkSpecialClear(Coord coord) {
    _specialClearCoords.remove(coord);
  }

  /// Suppress automatic burst spawning for these coords (VFX will handle timing).
  void suppressAutoBurstForCoords(Iterable<Coord> coords) {
    _suppressAutoBurstCoords.addAll(coords);
  }

  /// Clear tiles at specific coords (for VFX to trigger clearing at exact visual timing).
  /// This forwards to the controller's clearing mechanism to ensure objectives count correctly.
  Future<void> clearTilesAtCoords(Set<Coord> coords) async {
    if (coords.isEmpty) return;
    // Forward to controller's clearing mechanism
    // This ensures all clears go through _emitCellsCleared() for objectives
    await controller.clearTilesForVfx(coords);
    // Sync to update visual display
    await syncFromModel();
  }

  // Input handling: selected tile for swap
  Coord? _selectedCoord;
  TileComponent?
      _selectedTileComponent; // Currently selected tile component (for highlighting)
  // Drag-hover highlight (from belt drag-and-drop)
  TileComponent? _hoverTileComponent;

  // Game state model for tracking moves and objectives (optional)
  GameStateModel? _gameStateModel;

  // Callback for when no possible moves are detected (to show modal)
  Future<void> Function()? onNoMovesDetected;

  // Lock to prevent overlapping swaps/cascades (race condition prevention)
  bool _isBusy = false;

  /// Set game state model for tracking moves and objectives
  void setGameStateModel(GameStateModel gameStateModel) {
    _gameStateModel = gameStateModel;
  }

  BoardGame({
    required this.rows,
    required this.cols,
    required this.gridModel,
    required this.stageData,
    required double viewportWidth,
    required double viewportHeight,
  }) : super(
          // Set viewport size to match the widget size
          camera: CameraComponent.withFixedResolution(
            width: viewportWidth,
            height: viewportHeight,
          ),
        ) {
    // Compute grid layout from viewport size
    tileSize = (viewportWidth / cols < viewportHeight / rows)
        ? viewportWidth / cols
        : viewportHeight / rows;

    final gridWidth = tileSize * cols;
    final gridHeight = tileSize * rows;

    // Center the grid within the viewport
    gridLeft = (viewportWidth - gridWidth) / 2;
    gridTop = (viewportHeight - gridHeight) / 2;

    // Prebuild lookup maps for performance
    assert(stageData.bedTypes.isNotEmpty,
        'StageData must have at least one bed type');
    assert(stageData.tiles.isNotEmpty,
        'StageData must have at least one tile type');

    bedTypeById = {
      for (final bedType in stageData.bedTypes) bedType.id: bedType,
    };
    tileDefById = {
      for (final tileDef in stageData.tiles) tileDef.id: tileDef,
    };

    // Add special tile definitions (power-ups)
    // These are not in stage JSON, so we define them here
    tileDefById[101] = TileDef(
      id: 101,
      file: 'assets/sprites/power-ups/party_popper_horizontal.png',
      weight:
          0, // Not used for spawning (special tiles only spawn from matches)
    );
    tileDefById[102] = TileDef(
      id: 102,
      file: 'assets/sprites/power-ups/party_popper_vertical.png',
      weight:
          0, // Not used for spawning (special tiles only spawn from matches)
    );
    tileDefById[103] = TileDef(
      id: 103,
      file: 'assets/sprites/power-ups/sticky_rice_bomb.png',
      weight:
          0, // Not used for spawning (special tiles only spawn from matches)
    );
    tileDefById[104] = TileDef(
      id: 104,
      file: 'assets/sprites/power-ups/firecracker.png',
      weight:
          0, // Not used for spawning (special tiles only spawn from matches)
    );
    tileDefById[105] = TileDef(
      id: 105,
      file: 'assets/sprites/power-ups/dragon_fly.png',
      weight:
          0, // Not used for spawning (special tiles only spawn from matches)
    );

    // Initialize game controller (inject SfxManager instance)
    controller = BoardController(
      gridModel: gridModel,
      stageData: stageData,
      sfxManager: SfxManager.instance,
    );

    // Assign instanceIds to all existing tiles (if not already assigned)
    controller.initializeInstanceIds();

    // Stabilize initial board: reroll matched cells until zero matches
    controller.stabilizeInitialBoard();

    // Set generic clear callback for particles AND objectives (fires for ALL clears)
    // This callback does BOTH: spawn particles and update objective progress
    controller.setOnCellsClearedWithTypes((victims) async {
      DebugLogger.log(
          'BoardGame callback: received ${victims.length} victim tiles',
          category: 'BoardGame');
      DebugLogger.log(
          'BoardGame callback: victim types: ${victims.values.toSet()}',
          category: 'BoardGame');

      // 1) Spawn particles (only when we have victim tiles).
      // Some VFX (e.g. Party Popper projectiles) spawn bursts manually for timing,
      // so we suppress auto-bursts for those coords to avoid double bursts.
      if (victims.isNotEmpty) {
        // Filter out coords that are suppressed (VFX will spawn bursts)
        final coordsToSpawnParticles = <Coord, int>{};
        for (final entry in victims.entries) {
          if (!_suppressAutoBurstCoords.contains(entry.key)) {
            coordsToSpawnParticles[entry.key] = entry.value;
          }
        }

        if (coordsToSpawnParticles.isNotEmpty) {
          spawnClearParticles(coordsToSpawnParticles);
        }

        // Clear suppression markers for any coords that were just cleared
        _suppressAutoBurstCoords.removeAll(victims.keys);
      }

      // 2) Always forward clears to game state (even empty)
      _gameStateModel?.processClearedTiles(victims);
    });

    // Set blocker break callback for VFX
    controller.setOnBlockerBreak((coord) async {
      final blocker = blockerComponents[coord];
      if (blocker != null) {
        DebugLogger.log('Playing blocker break VFX at $coord', category: 'BoardGame');
        await BlockerBreakVfx.play(game: this, coord: coord, blocker: blocker);
      }
    });

    // Track blocker clears for win condition
    controller.setOnBlockerCleared((coord) {
      _gameStateModel?.decrementBlockersRemaining();
    });
  }

  /// Get the tile component at a specific coordinate
  /// Returns null if no tile exists at that coord
  TileComponent? tileAt(Coord coord) {
    final instanceId = instanceAtCoord[coord];
    if (instanceId == null) return null;
    return tilesByInstanceId[instanceId];
  }

  /// Get the tile component at a specific coordinate (alias for tileAt)
  /// Used by VFX system
  TileComponent? getTileAt(Coord coord) => tileAt(coord);

  /// Get the tile component by instanceId (stable during animations)
  /// Used by VFX system when coord might be unstable
  TileComponent? getTileByInstanceId(int instanceId) =>
      tilesByInstanceId[instanceId];

  /// Check if a cell is playable (not void)
  /// A cell is playable if bedId != -1 (or exists == true)
  bool isPlayableCell(Coord coord) {
    if (coord.row < 0 ||
        coord.row >= rows ||
        coord.col < 0 ||
        coord.col >= cols) {
      return false;
    }
    final cell = gridModel.cells[coord.row][coord.col];
    // Playable if bedId is not -1 (void bed)
    return cell.bedId != null && cell.bedId! != -1;
  }

  /// Spawn burst particles for cleared cells (generic - works for matches, specials, combos)
  /// Takes a map of coord -> tileTypeId (captured BEFORE clearing)
  /// For big clears (many cells), only spawn crumbs to reduce overload
  void spawnClearParticles(Map<Coord, int> clearedCellsWithTypes) {
    final isBigClear =
        clearedCellsWithTypes.length > 8; // Threshold for "big clear"

    for (final entry in clearedCellsWithTypes.entries) {
      final coord = entry.key;
      final tileTypeId = entry.value;

      // Skip burst for dragonfly target tiles that are still marked (VFX will handle them after animation)
      // But if it's marked for special clear, spawn enhanced burst
      if (_dragonflyTargetCoords.contains(coord) &&
          !_specialClearCoords.contains(coord)) {
        continue;
      }

      // Only spawn particles for regular tiles (special tiles may have different VFX)
      if (tileTypeId < 101) {
        final worldPos = coordToWorld(coord);
        final crumbSprite = crumbParticleByTileId[tileTypeId];

        // All regular tiles use enhanced burst for more intense particles
        final isSpecialClear = true;

        spawnMatchBurst(
          game: this,
          center: worldPos,
          tileSize: tileSize,
          crumbSprite: crumbSprite,
          sparkleSprite:
              isBigClear ? null : sparkleSprite, // Skip sparkles for big clears
          isSpecialClear: isSpecialClear,
        );

        // Unmark after spawning (cleanup) - still track for other logic if needed
        if (_specialClearCoords.contains(coord)) {
          unmarkSpecialClear(coord);
        }
      }
    }
  }

  /// Load particle sprites for match burst effects
  Future<void> _loadParticleSprites() async {
    // Load crumb particles for each tile type
    final crumbAssetPaths = {
      1: 'sprites/particles/bread_crumbs_particle.png',
      2: 'sprites/particles/fried_crumb_particle.png',
      3: 'sprites/particles/glass_particle.png',
      4: 'sprites/particles/shrimp_leaf_particle.png',
      5: 'sprites/particles/soup_splash_particle.png',
      6: 'sprites/particles/rau_muong_particle.png',
    };

    for (final entry in crumbAssetPaths.entries) {
      try {
        final image = await images.load(entry.value);
        crumbParticleByTileId[entry.key] = Sprite(image);
      } catch (e) {
        DebugLogger.error(
            'Failed to load crumb particle sprite: ${entry.value} - $e',
            category: 'BoardGame');
        // Continue loading other sprites even if one fails
      }
    }

    // Load sparkle sprite
    try {
      final sparkleImage =
          await images.load('sprites/particles/sparkle_particle.png');
      sparkleSprite = Sprite(sparkleImage);
    } catch (e) {
      DebugLogger.error(
          'Failed to load sparkle sprite: sprites/particles/sparkle_particle.png - $e',
          category: 'BoardGame');
    }

    // Load scooter blocker particles
    try {
      await images.load('sprites/particles/scooter_particle_1.png');
      await images.load('sprites/particles/scooter_particle_2.png');
    } catch (e) {
      DebugLogger.error(
          'Failed to load scooter particles: $e',
          category: 'BoardGame');
    }
  }

  TileAtlasFrame? atlasFrameForTileAsset(String tileAssetPath) {
    final atlasData = _tileAtlasData;
    if (atlasData == null) {
      return null;
    }
    return TileAtlasLoader.frameForAssetPath(atlasData, tileAssetPath);
  }

  Future<void> _loadTileAtlas() async {
    _tileAtlasData = await TileAtlasLoader.load();
    final frameCount = _tileAtlasData?.frames.length ?? 0;
    if (frameCount == 0) {
      throw StateError('Tile atlas loaded with zero frames');
    }
    DebugLogger.boardGame('Loaded tile atlas: $frameCount frame(s)');
  }

  /// Convert grid coordinates (row, col) to world coordinates (x, y)
  Vector2 coordToWorld(Coord coord) {
    final x = gridLeft + coord.col * tileSize + tileSize / 2;
    final y = gridTop + coord.row * tileSize + tileSize / 2;
    return Vector2(x, y);
  }

  /// Convert world coordinates (x, y) to grid coordinates (row, col)
  /// Returns null if out of bounds or if the cell is void (not playable)
  Coord? worldToCoord(Vector2 worldPos) {
    final col = ((worldPos.x - gridLeft) / tileSize).floor();
    final row = ((worldPos.y - gridTop) / tileSize).floor();

    if (row >= 0 && row < rows && col >= 0 && col < cols) {
      final coord = Coord(row, col);
      // Check if cell is playable (not void)
      if (isPlayableCell(coord)) {
        return coord;
      }
    }
    return null;
  }

  @override
  Color backgroundColor() => const Color(0x00000000); // Fully transparent
  // This allows the wooden board frame (from Flutter UI) to show through
  // Areas not covered by tiles/beds will show the board background

  /// Handle tap input: select tile, then swap if adjacent tile is tapped
  @override
  void onTapDown(TapDownEvent event) {
    // Prevent overlapping swaps/cascades (race condition prevention)
    if (_isBusy) {
      DebugLogger.boardGame('Ignoring tap - game is busy');
      return;
    }

    // Use canvasPosition which is relative to the game widget (canvas)
    // This should match our world coordinate system
    final worldPos = event.canvasPosition;
    DebugLogger.boardGame(
        'Tap at canvasPosition: $worldPos (gridLeft: $gridLeft, gridTop: $gridTop, tileSize: $tileSize)');

    final coord = worldToCoord(worldPos);

    if (coord == null) {
      // Tapped outside board - deselect
      DebugLogger.boardGame('Tap outside board at $worldPos');
      _deselectTile();
      return;
    }

    DebugLogger.boardGame('Converted to coord: $coord');

    // Check if there's a tile at this coord
    final tile = tileAt(coord);
    if (tile == null) {
      // No tile - deselect
      DebugLogger.boardGame('No tile at coord $coord');
      _deselectTile();
      return;
    }

    if (_selectedCoord == null) {
      // First tap - select this tile
      _selectTile(coord, tile);
      DebugLogger.boardGame(
          'Selected tile at $coord (tileTypeId: ${tile.tileTypeId}, instanceId: ${tile.instanceId})');
      return;
    }

    // Second tap - check if adjacent and attempt swap
    if (_selectedCoord == coord) {
      // Same tile - deselect
      DebugLogger.boardGame('Same tile tapped - deselecting');
      _deselectTile();
      return;
    }

    // Check if adjacent
    if (!_selectedCoord!.isAdjacent(coord)) {
      // Not adjacent - select new tile instead
      DebugLogger.boardGame(
          'Not adjacent: $_selectedCoord vs $coord - selecting new tile');
      _selectTile(coord, tile);
      return;
    }

    // Adjacent tiles - attempt swap
    final selectedCoord = _selectedCoord!;
    DebugLogger.boardGame('Attempting swap: $selectedCoord <-> $coord');
    _deselectTile();

    // Process swap asynchronously
    _processSwap(selectedCoord, coord);
  }

  /// Select a tile and highlight it
  void _selectTile(Coord coord, TileComponent tile) {
    _deselectTile(); // Deselect any previously selected tile first
    _selectedCoord = coord;
    _selectedTileComponent = tile;
    tile.isSelected = true;
  }

  /// Deselect the currently selected tile
  void _deselectTile() {
    if (_selectedTileComponent != null) {
      _selectedTileComponent!.isSelected = false;
      _selectedTileComponent = null;
    }
    _selectedCoord = null;
  }

  /// Highlight a tile while dragging a belt power over the board.
  /// Uses the same visual as tap-selection, but does NOT affect swap selection state.
  void setDragHoverCoord(Coord? coord) {
    // Clear previous hover highlight (but never clear the actual selected tile)
    if (_hoverTileComponent != null &&
        _hoverTileComponent != _selectedTileComponent) {
      _hoverTileComponent!.isSelected = false;
    }
    _hoverTileComponent = null;

    if (coord == null) return;

    final tile = tileAt(coord);
    if (tile == null) return;

    // Don't interfere with an active swap selection highlight
    if (tile == _selectedTileComponent) return;

    _hoverTileComponent = tile;
    _hoverTileComponent!.isSelected = true;
  }

  /// Process swap attempt asynchronously
  Future<void> _processSwap(Coord a, Coord b) async {
    // Set busy flag to prevent overlapping swaps
    if (_isBusy) return;
    _isBusy = true;

    try {
      // Attempt swap through controller
      // Controller will call onSync callback after each stage for animations
      // Particles are spawned via setOnCellsClearedWithTypes callback (handles all clears)
      // chosenCoord is the tile the user started dragging from (first tap = a)
      final chosenCoord = a; // This is the dragStartCoord (the selected tile)
      final success = await controller.attemptSwap(
        a,
        b,
        chosenCoord: chosenCoord,
        onSync: () async {
          await syncFromModel();
          // Validate board sync after sync to ensure all tiles are properly registered
          await validateBoardSync();
        },
        onNoMovesDetected: onNoMovesDetected,
        onSpecialActivated: (activatedSpecials, vfxMetadata) async {
          // IMPORTANT: Dispatch immediately per invocation - do NOT accumulate or queue
          // Each combo step calls this separately and must trigger VFX immediately
          // Convert from coord-based to instanceId-based for VFX (instanceId is stable during animations)
          // Read instanceId from GridModel first (source of truth), then get tile component
          final instanceIdSpecials = <int, int>{};
          final instanceIdMetadata = <int, SpecialVfxMetadata>{};

          // Debug: Log received activated specials
          DebugLogger.boardGame(
              'onSpecialActivated callback received ${activatedSpecials.length} activated special(s)');

          for (final entry in activatedSpecials.entries) {
            final coord = entry.key;
            final typeId = entry.value;

            DebugLogger.boardGame(
                'Activated special: coord=$coord, typeId=$typeId');

            // Read instanceId from GridModel (source of truth)
            if (coord.row < 0 ||
                coord.row >= gridModel.rows ||
                coord.col < 0 ||
                coord.col >= gridModel.cols) {
              DebugLogger.error('coord $coord is out of bounds! Skipping VFX.',
                  category: 'BoardGame');
              continue;
            }

            final cell = gridModel.cells[coord.row][coord.col];
            final instanceId = cell.tileInstanceId;

            if (instanceId == null) {
              DebugLogger.error(
                  'cell at $coord has no tileInstanceId! Skipping VFX.',
                  category: 'BoardGame');
              continue;
            }

            // Verify tile component exists by instanceId
            final tile = getTileByInstanceId(instanceId);
            if (tile == null) {
              DebugLogger.error(
                  'getTileByInstanceId($instanceId) returned null for coord $coord! Skipping VFX.',
                  category: 'BoardGame');
              continue;
            }

            instanceIdSpecials[instanceId] = typeId;
            DebugLogger.boardGame(
                'Converted coord=$coord to instanceId=$instanceId (from GridModel)');

            // Convert metadata
            final metaEntry = vfxMetadata[coord];
            if (metaEntry != null) {
              instanceIdMetadata[instanceId] = SpecialVfxMetadata(
                targetCoord: metaEntry.targetCoord,
                activationCells: metaEntry.activationCells,
              );
            }
          }

          // Play VFX immediately - do NOT accumulate or queue
          // Each invocation is independent (especially for combo steps)
          if (instanceIdSpecials.isNotEmpty) {
            await SpecialVfxDispatcher.playSpecialVfx(
              game: this,
              activatedSpecials: instanceIdSpecials,
              metadata: instanceIdMetadata,
            );
          }
        },
      );

      if (success) {
        DebugLogger.boardGame('Swap successful: $a <-> $b');
        // Decrement moves when swap succeeds
        _gameStateModel?.decrementMoves();
      } else {
        DebugLogger.boardGame('Swap failed: $a <-> $b');
      }
    } finally {
      // Always release the lock, even if an error occurs
      _isBusy = false;
    }
  }

  /// Spawn or update a tile at a specific coordinate
  /// ALWAYS ensures: instanceId assigned, TileComponent exists and is registered, position/size correct, flags reset
  /// This is the single unified path for all tile spawning/updating
  /// Note: Does NOT update instanceAtCoord/coordByInstanceId maps - caller should handle map updates
  /// (This prevents conflicts when called from syncFromModel which manages maps atomically)
  Future<void> spawnOrUpdateTileAt(Coord coord, int tileTypeId,
      {int? instanceId, bool updateMaps = false}) async {
    if (!isPlayableCell(coord)) {
      DebugLogger.warn('Attempted to spawn tile at non-playable coord $coord',
          category: 'BoardGame');
      return;
    }

    final cell = gridModel.cells[coord.row][coord.col];

    // Ensure instanceId is assigned
    final finalInstanceId =
        instanceId ?? cell.tileInstanceId ?? controller.getNextInstanceId();
    if (cell.tileInstanceId != finalInstanceId) {
      cell.tileInstanceId = finalInstanceId;
    }

    // Update tileTypeId
    cell.tileTypeId = tileTypeId;

    // Get or create TileComponent
    TileComponent? component = tilesByInstanceId[finalInstanceId];

    if (component == null) {
      // Create new component
      component = TileComponent(
        instanceId: finalInstanceId,
        tileTypeId: tileTypeId,
        coord: coord,
        tileSize: tileSize,
        coordToWorld: coordToWorld,
      );
      add(component);
      tilesByInstanceId[finalInstanceId] = component;
      DebugLogger.boardGame(
          'Spawned tile at $coord (instanceId: $finalInstanceId, tileTypeId: $tileTypeId)');
    } else {
      // Update existing component
      if (component.tileTypeId != tileTypeId) {
        await component.setType(tileTypeId);
      }
      if (component.coord != coord) {
        // Update coord and position immediately (no animation for spawns)
        component.coord = coord;
        component.position = coordToWorld(coord);
        // Cancel any ongoing movement
        if (component.isMoving) {
          component
              .moveToCoord(coord, duration: 0.0)
              .catchError((_) {}); // Instant move to reset
        }
      } else {
        // Ensure position is correct
        component.position = coordToWorld(coord);
      }
    }

    // Update maps only if requested (for direct calls outside syncFromModel)
    if (updateMaps) {
      instanceAtCoord[coord] = finalInstanceId;
      coordByInstanceId[finalInstanceId] = coord;
    }

    // Restore opacity to 1.0
    component.opacity = 1.0;

    // Reset flags to ensure tile is selectable/active
    component.isSelected = false; // Not selected
    // Note: TileComponent doesn't have explicit canInteract/locked flags,
    // but ensuring it's not moving and position is correct makes it active
  }

  /// Validate board synchronization: check that all tiles are properly synced
  /// Fixes any mismatches between GridModel and TileComponents
  /// Returns count of fixes applied
  Future<int> validateBoardSync() async {
    int fixCount = 0;

    // Check 1: Every grid cell with instanceId must have a TileComponent
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final coord = Coord(row, col);
        if (!isPlayableCell(coord)) continue;

        final cell = gridModel.cells[row][col];
        if (cell.tileInstanceId != null && cell.tileTypeId != null) {
          final component = tilesByInstanceId[cell.tileInstanceId];
          if (component == null) {
            DebugLogger.warn(
                'Missing TileComponent for instanceId ${cell.tileInstanceId} at $coord',
                category: 'BoardGame');
            // Fix: spawn the tile
            await spawnOrUpdateTileAt(coord, cell.tileTypeId!,
                instanceId: cell.tileInstanceId, updateMaps: true);
            fixCount++;
          } else {
            // Check 2: TileComponent coord must match where instanceId lives in GridModel
            if (component.coord != coord) {
              DebugLogger.warn(
                  'TileComponent coord mismatch: component.coord=${component.coord}, GridModel=$coord (instanceId: ${cell.tileInstanceId})',
                  category: 'BoardGame');
              // Fix: rebind coord/position from GridModel
              // Use moveToCoord with same coord to reset movement state
              component.coord = coord;
              component.position = coordToWorld(coord);
              // Cancel any ongoing movement by calling moveToCoord with same coord
              if (component.isMoving) {
                component
                    .moveToCoord(coord, duration: 0.0)
                    .catchError((_) {}); // Instant move to reset
              }
              instanceAtCoord[coord] = cell.tileInstanceId!;
              coordByInstanceId[cell.tileInstanceId!] = coord;
              fixCount++;
            }

            // Check 3: TileComponent tileTypeId must match GridModel
            if (component.tileTypeId != cell.tileTypeId) {
              DebugLogger.warn(
                  'TileComponent tileTypeId mismatch: component=${component.tileTypeId}, GridModel=${cell.tileTypeId} (instanceId: ${cell.tileInstanceId})',
                  category: 'BoardGame');
              // Fix: update type (async, but we'll trigger it)
              component.setType(cell.tileTypeId!).catchError((e) {
                DebugLogger.error('Error updating tile type: $e',
                    category: 'BoardGame');
              });
              fixCount++;
            }
          }
        }
      }
    }

    // Check 4: Every TileComponent must have a corresponding cell in GridModel
    final orphanedComponents = <int>[];
    for (final entry in tilesByInstanceId.entries) {
      final instanceId = entry.key;
      final expectedCoord = coordByInstanceId[instanceId];

      if (expectedCoord == null) {
        DebugLogger.warn(
            'TileComponent has no coord mapping (instanceId: $instanceId)',
            category: 'BoardGame');
        orphanedComponents.add(instanceId);
        continue;
      }

      final cell = gridModel.cells[expectedCoord.row][expectedCoord.col];
      if (cell.tileInstanceId != instanceId) {
        DebugLogger.warn(
            'TileComponent instanceId not found at expected coord $expectedCoord (instanceId: $instanceId)',
            category: 'BoardGame');
        orphanedComponents.add(instanceId);
      }
    }

    // Remove orphaned components
    for (final instanceId in orphanedComponents) {
      tilesByInstanceId[instanceId]?.removeFromParent();
      tilesByInstanceId.remove(instanceId);
      coordByInstanceId.remove(instanceId);
      // Remove from instanceAtCoord
      instanceAtCoord.removeWhere((coord, id) => id == instanceId);
      fixCount++;
    }

    if (fixCount > 0) {
      DebugLogger.boardGame('validateBoardSync fixed $fixCount issue(s)');
    }

    return fixCount;
  }

  /// Synchronize tile components with the grid model
  /// Identity-based: tiles are tracked by instanceId, allowing smooth movement animations
  /// - Creates components for new tile instances
  /// - Animates movement when tiles move to different coords (awaited in parallel)
  /// - Updates sprite type when tileTypeId changes
  /// - Removes components for cleared tiles
  ///
  /// Key: Rebuilds coordinate maps fresh from model to prevent swap bugs
  Future<void> syncFromModel() async {
    // Track which instanceIds should exist (for cleanup)
    final activeInstanceIds = <int>{};
    // Collect all async operations (moves and type changes) to await in parallel
    final asyncOperations = <Future<void>>[];

    // ✅ Build fresh maps from the model (prevents swap clobber bugs)
    // Don't modify existing maps during the loop - build new ones and replace atomically
    final nextInstanceAtCoord = <Coord, int>{};
    final nextCoordByInstanceId = <int, Coord>{};

    // Loop through all playable cells
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final coord = Coord(row, col);

        // Skip void cells (not playable)
        if (!isPlayableCell(coord)) {
          continue;
        }

        final cell = gridModel.cells[row][col];

        // If cell has tileInstanceId + tileTypeId
        if (cell.tileInstanceId != null && cell.tileTypeId != null) {
          final instanceId = cell.tileInstanceId!;
          final tileTypeId = cell.tileTypeId!;
          activeInstanceIds.add(instanceId);

          // ✅ Record desired mappings (do NOT remove anything from old maps yet)
          nextInstanceAtCoord[coord] = instanceId;
          nextCoordByInstanceId[instanceId] = coord;

          final component = tilesByInstanceId[instanceId];

          // Create component if missing (use unified spawn function)
          if (component == null) {
            await spawnOrUpdateTileAt(coord, tileTypeId,
                instanceId: instanceId);
            // Component is now created and registered, continue to next cell
            continue;
          } else {
            // Component exists - check if it needs updates

            // Check if coord changed (tile moved)
            if (component.coord != coord) {
              // Always call moveToCoord - it supports retargeting
              // If already moving, it will cancel current animation and start new one
              // Collect the future to await all moves in parallel
              asyncOperations.add(component.moveToCoord(coord));
            } else if (!component.isMoving) {
              // Same coord and not moving, just ensure position is correct (in case of layout changes)
              component.position = coordToWorld(coord);
            }
            // If moving, don't snap position - let animation complete

            // Check if tileTypeId changed
            if (component.tileTypeId != tileTypeId) {
              // setType is async - collect to await later (sprite loading can happen in parallel)
              asyncOperations.add(component.setType(tileTypeId));
            }
          }
        }
      }
    }

    // Await all async operations in parallel (moves and type changes can happen simultaneously)
    // Await all async operations in parallel (moves and type changes can happen simultaneously)
    if (asyncOperations.isNotEmpty) {
      await Future.wait(asyncOperations);
    }

    // ✅ Now replace maps atomically (prevents race conditions and swap bugs)
    instanceAtCoord
      ..clear()
      ..addAll(nextInstanceAtCoord);

    coordByInstanceId
      ..clear()
      ..addAll(nextCoordByInstanceId);

    // ✅ Cleanup tiles that no longer exist
    final toRemove = <int>[];
    for (final id in tilesByInstanceId.keys) {
      if (!activeInstanceIds.contains(id)) {
        toRemove.add(id);
      }
    }
    for (final id in toRemove) {
      tilesByInstanceId[id]?.removeFromParent();
      tilesByInstanceId.remove(id);
    }

    // ✅ Always reset opacity on sync (guarantees VFX can't permanently hide tiles)
    // Since VFX finishes before clear+sync, we can reset everything
    for (final component in tilesByInstanceId.values) {
      component.opacity = 1.0;
    }

    // ✅ Sync blockers from model
    await _syncBlockersFromModel();
  }

  /// Synchronize blocker components with the grid model
  /// Creates/removes blocker overlays based on cell.blocker state
  Future<void> _syncBlockersFromModel() async {
    final activeBlocRokers = <Coord>{};

    // Loop through all playable cells
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final coord = Coord(row, col);

        // Skip void cells
        if (!isPlayableCell(coord)) {
          continue;
        }

        final cell = gridModel.cells[row][col];

        // If cell has a blocker
        if (cell.blocker != BlockerType.none) {
          activeBlocRokers.add(coord);

          // Create blocker component if missing
          if (!blockerComponents.containsKey(coord)) {
            // Get file path from cell (populated from JSON)
            final filePath = cell.blockerFilePath;
            if (filePath == null) {
              DebugLogger.error('Blocker at $coord has no filePath! Skipping.',
                  category: 'BoardGame');
              continue;
            }

            final blockerComponent = BlockerComponent(
              coord: coord,
              blockerType: cell.blocker,
              filePath: filePath,
              tileSize: tileSize,
              coordToWorld: coordToWorld,
            );
            add(blockerComponent);
            blockerComponents[coord] = blockerComponent;
          }
        }
      }
    }

    // Remove blockers that no longer exist
    final toRemove = <Coord>[];
    for (final coord in blockerComponents.keys) {
      if (!activeBlocRokers.contains(coord)) {
        toRemove.add(coord);
      }
    }
    for (final coord in toRemove) {
      blockerComponents[coord]?.removeFromParent();
      blockerComponents.remove(coord);
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Initialize SFX Manager (preload all AudioPools)
    await SfxManager.instance.init();
    debugPrint('[BoardGame] SfxManager initialized');

    // Start gameplay BGM
    await BgmManager.instance.playGameplayBgm();
    debugPrint('[BoardGame] Gameplay BGM started');

    // Components strip 'assets/' before loading through Flame's image cache.
    images.prefix = 'assets/';

    // Load the food tile atlas (single texture for regular tiles).
    await _loadTileAtlas();

    // Preload particle sprites
    await _loadParticleSprites();

    // Build the board: add beds first (background layer), then tiles
    // Skip void cells entirely (no bed, no tile)
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final coord = Coord(row, col);

        // Skip void cells (not playable)
        if (!isPlayableCell(coord)) {
          continue;
        }

        final cell = gridModel.cells[row][col];

        // Add bed component (background)
        if (cell.bedId != null && cell.bedId! >= 0) {
          final bedType = bedTypeById[cell.bedId] ?? stageData.bedTypes.first;
          final bedComponent = BedComponent(
            coord: coord,
            bedType: bedType,
            tileSize: tileSize,
            coordToWorld: coordToWorld,
          );
          add(bedComponent);
          bedComponents[coord] = bedComponent;
        }

        // Add tile component (foreground) using unified spawn function
        // InstanceIds should already be initialized by controller.initializeInstanceIds()
        if (cell.tileTypeId != null && cell.tileInstanceId != null) {
          await spawnOrUpdateTileAt(coord, cell.tileTypeId!,
              instanceId: cell.tileInstanceId, updateMaps: true);
        }
      }
    }

    // Validate board sync after initial load
    await validateBoardSync();

    // Sync blockers from model to show on first frame
    await _syncBlockersFromModel();

    // Ensure input is enabled after initialization
    _isBusy = false;
  }
}
