import 'package:flutter/foundation.dart';
import 'inventory.dart';
import 'inventory_repository.dart';
import '../utils/debug_logger.dart';

/// Model for power-up inventory and equipped belt
/// Wraps Inventory and InventoryRepository with ChangeNotifier for UI updates
class InventoryModel extends ChangeNotifier {
  final InventoryRepository _repository = InventoryRepository();
  Inventory? _inventory;

  // Belt slots: ordered list of typeIds (typically [101, 102, 103, 104, 105])
  final List<int> _beltSlots = [101, 102, 103, 104, 105];
  
  /// Get current inventory (null if not loaded yet)
  Inventory? get inventory => _inventory;

  /// Get count for a power typeId (booster)
  int getCount(int typeId) {
    return _inventory?.getBoosterCount(typeId.toString()) ?? 0;
  }

  /// Check if a power can be used (count > 0)
  bool canUse(int typeId) {
    return getCount(typeId) > 0;
  }

  /// Get belt slots
  List<int> get beltSlots => List.unmodifiable(_beltSlots);
  
  /// Check if inventory is loaded
  bool get isLoaded => _inventory != null;

  /// Add power-up/booster to inventory
  Future<void> add(int typeId, int amount) async {
    if (_inventory == null) {
      DebugLogger.warn('Cannot add booster: inventory not loaded', category: 'Inventory');
      return;
    }
    
    await _repository.addBooster(_inventory!, typeId.toString(), amount);
    notifyListeners();
  }

  /// Spend/consume power-up from inventory
  /// Returns true if successful, false if insufficient count
  Future<bool> spend(int typeId, int amount) async {
    if (_inventory == null) {
      DebugLogger.warn('Cannot spend booster: inventory not loaded', category: 'Inventory');
      return false;
    }
    
    // Consume multiple boosters
    for (int i = 0; i < amount; i++) {
      final success = await _repository.consumeBooster(_inventory!, typeId.toString());
      if (!success) {
        DebugLogger.warn('Failed to consume booster $typeId (consumed $i out of $amount)', category: 'Inventory');
        notifyListeners();
        return false;
      }
    }
    
    notifyListeners();
    return true;
  }

  /// Load inventory from SharedPreferences or defaults
  Future<void> load() async {
    _inventory = await _repository.loadInventory();
    notifyListeners();
    DebugLogger.inventory('Inventory loaded: boosters=${_inventory!.boosters}');
  }
  
  /// Reset inventory to defaults (clears SharedPreferences)
  Future<void> reset() async {
    await _repository.resetInventory();
    _inventory = await _repository.loadInventory();
    notifyListeners();
    DebugLogger.inventory('Inventory reset to defaults');
  }
  
  /// Force reload from JSON (for debugging/testing)
  /// Use this if inventory is stuck at 0
  Future<void> forceLoadDefaults() async {
    _inventory = await _repository.forceLoadDefaults();
    notifyListeners();
    DebugLogger.inventory('Force reloaded from JSON: ${_inventory!.boosters}');
  }
}
