import 'dart:convert';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SFX Manager for handling all game sound effects
/// 
/// Features:
/// - AudioPool for each sound (prevents cutting off)
/// - Preload all SFX for instant playback
/// - Volume control with persistence
/// - Sound on/off toggle
/// - Singleton pattern with init()
class SfxManager {
  static final SfxManager _instance = SfxManager._internal();
  static SfxManager get instance => _instance;
  
  factory SfxManager() => _instance;
  SfxManager._internal();

  // Sound settings
  bool _soundEnabled = true;
  double _volume = 1.0; // Master volume defaults to 1.0
  double _masterGain = 2.0; // Master gain multiplier for louder SFX (overridden by JSON)
  bool _isInitialized = false;

  // SFX tuning configuration (loaded from JSON)
  final Map<SfxType, _SfxTuning> _tuning = {};
  _SfxTuning? _defaultTuning;
  
  // Cooldown tracking: last played timestamp per SfxType
  final Map<SfxType, DateTime> _lastPlayed = {};

  // AudioPools for each sound (prevents cutting off)
  final Map<SfxType, AudioPool> _audioPools = {};
  
  // Explicit manifest: maps SfxType to file path (relative to assets/audio/)
  final Map<SfxType, String> _sfxManifest = {
    SfxType.swipe: 'sfx/swipe.wav',
    SfxType.bloop: 'sfx/bloop.wav', // Normal match sound
    SfxType.stickyRiceBombBloop: 'sfx/bloop.wav', // Reuse bloop.wav with pitch variation
    SfxType.partyPopperLaunch: 'sfx/party_popper_launch.wav',
    SfxType.dragonFlyLaunch: 'sfx/dragon_fly_launch.wav',
    SfxType.firecracker: 'sfx/firecracker.wav',
    SfxType.gong: 'sfx/gong.wav', // Sticky Rice Duo combo
    SfxType.yayCheer: 'sfx/yay_cheer.mp3', // Celebration for rewards
    SfxType.scooter: 'sfx/scooter_sfx.wav', // Scooter animation start (NEW, fixed path)
  };
  
  // Pool sizes (maxPlayers per sound)
  final Map<SfxType, int> _poolSizes = {
    SfxType.swipe: 6, // High for UI responsiveness
    SfxType.bloop: 8, // Normal match sounds, needs high pool for cascades
    SfxType.stickyRiceBombBloop: 3, // Sticky rice bomb special clears
    SfxType.partyPopperLaunch: 3,
    SfxType.dragonFlyLaunch: 3,
    SfxType.firecracker: 3,
    SfxType.gong: 1, // Sticky Rice Duo combo (rare)
    SfxType.yayCheer: 2, // Celebration for rewards
    SfxType.scooter: 2, // Scooter sound, low pool to avoid overlap
  };

  // Getters
  bool get isSoundEnabled => _soundEnabled;
  double get volume => _volume;
  bool get isInitialized => _isInitialized;

  /// Initialize the SFX manager
  /// Call this once at app startup (e.g., BoardGame.onLoad)
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      debugPrint('[SfxManager] Initializing with AudioPools...');

      // Load preferences
      await _loadPreferences();

      // Load SFX tuning from JSON
      await _loadTuning();

      // Preload all sound effects as AudioPools
      await _preloadPools();

