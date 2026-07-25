import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLayoutMode { classic, spotify, ytMusic, custom }

class LayoutManager extends ChangeNotifier {
  AppLayoutMode _currentMode = AppLayoutMode.classic;
  List<String> _customOrder = ['sidebar', 'main', 'sidepanel'];
  
  // Advanced Custom Layout States
  Map<String, bool> _panelVisibility = {
    'sidebar': true,
    'main': true,
    'sidepanel': true,
  };
  String _navStyle = 'sidebar'; // 'sidebar' or 'topBar'
  double _sidebarWidth = 200.0;
  double _sidePanelWidth = 300.0;

  SharedPreferences? _prefs;

  AppLayoutMode get currentMode => _currentMode;
  List<String> get customOrder => _customOrder;
  Map<String, bool> get panelVisibility => _panelVisibility;
  String get navStyle => _navStyle;
  double get sidebarWidth => _sidebarWidth;
  double get sidePanelWidth => _sidePanelWidth;

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

    _panelVisibility['sidebar'] = _prefs?.getBool('vis_sidebar') ?? true;
    _panelVisibility['main'] = _prefs?.getBool('vis_main') ?? true;
    _panelVisibility['sidepanel'] = _prefs?.getBool('vis_sidepanel') ?? true;
    
    _navStyle = _prefs?.getString('nav_style') ?? 'sidebar';
    _sidebarWidth = _prefs?.getDouble('sidebar_width') ?? 200.0;
    _sidePanelWidth = _prefs?.getDouble('sidepanel_width') ?? 300.0;

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

  void setPanelVisibility(String panel, bool visible) {
    _panelVisibility[panel] = visible;
    _prefs?.setBool('vis_$panel', visible);
    notifyListeners();
  }

  void setNavStyle(String style) {
    _navStyle = style;
    _prefs?.setString('nav_style', style);
    notifyListeners();
  }

  void updateSidebarWidth(double delta) {
    _sidebarWidth = (_sidebarWidth + delta).clamp(100.0, 400.0);
    _prefs?.setDouble('sidebar_width', _sidebarWidth);
    notifyListeners();
  }

  void updateSidePanelWidth(double delta) {
    _sidePanelWidth = (_sidePanelWidth + delta).clamp(150.0, 500.0);
    _prefs?.setDouble('sidepanel_width', _sidePanelWidth);
    notifyListeners();
  }
}
