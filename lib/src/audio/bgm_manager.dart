import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/utils/debug_logger.dart';

/// BGM Manager for handling background music
/// 
/// Features:
/// - Single AudioPlayer instance (singleton)
/// - Load once, loop forever
/// - Volume control with persistence
/// - Music on/off toggle
/// - Simple start(), pause(), resume(), stop() controls
/// - Crossfade between tracks
class BgmManager {
  static final BgmManager _instance = BgmManager._internal();
  static BgmManager get instance => _instance;
  
  factory BgmManager() => _instance;
  BgmManager._internal();

  // Single audio player for all BGM (lives for entire app lifecycle)
  final AudioPlayer _player = AudioPlayer();
  
  // BGM settings
  bool _musicEnabled = true;
  double _volume = 0.25; // Default BGM volume (25%)
  final double _menuVolume = 0.20; // Menu BGM volume (20%)
  final double _gameplayVolume = 0.10; // Gameplay BGM volume (10% - lower to not compete with SFX)
  final double _festivalVolume = 0.15; // Festival BGM volume (15%)
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentTrack; // Track currently playing
  String? _pendingWebTrack; // Track to retry after first web user interaction
  bool _isRetryingWebUnlock = false;
  
  // Crossfade settings
  static const int _crossfadeDurationMs = 400; // 400ms crossfade
  
  // BGM track definitions (3 tracks)
  static const String menuBgm = 'audio/bgm/Menu_BGM.mp3';
  static const String gameplayBgm = 'audio/bgm/gameplay_BGM.mp3';
  static const String festivalBgm = 'audio/bgm/vietnamese-festival-bgm.mp3';

  /// Initialize BGM Manager
  /// Call this once at app startup
  /// Preloads audio player and configures for infinite loop
  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      DebugLogger.log('Initializing BGM Manager...', category: 'BgmManager');
      
      // Load settings from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _musicEnabled = prefs.getBool('music_enabled') ?? true;
      _volume = prefs.getDouble('music_volume') ?? 0.25;
      
