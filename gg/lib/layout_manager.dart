import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLayoutMode { classic, spotify, ytMusic, custom }

class LayoutManager extends ChangeNotifier {
  AppLayoutMode _currentMode = AppLayoutMode.classic;
  List<String> _customOrder = ['sidebar', 'main', 'sidepanel'];
  SharedPreferences? _prefs;

  AppLayoutMode get currentMode => _currentMode;
  List<String> get customOrder => _customOrder;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final modeIndex = _prefs?.getInt('layout_mode') ?? 0;
    if (modeIndex >= 0 && modeIndex < AppLayoutMode.values.length) {
      _currentMode = AppLayoutMode.values[modeIndex];
    }
    final savedOrder = _prefs?.getStringList('custom_layout_order');
    if (savedOrder != null && savedOrder.length == 3) {
      _customOrder = savedOrder;
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

  void setCustomOrder(List<String> newOrder) {
    _customOrder = newOrder;
    _prefs?.setStringList('custom_layout_order', _customOrder);
    notifyListeners();
  }
}
