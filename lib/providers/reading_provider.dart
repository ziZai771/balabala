import 'package:flutter/material.dart';
import '../models/reading_config.dart';
import '../models/bookmark.dart';
import '../models/reading_history.dart';
import '../services/storage_service.dart';
import 'package:uuid/uuid.dart';

class ReadingProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final _uuid = const Uuid();

  ReadingConfig _config = ReadingConfig();
  ReadingConfig get config => _config;

  List<Bookmark> _bookmarks = [];
  List<Bookmark> get bookmarks => _bookmarks;

  bool _isBookmarked = false;
  bool get isBookmarked => _isBookmarked;

  ReadingProvider() {
    loadConfig();
  }

  void loadConfig() {
    final saved = _storage.getReadingConfig();
    if (saved != null) {
      _config = saved;
    }
    notifyListeners();
  }

  Future<void> updateConfig(ReadingConfig newConfig) async {
    _config = newConfig;
    await _storage.updateReadingConfig(newConfig);
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _config.fontSize = size;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  Future<void> setFontFamily(String family) async {
    _config.fontFamily = family;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  Future<void> setTheme(ReadingTheme theme) async {
    _config.theme = theme;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  Future<void> setAnimation(PageAnimation animation) async {
    _config.animation = animation;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  Future<void> setNightMode(bool value) async {
    _config.nightMode = value;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  Future<void> setBrightness(int value) async {
    _config.screenBrightness = value;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  Future<void> setScrollMode(bool value) async {
    _config.scrollMode = value;
    await _storage.updateReadingConfig(_config);
    notifyListeners();
  }

  // ===== 书签操作 =====
  void loadBookmarks(String bookId) {
    _bookmarks = _storage.getBookmarks(bookId);
    notifyListeners();
  }

  Future<void> addBookmark(String bookId, int position, String text) async {
    final bookmark = Bookmark(
      id: _uuid.v4(),
      bookId: bookId,
      position: position,
      text: text.length > 50 ? '${text.substring(0, 50)}...' : text,
    );
    await _storage.addBookmark(bookmark);
    _bookmarks.add(bookmark);
    _isBookmarked = true;
    notifyListeners();
  }

  Future<void> removeBookmark(String id) async {
    await _storage.deleteBookmark(id);
    _bookmarks.removeWhere((b) => b.id == id);
    _isBookmarked = _bookmarks.isNotEmpty;
    notifyListeners();
  }

  void checkBookmark(String bookId, int position) {
    _isBookmarked = _bookmarks.any((b) => b.position == position);
    notifyListeners();
  }

  // ===== 阅读历史 =====
  Future<void> addReadingHistory(String bookId, String bookTitle, int position, int duration) async {
    final history = ReadingHistory(
      id: _uuid.v4(),
      bookId: bookId,
      bookTitle: bookTitle,
      position: position,
      durationSeconds: duration,
    );
    await _storage.addHistory(history);
  }

  List<ReadingHistory> getHistory({int limit = 50}) {
    return _storage.getHistory(limit: limit);
  }
}
