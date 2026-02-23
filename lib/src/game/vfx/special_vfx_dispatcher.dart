import '../model/coord.dart';
import '../utils/debug_logger.dart';
import '../board/board_game.dart';
import '../../audio/sfx_manager.dart';
import 'dragonfly_vfx.dart';
import 'party_popper_vfx.dart';
import 'firecracker_vfx.dart';
import 'sticky_rice_vfx.dart';
import 'sticky_rice_duo_vfx.dart';

/// Metadata for special tile activation VFX
/// Contains information needed for visual effects
class SpecialVfxMetadata {
  final Coord? targetCoord; // For DragonFly (105): the target tile coord
  final Set<Coord>? activationCells; // For StickyRice (103): tiles that will be cleared
  
  SpecialVfxMetadata({
    this.targetCoord,
    this.activationCells,
  });
}

/// Dispatcher for special tile visual effects
/// Entry point to play visuals for activated specials without mutating GridModel
class SpecialVfxDispatcher {
  /// Play visual effects for activated special tiles
  /// 
  /// Parameters:
  /// - game: The BoardGame instance for accessing components
  /// - activatedSpecials: Map of instanceId -> tileTypeId for activated specials (instanceId is stable during animations)
  /// - metadata: Optional metadata map (instanceId -> SpecialVfxMetadata) for additional VFX info
  /// 
  /// This does NOT mutate GridModel - it only plays visual effects
  static Future<void> playSpecialVfx({
    required BoardGame game,
    required Map<int, int> activatedSpecials,
    Map<int, SpecialVfxMetadata>? metadata,
  }) async {
    // Debug: Log activated specials
    DebugLogger.specialVfx('playSpecialVfx called with ${activatedSpecials.length} activated special(s)');
    for (final entry in activatedSpecials.entries) {
      final instanceId = entry.key;
      final specialTypeId = entry.value;
      DebugLogger.specialVfx('Activated special: instanceId=$instanceId, typeId=$specialTypeId');
      
      // Debug: Check if tile exists by instanceId
      final tile = game.getTileByInstanceId(instanceId);
      if (tile == null) {
        DebugLogger.error('getTileByInstanceId($instanceId) returned null!', category: 'SpecialVfxDispatcher');
      } else {
        DebugLogger.specialVfx('Found tile by instanceId=$instanceId: coord=${tile.coord}, tileTypeId=${tile.tileTypeId}');
      }
    }
    
    // Special case: StickyRice Duo (103+103 combo)
    // Check if exactly two entries, both type 103, both have activationCells
    if (activatedSpecials.length == 2) {
      final entries = activatedSpecials.entries.toList();
      final type1 = entries[0].value;
      final type2 = entries[1].value;
      
      if (type1 == 103 && type2 == 103) {
        final idA = entries[0].key;
        final idB = entries[1].key;
        final metaA = metadata?[idA];
        final metaB = metadata?[idB];
        
        // Check both have non-empty activationCells
        if (metaA?.activationCells != null && metaA!.activationCells!.isNotEmpty &&
            metaB?.activationCells != null && metaB!.activationCells!.isNotEmpty) {
          // Get both tiles
          final tileA = game.getTileByInstanceId(idA);
          final tileB = game.getTileByInstanceId(idB);
          
          if (tileA != null && tileB != null) {
            // Union of activation cells
            final unionActivationCells = <Coord>{
              ...metaA.activationCells!,
              ...metaB.activationCells!,
            };
            
            DebugLogger.specialVfx('StickyRice Duo detected: playing duo VFX for instanceIds=$idA, $idB');
            await StickyRiceDuoVfx.play(
              game: game,
              tileA: tileA,
              tileB: tileB,
              activationCells: unionActivationCells,
            );
            
            // Play single bloop after duo VFX and all tiles clear
            SfxManager.instance.playConfigured(SfxType.bloop);
            
            // Return immediately - skip the per-tile loop
            return;
          }
        }
      }
    }
    
    // Process each activated special in the order received (BoardController determines the exact sequence)
    // Do NOT sort - sorting would break combo step order and is unstable for ties
    for (final entry in activatedSpecials.entries) {
      final instanceId = entry.key;
      final specialTypeId = entry.value;
      final meta = metadata?[instanceId];
      
      // Get tile by instanceId (stable during animations)
      final tile = game.getTileByInstanceId(instanceId);
      if (tile == null) {
        DebugLogger.error('Tile not found by instanceId=$instanceId, skipping VFX', category: 'SpecialVfxDispatcher');
        continue;
      }
      
      final coord = tile.coord; // Get current coord from tile component
      
      DebugLogger.specialVfx('Playing VFX for special type $specialTypeId at $coord (instanceId=$instanceId)');
      
      switch (specialTypeId) {
        case 105: // DragonFly
          // Get target coord from metadata
          final targetCoord = meta?.targetCoord;
          if (targetCoord != null) {
            // Mark target coord to skip early burst (VFX will handle it after animation)
            game.markDragonflyTarget(targetCoord);
            
            await DragonFlyVfx.play(
              game: game,
              sourceTile: tile, // Pass tile directly instead of coord
              targetCoord: targetCoord,
            );
            
            // After VFX completes, mark target for special clear burst (enhanced burst)
            // Then unmark dragonfly target so the clear system can spawn the burst
            game.markSpecialClear(targetCoord);
            game.unmarkDragonflyTarget(targetCoord);
          }
          break;
        
        case 101: // PartyPopper_H
        case 102: // PartyPopper_V
          // Play shake effect for party popper
          DebugLogger.specialVfx('Playing party popper VFX for type $specialTypeId at $coord (instanceId=$instanceId)');
          await PartyPopperVfx.play(
            game: game,
            tile: tile, // Pass tile directly instead of coord
            partyPopperType: specialTypeId, // Pass type to determine orientation
          );
          break;
        case 104: // Firecracker
          // Play explosion effect for firecracker
          DebugLogger.specialVfx('Playing firecracker VFX at $coord (instanceId=$instanceId)');
          await FirecrackerVfx.play(
            game: game,
            tile: tile, // Pass tile directly instead of coord
          );
          break;
        
        case 103: // StickyRice
          // Play sticky rice VFX with warning → explode outward sequence
          // activationCells should always be provided (especially for combos)
          final activationCells = meta?.activationCells;
          if (activationCells != null && activationCells.isNotEmpty) {
            DebugLogger.specialVfx('Playing sticky rice VFX at $coord (instanceId=$instanceId) with ${activationCells.length} activation cells');
            await StickyRiceVfx.play(
              game: game,
              tile: tile,
              activationCells: activationCells,
            );
          } else {
            DebugLogger.warn('StickyRice (103) at $coord (instanceId=$instanceId) missing activationCells in metadata!', category: 'SpecialVfxDispatcher');
          }
          break;
        
        default:
          // Unknown special type - skip VFX
          break;
      }
    }
  }
}
