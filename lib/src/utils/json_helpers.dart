/// Helper utilities for JSON parsing
/// Reduces boilerplate when converting JSON values to Dart types
library;

/// Convert JSON number value to double
double parseDouble(dynamic value) => (value as num).toDouble();

/// Convert JSON number value to int
int parseInt(dynamic value) => (value as num).toInt();

/// Parse optional double (returns null if value is null)
double? parseDoubleOrNull(dynamic value) => 
    value != null ? (value as num).toDouble() : null;

/// Parse optional int (returns null if value is null)
int? parseIntOrNull(dynamic value) => 
    value != null ? (value as num).toInt() : null;

/// Extension methods for cleaner JSON parsing
extension JsonMapExtensions on Map<String, dynamic> {
  /// Get double value with key
  double getDouble(String key) => parseDouble(this[key]);
  
  /// Get int value with key
  int getInt(String key) => parseInt(this[key]);
  
  /// Get optional double value with key
  double? getDoubleOrNull(String key) => parseDoubleOrNull(this[key]);
  
  /// Get optional int value with key
  int? getIntOrNull(String key) => parseIntOrNull(this[key]);
  
  /// Get nested double from path like ['position']['x']
  double getNestedDouble(String key1, String key2) =>
      parseDouble((this[key1] as Map<String, dynamic>)[key2]);
}
