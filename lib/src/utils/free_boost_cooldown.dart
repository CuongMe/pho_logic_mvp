import 'package:shared_preferences/shared_preferences.dart';

/// Persists the next time a free boost can be claimed.
class FreeBoostCooldown {
  FreeBoostCooldown._();

  static const Duration duration = Duration(seconds: 45);
  static const String _nextClaimAtMsKey = 'free_boost_next_claim_at_ms';

  static Duration remaining(SharedPreferences prefs, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final nextClaimMs = prefs.getInt(_nextClaimAtMsKey) ?? 0;
    if (nextClaimMs <= nowMs) {
      return Duration.zero;
    }
    return Duration(milliseconds: nextClaimMs - nowMs);
  }

  static int remainingSeconds(SharedPreferences prefs, {DateTime? now}) {
    final remainingDuration = remaining(prefs, now: now);
    if (remainingDuration == Duration.zero) {
      return 0;
    }
    return (remainingDuration.inMilliseconds / 1000).ceil();
  }

  static Future<void> start(SharedPreferences prefs, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final nextClaimMs = nowMs + duration.inMilliseconds;
    return prefs.setInt(_nextClaimAtMsKey, nextClaimMs);
  }
}
