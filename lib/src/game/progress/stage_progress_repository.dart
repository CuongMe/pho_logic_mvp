import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/debug_logger.dart';

enum StageResult {
  cleared,
  lose,
}

extension StageResultStorage on StageResult {
  String get storageValue {
    switch (this) {
      case StageResult.cleared:
        return 'cleared';
      case StageResult.lose:
        return 'lose';
    }
  }

  String get label {
    switch (this) {
      case StageResult.cleared:
        return 'Cleared';
      case StageResult.lose:
        return 'Lose';
    }
  }

  static StageResult? fromStorage(String value) {
    switch (value) {
      case 'cleared':
        return StageResult.cleared;
      case 'lose':
        return StageResult.lose;
      default:
        return null;
    }
  }
}

/// Persists per-stage latest result (cleared or lose).
class StageProgressRepository {
  static const String _prefsKey = 'stage_progress_v1';

  Future<Map<int, StageResult>> loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        return {};
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        DebugLogger.warn(
          'Invalid progress payload type: ${decoded.runtimeType}',
          category: 'StageProgress',
        );
        return {};
      }

      final progress = <int, StageResult>{};
      decoded.forEach((stageIdRaw, resultRaw) {
        final stageId = int.tryParse(stageIdRaw);
        final result = resultRaw is String
            ? StageResultStorage.fromStorage(resultRaw)
            : null;
        if (stageId != null && result != null) {
          progress[stageId] = result;
        }
      });

      return progress;
    } catch (e) {
      DebugLogger.error('Failed to load stage progress: $e',
          category: 'StageProgress');
      return {};
    }
  }

  Future<void> saveStageResult(int stageId, StageResult result) async {
    if (stageId <= 0) {
      DebugLogger.warn('Ignoring invalid stageId: $stageId',
          category: 'StageProgress');
      return;
    }

    final progress = await loadProgress();
    progress[stageId] = result;
    await _saveProgress(progress);
  }

  Future<void> _saveProgress(Map<int, StageResult> progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = <String, String>{
        for (final entry in progress.entries)
          entry.key.toString(): entry.value.storageValue,
      };
      await prefs.setString(_prefsKey, jsonEncode(serializable));
    } catch (e) {
      DebugLogger.error('Failed to save stage progress: $e',
          category: 'StageProgress');
    }
  }
}