      // Configure player to loop forever
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_volume);
      
      _isInitialized = true;
      DebugLogger.log('BGM Manager initialized (music: $_musicEnabled, volume: $_volume)', category: 'BgmManager');
    } catch (e) {
      DebugLogger.error('Error initializing BGM Manager: $e', category: 'BgmManager');
    }
  }

  /// Start playing menu background music
  /// Loads once and loops forever
  Future<void> playMenuBgm() async {
    await start(menuBgm);
  }
  
  /// Start playing gameplay background music
  /// Loads once and loops forever
  Future<void> playGameplayBgm() async {
    await start(gameplayBgm);
  }
  
  /// Start playing festival background music
  /// Loads once and loops forever
  Future<void> playFestivalBgm() async {
    await start(festivalBgm);
  }
  
  /// Start playing a specific BGM track
  /// Loads the track and plays it on infinite loop
  /// Handles crossfade if switching from another track
  Future<void> start(String trackPath) async {
    if (!_isInitialized) {
      DebugLogger.warn('BGM Manager not initialized, call init() first', category: 'BgmManager');
      return;
    }
    
    if (!_musicEnabled) {
      DebugLogger.log('Music disabled, not starting track', category: 'BgmManager');
      return;
    }
    
    // If same track is already playing, don't restart
    if (_isPlaying && _currentTrack == trackPath) {
      DebugLogger.log('Track already playing: $trackPath', category: 'BgmManager');
      return;
    }
    
    // Determine target volume based on track
    double targetVolume = _menuVolume;
    if (trackPath == gameplayBgm) {
      targetVolume = _gameplayVolume;
    } else if (trackPath == festivalBgm) {
      targetVolume = _festivalVolume;
    }
    
    try {
      // If switching tracks, do crossfade
      if (_isPlaying && _currentTrack != null && _currentTrack != trackPath) {
        DebugLogger.log('Crossfading from $_currentTrack to $trackPath', category: 'BgmManager');
        
        // Fade out current track
        await _fadeVolume(_volume, 0.0, _crossfadeDurationMs);
        
        // Stop old track
        await _player.stop();
      }
      
      // Start new track at volume 0
      await _player.setVolume(0.0);
      await _player.play(AssetSource(trackPath));
      _isPlaying = true;
      _currentTrack = trackPath;
      
      // Fade in to target volume
      await _fadeVolume(0.0, targetVolume, _crossfadeDurationMs);
      _pendingWebTrack = null;
      
      DebugLogger.log('Now playing: $trackPath at volume $targetVolume (looping forever)', category: 'BgmManager');
    } catch (e) {
      DebugLogger.error('Error starting BGM: $e', category: 'BgmManager');
      if (kIsWeb) {
        _isPlaying = false;
        _pendingWebTrack = trackPath;
        DebugLogger.log(
          'Web audio likely blocked by autoplay policy. Queued for first user interaction: $trackPath',
          category: 'BgmManager',
        );
      }
    }
  }

  /// Called from a user gesture handler to unlock/retry audio on web.
  Future<void> onUserInteraction() async {
    if (!kIsWeb) return;
    if (_isRetryingWebUnlock) return;
    if (!_isInitialized || !_musicEnabled || _isPlaying) return;

    final trackToRetry = _pendingWebTrack ?? _currentTrack;
    if (trackToRetry == null) return;

    _isRetryingWebUnlock = true;
    try {
      await start(trackToRetry);
    } finally {
      _isRetryingWebUnlock = false;
    }
  }
  
  /// Gradually fade volume from start to end over duration
  Future<void> _fadeVolume(double startVolume, double endVolume, int durationMs) async {
    const int steps = 20; // Number of steps in the fade
    final stepDuration = durationMs ~/ steps;
    final volumeStep = (endVolume - startVolume) / steps;
    
    for (int i = 1; i <= steps; i++) {
      final newVolume = startVolume + (volumeStep * i);
      await _player.setVolume(newVolume.clamp(0.0, 1.0));
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Pause background music
  Future<void> pause() async {
    if (!_isPlaying) return;
    
    try {
      await _player.pause();
      _isPlaying = false;
      DebugLogger.log('BGM paused', category: 'BgmManager');
    } catch (e) {
      DebugLogger.error('Error pausing BGM: $e', category: 'BgmManager');
    }
  }

  /// Resume background music
  Future<void> resume() async {
    if (_isPlaying) return;
    
    try {
      await _player.resume();
      _isPlaying = true;
      DebugLogger.log('BGM resumed', category: 'BgmManager');
    } catch (e) {
      DebugLogger.error('Error resuming BGM: $e', category: 'BgmManager');
      // If resume fails, try to restart the current track
      if (_currentTrack != null) {
        DebugLogger.log('Resume failed, restarting track: $_currentTrack', category: 'BgmManager');
        _isPlaying = false; // Reset flag
        await start(_currentTrack!);
      }
    }
  }

  /// Stop background music
  Future<void> stop() async {
    if (!_isPlaying) return;
    
    try {
      await _player.stop();
      _isPlaying = false;
      _currentTrack = null;
      DebugLogger.log('BGM stopped', category: 'BgmManager');
    } catch (e) {
      DebugLogger.error('Error stopping BGM: $e', category: 'BgmManager');
    }
  }

  /// Toggle music on/off
  Future<void> toggleMusic() async {
    _musicEnabled = !_musicEnabled;
    
    if (_musicEnabled) {
      // Resume current track if we have one
      if (_currentTrack != null) {
        await start(_currentTrack!);
      }
    } else {
      await stop();
    }
    
    // Persist setting
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('music_enabled', _musicEnabled);
    DebugLogger.log('Music toggled: $_musicEnabled', category: 'BgmManager');
  }

  /// Set music volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    
    // Persist setting
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('music_volume', _volume);
    DebugLogger.log('Volume set to: $_volume', category: 'BgmManager');
  }

  /// Get current music enabled state
  bool get isMusicEnabled => _musicEnabled;
  
  /// Get current music volume
  double get volume => _volume;
  
  /// Get current playing state
  bool get isPlaying => _isPlaying;
  
  /// Get current track path
  String? get currentTrack => _currentTrack;

  /// Dispose resources
  Future<void> dispose() async {
    await _player.dispose();
    _isInitialized = false;
    _isPlaying = false;
    DebugLogger.log('BGM Manager disposed', category: 'BgmManager');
  }
}
