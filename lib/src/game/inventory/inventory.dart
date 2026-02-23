/// Inventory data model containing boosters
class Inventory {
  Map<String, int> boosters;

  Inventory({
    required this.boosters,
  });

  /// Create Inventory from JSON
  factory Inventory.fromJson(Map<String, dynamic> json) {
    return Inventory(
      boosters: Map<String, int>.from(
        (json['boosters'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, value as int),
        ),
      ),
    );
  }

  /// Convert Inventory to JSON
  Map<String, dynamic> toJson() {
    return {
      'boosters': boosters,
    };
  }

  /// Create a copy of this inventory
  Inventory copy() {
    return Inventory(
      boosters: Map<String, int>.from(boosters),
    );
  }

  /// Get booster count by ID (returns 0 if not found)
  int getBoosterCount(String id) {
    return boosters[id] ?? 0;
  }

  /// Check if a booster is available
  bool hasBooster(String id) {
    return getBoosterCount(id) > 0;
  }

  @override
  String toString() {
    return 'Inventory(boosters: $boosters)';
  }
}
