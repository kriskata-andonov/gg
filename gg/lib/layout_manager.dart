import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLayoutMode { classic, spotify, ytMusic, custom }

class LayoutManager extends ChangeNotifier {
  AppLayoutMode _currentMode = AppLayoutMode.classic;
  SharedPreferences? _prefs;

  AppLayoutMode get currentMode => _currentMode;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final modeIndex = _prefs?.getInt('layout_mode') ?? 0;
    if (modeIndex >= 0 && modeIndex < AppLayoutMode.values.length) {
      _currentMode = AppLayoutMode.values[modeIndex];
    }
    notifyListeners();
  }

  void setMode(AppLayoutMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      _prefs?.setInt('layout_mode', mode.index);
      notifyListeners();
    }
  }
}
