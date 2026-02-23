import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'inventory.dart';
import '../utils/debug_logger.dart';

/// Repository for managing player inventory with persistence
class InventoryRepository {
  static const String _prefsKey = 'player_inventory_v4'; // v4: Hard-coded defaults
  
  /// Default starter inventory (hard-coded) - All start at 0
  static final Map<String, int> _defaultBoosters = {
    '101': 0, // Party Popper Horizontal
    '102': 0, // Party Popper Vertical
    '103': 0, // Sticky Rice Bomb
    '104': 0, // Firecracker
    '105': 0, // DragonFly
  };

  /// Load inventory from SharedPreferences, or defaults if not found
  Future<Inventory> loadInventory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // DEBUG: Log all stored keys
      final keys = prefs.getKeys();
      DebugLogger.inventory('SharedPreferences keys: $keys');
      
      final jsonString = prefs.getString(_prefsKey);
      DebugLogger.inventory('Looking for key: $_prefsKey, found: ${jsonString != null}');

      if (jsonString != null) {
        // Load existing inventory from SharedPreferences
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final inventory = Inventory.fromJson(json);
        DebugLogger.inventory('✅ Loaded from SharedPreferences ($_prefsKey): $inventory');
        return inventory;
      } else {
        // No saved inventory - use hard-coded defaults and save
        DebugLogger.inventory('❌ No saved data for $_prefsKey - using hard-coded defaults');
        final inventory = _createDefaultInventory();
        await saveInventory(inventory);
        DebugLogger.inventory('✅ Saved fresh inventory to $_prefsKey: $inventory');
        return inventory;
      }
    } catch (e) {
      DebugLogger.error('Failed to load inventory: $e', category: 'Inventory');
      // Fallback to defaults
      final inventory = _createDefaultInventory();
      await saveInventory(inventory);
      return inventory;
    }
  }

  /// Create default inventory (hard-coded values)
  Inventory _createDefaultInventory() {
    final inventory = Inventory(
      boosters: Map<String, int>.from(_defaultBoosters),
    );
    DebugLogger.inventory('Created default inventory: $inventory');
    return inventory;
  }

  /// Save inventory to SharedPreferences
  Future<void> saveInventory(Inventory inventory) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(inventory.toJson());
      await prefs.setString(_prefsKey, jsonString);
      DebugLogger.inventory('Saved inventory: $inventory');
    } catch (e) {
      DebugLogger.error('Failed to save inventory: $e', category: 'Inventory');
    }
  }

  /// Add booster to inventory
  Future<void> addBooster(Inventory inventory, String id, int amount) async {
    if (amount <= 0) {
      DebugLogger.warn('Attempted to add non-positive booster amount: $amount for $id', category: 'Inventory');
      return;
    }

    final currentCount = inventory.boosters[id] ?? 0;
    inventory.boosters[id] = currentCount + amount;
    await saveInventory(inventory);
    DebugLogger.inventory('Added $amount of booster $id, new count: ${inventory.boosters[id]}');
  }

  /// Consume a booster (returns true if successful, false if not available)
  Future<bool> consumeBooster(Inventory inventory, String id) async {
    final currentCount = inventory.boosters[id] ?? 0;
    
    if (currentCount <= 0) {
      DebugLogger.warn('Cannot consume booster $id: insufficient count ($currentCount)', category: 'Inventory');
      return false;
    }

    inventory.boosters[id] = currentCount - 1;
    await saveInventory(inventory);
    DebugLogger.inventory('Consumed booster $id, remaining: ${inventory.boosters[id]}');
    return true;
  }

  /// Reset inventory to defaults (useful for testing or reset functionality)
  Future<void> resetInventory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    DebugLogger.inventory('Inventory reset - will load defaults on next load');
  }
  
  /// Force reload from hard-coded defaults (clears saved data and loads fresh)
  Future<Inventory> forceLoadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    final inventory = _createDefaultInventory();
    await saveInventory(inventory);
    DebugLogger.inventory('Force loaded hard-coded defaults: $inventory');
    return inventory;
  }
}
