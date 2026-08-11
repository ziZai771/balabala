import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/app_config.dart';
import '../services/storage_service.dart';
import '../services/file_service.dart';

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final FileService _fileService = FileService();

  AppConfig _config = AppConfig();
  AppConfig get config => _config;

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  AppProvider() {
    loadConfig();
  }

  void loadConfig() {
    final saved = _storage.getAppConfig();
    if (saved != null) {
      _config = saved;
      _isDarkMode = saved.darkMode;
    }
    notifyListeners();
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await _storage.updateAppConfig(newConfig);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    _config.darkMode = value;
    await _storage.updateAppConfig(_config);
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _config.locale = locale;
    await _storage.updateAppConfig(_config);
    notifyListeners();
  }

  Future<void> setTtsAutoRead(bool value) async {
    _config.ttsAutoRead = value;
    await _storage.updateAppConfig(_config);
    notifyListeners();
  }

  Future<void> setTtsDefaultSpeed(double value) async {
    _config.ttsDefaultSpeed = value;
    await _storage.updateAppConfig(_config);
    notifyListeners();
  }

  // ===== 导出/导入配置 =====
  Future<String?> exportAllConfig() async {
    try {
      final data = await _storage.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final path = await _fileService.exportConfig(jsonStr);
      if (path != null) {
        _config.lastExportPath = path;
        await _storage.updateAppConfig(_config);
      }
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<bool> importAllConfig() async {
    try {
      final jsonStr = await _fileService.importConfig();
      if (jsonStr != null) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        await _storage.importAllData(data);
        // 重新加载所有数据
        loadConfig();
        notifyListeners();
        return true;
      }
    } catch (e) {
      // 处理错误
    }
    return false;
  }
}