      _isInitialized = true;
      debugPrint('[SfxManager] Initialization complete');
    } catch (e) {
      debugPrint('[SfxManager] Initialization error: $e');
    }
  }

  /// Load sound preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool('sound_enabled') ?? true;
    _volume = prefs.getDouble('sound_volume') ?? 1.0;
    debugPrint('[SfxManager] Loaded preferences: enabled=$_soundEnabled, volume=$_volume');
  }

  /// Load SFX tuning from JSON file
  Future<void> _loadTuning() async {
    try {
      final jsonString = await rootBundle.loadString('assets/audio/sfx_tuning.json');
      final Map<String, dynamic> json = jsonDecode(jsonString);
      
      // Load master gain from JSON (overrides hardcoded value)
      if (json['masterGain'] != null) {
        _masterGain = (json['masterGain'] as num).toDouble();
      }
      
      // Load default tuning
      if (json['defaults'] != null) {
        final defaults = json['defaults'] as Map<String, dynamic>;
        _defaultTuning = _SfxTuning(
          volume: (defaults['volume'] as num?)?.toDouble() ?? 1.0,
          cooldownMs: defaults['cooldownMs'] as int? ?? 0,
          delayMs: defaults['delayMs'] as int? ?? 0,
        );
      } else {
        _defaultTuning = _SfxTuning(volume: 1.0, cooldownMs: 0, delayMs: 0);
      }
      
      // Load per-SFX tuning
      if (json['sfx'] != null) {
        final sfxMap = json['sfx'] as Map<String, dynamic>;
        for (final entry in sfxMap.entries) {
          final sfxType = _sfxTypeFromString(entry.key);
          if (sfxType != null) {
            final tuning = entry.value as Map<String, dynamic>;
            _tuning[sfxType] = _SfxTuning(
              volume: (tuning['volume'] as num?)?.toDouble() ?? _defaultTuning!.volume,
              cooldownMs: tuning['cooldownMs'] as int? ?? _defaultTuning!.cooldownMs,
              delayMs: tuning['delayMs'] as int? ?? _defaultTuning!.delayMs,
            );
          }
        }
      }
      
      debugPrint('[SfxManager] Loaded tuning: masterGain=$_masterGain, ${_tuning.length} SFX configured');
    } catch (e) {
      debugPrint('[SfxManager] Failed to load tuning JSON, using defaults: $e');
      _defaultTuning = _SfxTuning(volume: 1.0, cooldownMs: 0, delayMs: 0);
    }
  }
  
  /// Convert string to SfxType enum
  SfxType? _sfxTypeFromString(String name) {
    try {
      return SfxType.values.firstWhere((e) => e.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Preload all sound effects as AudioPools using explicit manifest
  Future<void> _preloadPools() async {
    debugPrint('[SfxManager] Preloading AudioPools from manifest...');
    
    // Ensure swipe is always loaded first
    await _loadSfxPool(SfxType.swipe);
    
    // Load remaining SFX
    for (final sfx in SfxType.values) {
      if (sfx == SfxType.swipe) continue; // Already loaded
      await _loadSfxPool(sfx);
    }
    
    debugPrint('[SfxManager] Loaded ${_audioPools.length}/${_sfxManifest.length} pools');
  }
  
  /// Load a single SFX pool from manifest
  Future<void> _loadSfxPool(SfxType sfx) async {
    final filePath = _sfxManifest[sfx];
    if (filePath == null) {
      debugPrint('[SfxManager] No manifest entry for ${sfx.name}');
      return;
    }
    
    final poolSize = _poolSizes[sfx] ?? 3;
    
    try {
      // FlameAudio.createPool expects path relative to assets/audio/
      final pool = await FlameAudio.createPool(
        filePath,
        maxPlayers: poolSize,
      );
      _audioPools[sfx] = pool;
      debugPrint('[SfxManager] ✓ Created pool for ${sfx.name}: path=$filePath, maxPlayers=$poolSize');
    } catch (e) {
      debugPrint('[SfxManager] ✗ Failed to create pool for ${sfx.name}: $e');
    }
  }

  /// Play a sound effect using AudioPool (fire-and-forget)
  /// Does NOT use JSON tuning - use playTuned() for that
  void play(SfxType sfx, {double? volume}) {
    if (!_soundEnabled) {
      debugPrint('[SfxManager] Sound disabled, skipping ${sfx.name}');
      return;
    }
    if (!_isInitialized) {
      debugPrint('[SfxManager] Not initialized, skipping ${sfx.name}');
      return;
    }

    final pool = _audioPools[sfx];
    if (pool == null) {
      debugPrint('[SfxManager] Pool not found for ${sfx.name}');
      return;
    }

    // Use provided volume or default to master volume, then apply gain
    final baseVolume = volume ?? _volume;
    final finalVolume = (baseVolume * _masterGain).clamp(0.0, 1.0);
    
    debugPrint('[SfxManager] Playing ${sfx.name} at volume $finalVolume (base=$baseVolume, gain=$_masterGain)');
    
    try {
      pool.start(volume: finalVolume);
    } catch (e) {
      debugPrint('[SfxManager] Error playing ${sfx.name}: $e');
    }
  }
  
  /// Play a sound effect with JSON tuning (cooldown, delay, volume multiplier)
  void playTuned(SfxType sfx, {double? volumeOverride, double? pitch}) {
    if (!_soundEnabled) return;
    if (!_isInitialized) return;

    final pool = _audioPools[sfx];
    if (pool == null) {
      debugPrint('[SfxManager] Pool not found for ${sfx.name}');
      return;
    }
    
    // Get tuning config (fall back to defaults)
    final tuning = _tuning[sfx] ?? _defaultTuning ?? _SfxTuning(volume: 1.0, cooldownMs: 0, delayMs: 0);
    
    // Check cooldown
    if (tuning.cooldownMs > 0) {
      final lastPlayedTime = _lastPlayed[sfx];
      if (lastPlayedTime != null) {
        final elapsed = DateTime.now().difference(lastPlayedTime).inMilliseconds;
        if (elapsed < tuning.cooldownMs) {
          debugPrint('[SfxManager] ${sfx.name} on cooldown (${tuning.cooldownMs - elapsed}ms remaining)');
          return;
        }
      }
    }
    
    // Compute final volume: (volumeOverride ?? _volume) * tuning.volume * _masterGain
    final baseVolume = volumeOverride ?? _volume;
    final finalVolume = (baseVolume * tuning.volume * _masterGain).clamp(0.0, 1.0);
    
    // Note: pitch parameter is accepted but not used (AudioPool doesn't support rate/pitch)
    
    // Schedule playback with delay
    final delayDuration = Duration(milliseconds: tuning.delayMs);
    
    debugPrint('[SfxManager] Tuned ${sfx.name}: delayMs=${tuning.delayMs}, cooldownMs=${tuning.cooldownMs}, volume=$finalVolume (base=$baseVolume, tuning=${tuning.volume}, gain=$_masterGain)');
    
    Future.delayed(delayDuration, () {
      if (!_soundEnabled || !_isInitialized) return;
      
      try {
        pool.start(volume: finalVolume);
        _lastPlayed[sfx] = DateTime.now();
      } catch (e) {
        debugPrint('[SfxManager] Error playing tuned ${sfx.name}: $e');
      }
    });
  }
  
  /// Alias for playTuned() - play with JSON configuration
  void playConfigured(SfxType sfx, {double? volumeOverride, double? pitch}) {
    playTuned(sfx, volumeOverride: volumeOverride, pitch: pitch);
  }

  /// Enable or disable sound
  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', enabled);
    debugPrint('[SfxManager] Sound ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Set volume level (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sound_volume', _volume);
    debugPrint('[SfxManager] Volume set to $_volume');
  }

  /// Toggle sound on/off
  Future<void> toggleSound() async {
    await setSoundEnabled(!_soundEnabled);
  }

  /// Dispose and clean up resources
  void dispose() {
    // Dispose all pools
    for (final pool in _audioPools.values) {
      pool.dispose();
    }
    _audioPools.clear();
    _isInitialized = false;
    debugPrint('[SfxManager] Disposed');
  }
}

/// SFX tuning configuration loaded from JSON
class _SfxTuning {
  final double volume;      // Volume multiplier (applied before masterGain)
  final int cooldownMs;     // Minimum time between plays in milliseconds
  final int delayMs;        // Delay before playing in milliseconds
  
  const _SfxTuning({
    required this.volume,
    required this.cooldownMs,
    required this.delayMs,
  });
}

/// Enum for all available sound effects
enum SfxType {
  // UI sounds
  swipe,            // Tile swipe/swap
  
  // Match sounds
  bloop,                     // Normal tile matches
  stickyRiceBombBloop,      // Sticky Rice Bomb special clear (with pitch variation)
  
  // Power-up sounds
  firecracker,           // Firecracker explosion
  dragonFlyLaunch,       // Dragonfly launch
  partyPopperLaunch,     // Party Popper launch
  
  // Special combo sounds
  gong,                  // Sticky Rice Duo (103+103) combo
  
  // Reward sounds
  yayCheer,              // Celebration for rewards
  scooter,               // Scooter animation start (NEW, fixed path)
}
