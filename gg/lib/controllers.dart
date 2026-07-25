import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum CustomLoopMode {
  off,
  all,
  one,
}

class QueueController<T> {
  final List<T> originalSongs;
  List<T> currentSongs;
  int activeIndex;
  bool isShuffleEnabled;
  CustomLoopMode loopMode;
  List<int> _currentIndices;

  QueueController({
    required List<T> songs,
    int initialIndex = 0,
    bool shuffle = false,
    CustomLoopMode loop = CustomLoopMode.off,
  })  : originalSongs = List.from(songs),
        currentSongs = List.from(songs),
        activeIndex = initialIndex,
        isShuffleEnabled = shuffle,
        loopMode = loop,
        _currentIndices = List.generate(songs.length, (i) => i) {
    if (shuffle && songs.isNotEmpty) {
      isShuffleEnabled = false;
      setShuffleEnabled(true);
    }
  }

  void setShuffleEnabled(bool enabled) {
    if (isShuffleEnabled == enabled || originalSongs.isEmpty) return;
    if (enabled) {
      final currentOrigIndex = _currentIndices[activeIndex];
      
      // Get all other indices
      final otherIndices = List.generate(originalSongs.length, (i) => i)
        ..remove(currentOrigIndex);
      
      otherIndices.shuffle();
      
      _currentIndices = [currentOrigIndex, ...otherIndices];
      currentSongs = _currentIndices.map((idx) => originalSongs[idx]).toList();
      activeIndex = 0;
      isShuffleEnabled = true;
    } else {
      final currentOrigIndex = _currentIndices[activeIndex];
      
      _currentIndices = List.generate(originalSongs.length, (i) => i);
      currentSongs = List.from(originalSongs);
      activeIndex = currentOrigIndex;
      isShuffleEnabled = false;
    }
  }

  void setLoopMode(CustomLoopMode mode) {
    loopMode = mode;
  }

  void skipNext() {
    if (currentSongs.isEmpty) return;
    switch (loopMode) {
      case CustomLoopMode.one:
        // stays on the same song
        break;
      case CustomLoopMode.all:
        activeIndex = (activeIndex + 1) % currentSongs.length;
        break;
      case CustomLoopMode.off:
        if (activeIndex < currentSongs.length - 1) {
          activeIndex++;
        }
        break;
    }
  }

  void skipPrevious() {
    if (currentSongs.isEmpty) return;
    switch (loopMode) {
      case CustomLoopMode.one:
        // stays on the same song
        break;
      case CustomLoopMode.all:
        activeIndex = (activeIndex - 1 + currentSongs.length) % currentSongs.length;
        break;
      case CustomLoopMode.off:
        if (activeIndex > 0) {
          activeIndex--;
        }
        break;
    }
  }
}

class EQController {
  static const List<double> frequencies = [
    31.25,
    62.5,
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
    16000.0,
  ];

  static const Map<String, List<double>> presets = {
    'flat': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    'pop': [-1.5, -1.0, 0.0, 2.0, 4.0, 4.0, 2.0, 1.0, -1.0, -1.5],
    'rock': [4.0, 3.0, -2.0, -4.0, -1.0, 2.0, 4.0, 5.0, 5.0, 5.0],
    'bassBoost': [6.0, 5.0, 3.0, 1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  };

  Map<String, List<double>> userPresets = {};
  Map<String, List<double>> get allPresets => {...presets, ...userPresets};

  List<double> _gains = List.filled(10, 0.0);

  List<double> get gains => List.unmodifiable(_gains);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    final presetsString = _prefs!.getString('eq_user_presets');
    if (presetsString != null) {
      final Map<String, dynamic> decoded = jsonDecode(presetsString);
      userPresets = decoded.map((key, value) {
        return MapEntry(key, (value as List).map((e) => (e as num).toDouble()).toList());
      });
    }

    final gainsString = _prefs!.getString('eq_last_gains');
    if (gainsString != null) {
      final decodedGains = jsonDecode(gainsString) as List;
      _gains = decodedGains.map((e) => (e as num).toDouble()).toList();
    }
  }

  void saveUserPreset(String name) {
    userPresets[name] = List.from(_gains);
    _prefs?.setString('eq_user_presets', jsonEncode(userPresets));
  }

  void deleteUserPreset(String name) {
    userPresets.remove(name);
    _prefs?.setString('eq_user_presets', jsonEncode(userPresets));
  }

  void _saveGains() {
    _prefs?.setString('eq_last_gains', jsonEncode(_gains));
  }

  void setGain(int bandIndex, double gain) {
    if (bandIndex < 0 || bandIndex >= 10) return;
    _gains[bandIndex] = gain.clamp(-10.0, 10.0);
    _saveGains();
  }

  void applyPreset(String presetName) {
    final presetGains = allPresets[presetName];
    if (presetGains != null) {
      for (int i = 0; i < 10; i++) {
        _gains[i] = presetGains[i].clamp(-10.0, 10.0);
      }
      _saveGains();
    }
  }

  String get filterString {
    final List<String> bands = [];
    for (int i = 0; i < 10; i++) {
      final freq = frequencies[i];
      final freqStr = freq == freq.toInt() ? freq.toInt().toString() : freq.toString();
      final gainStr = _gains[i].toString();
      bands.add('equalizer=f=$freqStr:width_type=q:w=1:g=$gainStr');
    }
    return bands.join(',');
  }
}
