import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/voice_profile.dart';
import '../models/reading_config.dart';
import '../models/bookmark.dart';
import '../models/app_config.dart';
import '../models/reading_history.dart';
import '../utils/chapter_number.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _booksKey = 'books';
  static const String _voicesKey = 'voices';
  static const String _readingConfigKey = 'reading_config';
  static const String _bookmarksKey = 'bookmarks';
  static const String _appConfigKey = 'app_config';
  static const String _historyKey = 'history';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ===== 书籍操作 =====
  List<Book> getAllBooks() {
    final data = _prefs.getString(_booksKey);
    debugPrint('StorageService.getAllBooks: key=$_booksKey data=${data != null ? "found (${data.length} chars)" : "null"}');
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      debugPrint('StorageService.getAllBooks: decoded ${list.length} items');
      final books = list.map((e) => Book.fromMap(e)).toList();
      // 在线阅读书籍的章节可能因旧数据而顺序混乱（目录页"最新章节"倒序区块混入正序目录）。
      // 加载时统一按章节号排序，保证目录始终正序，并同步修正当前章节索引。
      for (final book in books) {
        if (book.source == BookSource.url && book.chapters.length > 1) {
          _normalizeUrlBookChapters(book);
        }
      }
      return books;
    } catch (e) {
      debugPrint('StorageService.getAllBooks: JSON decode error: $e');
      return [];
    }
  }

  /// 对在线阅读书籍的章节按章节号排序（正序），并同步修正 currentChapter 索引。
  void _normalizeUrlBookChapters(Book book) {
    // 记录当前章节标题，用于排序后重新定位
    final currentTitle = book.currentChapter >= 0 && book.currentChapter < book.chapters.length
        ? book.chapters[book.currentChapter].title
        : null;

    sortChaptersByNumber(book.chapters);

    // 排序后重新生成 startIndex
    for (var i = 0; i < book.chapters.length; i++) {
      book.chapters[i] = Chapter(
        title: book.chapters[i].title,
        startIndex: i,
        url: book.chapters[i].url,
      );
    }

    // 根据当前章节标题重新定位索引
    if (currentTitle != null) {
      final newIndex = book.chapters.indexWhere((c) => c.title == currentTitle);
      if (newIndex >= 0) {
        book.currentChapter = newIndex;
      }
    }
  }

  List<Book> getBookshelfBooks() {
    return getAllBooks().where((b) => b.isInBookshelf).toList();
  }

  Book? getBook(String id) {
    final books = getAllBooks();
    try {
      return books.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addBook(Book book) async {
    final books = getAllBooks();
    books.add(book);
    await _saveBooks(books);
  }

  Future<void> updateBook(Book book) async {
    final books = getAllBooks();
    final index = books.indexWhere((b) => b.id == book.id);
    if (index != -1) {
      books[index] = book;
      await _saveBooks(books);
    }
  }

  Future<void> deleteBook(String id) async {
    final books = getAllBooks();
    books.removeWhere((b) => b.id == id);
    await _saveBooks(books);
  }

  Future<void> addToBookshelf(String id) async {
    final book = getBook(id);
    if (book != null) {
      book.isInBookshelf = true;
      await updateBook(book);
    }
  }

  Future<void> removeFromBookshelf(String id) async {
    final book = getBook(id);
    if (book != null) {
      book.isInBookshelf = false;
      await updateBook(book);
    }
  }

  Future<void> _saveBooks(List<Book> books) async {
    final data = jsonEncode(books.map((b) => b.toMap()).toList());
    await _prefs.setString(_booksKey, data);
  }

  // ===== 音色操作 =====
  List<VoiceProfile> getAllVoices() {
    final data = _prefs.getString(_voicesKey);
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((e) => VoiceProfile.fromMap(e)).toList();
  }

  VoiceProfile? getVoice(String id) {
    final voices = getAllVoices();
    try {
      return voices.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  VoiceProfile? getDefaultVoice() {
    final voices = getAllVoices();
    try {
      return voices.firstWhere((v) => v.isDefault);
    } catch (_) {
      return voices.isNotEmpty ? voices.first : null;
    }
  }

  Future<void> addVoice(VoiceProfile voice) async {
    final voices = getAllVoices();
    voices.add(voice);
    await _saveVoices(voices);
  }

  Future<void> updateVoice(VoiceProfile voice) async {
    final voices = getAllVoices();
    final index = voices.indexWhere((v) => v.id == voice.id);
    if (index != -1) {
      voices[index] = voice;
      await _saveVoices(voices);
    }
  }

  Future<void> deleteVoice(String id) async {
    final voices = getAllVoices();
    voices.removeWhere((v) => v.id == id);
    await _saveVoices(voices);
  }

  Future<void> setDefaultVoice(String id) async {
    final voices = getAllVoices();
    for (var voice in voices) {
      voice.isDefault = voice.id == id;
    }
    await _saveVoices(voices);
  }

  Future<void> _saveVoices(List<VoiceProfile> voices) async {
    final data = jsonEncode(voices.map((v) => v.toMap()).toList());
    await _prefs.setString(_voicesKey, data);
  }

  // ===== 阅读配置 =====
  ReadingConfig? getReadingConfig() {
    final data = _prefs.getString(_readingConfigKey);
    if (data == null) return null;
    return ReadingConfig.fromMap(jsonDecode(data));
  }

  Future<void> updateReadingConfig(ReadingConfig config) async {
    await _prefs.setString(_readingConfigKey, jsonEncode(config.toMap()));
  }

  // ===== 书签操作 =====
  List<Bookmark> getBookmarks(String bookId) {
    final data = _prefs.getString(_bookmarksKey);
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((e) => Bookmark.fromMap(e))
        .where((b) => b.bookId == bookId).toList();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final data = _prefs.getString(_bookmarksKey);
    final list = data != null ? jsonDecode(data) as List : [];
    list.add(bookmark.toMap());
    await _prefs.setString(_bookmarksKey, jsonEncode(list));
  }

  Future<void> deleteBookmark(String id) async {
    final data = _prefs.getString(_bookmarksKey);
    if (data == null) return;
    final list = (jsonDecode(data) as List).where((e) => e['id'] != id).toList();
    await _prefs.setString(_bookmarksKey, jsonEncode(list));
  }

  // ===== 应用配置 =====
  AppConfig? getAppConfig() {
    final data = _prefs.getString(_appConfigKey);
    if (data == null) return null;
    return AppConfig.fromMap(jsonDecode(data));
  }

  Future<void> updateAppConfig(AppConfig config) async {
    await _prefs.setString(_appConfigKey, jsonEncode(config.toMap()));
  }

  // ===== 阅读历史 =====
  List<ReadingHistory> getHistory({int limit = 50}) {
    final data = _prefs.getString(_historyKey);
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    final all = list.map((e) => ReadingHistory.fromMap(e)).toList();
    all.sort((a, b) => b.readAt.compareTo(a.readAt));
    return all.take(limit).toList();
  }

  Future<void> addHistory(ReadingHistory history) async {
    final data = _prefs.getString(_historyKey);
    final list = data != null ? jsonDecode(data) as List : [];
    list.add(history.toMap());
    await _prefs.setString(_historyKey, jsonEncode(list));
  }

  // ===== 导出/导入 =====
  Future<Map<String, dynamic>> exportAllData() async {
    return {
      'books': getAllBooks().map((b) => b.toMap()).toList(),
      'voices': getAllVoices().map((v) => v.toMap()).toList(),
      'readingConfig': getReadingConfig()?.toMap(),
      'bookmarks': _prefs.getString(_bookmarksKey) != null
          ? (jsonDecode(_prefs.getString(_bookmarksKey)!) as List)
          : [],
      'appConfig': getAppConfig()?.toMap(),
      'exportVersion': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> importAllData(Map<String, dynamic> data) async {
    if (data['books'] != null) {
      final existingBooks = getAllBooks();
      for (var bookData in data['books'] as List) {
        final book = Book.fromMap(bookData);
        if (!existingBooks.any((b) => b.id == book.id)) {
          existingBooks.add(book);
        }
      }
      await _saveBooks(existingBooks);
    }
    if (data['voices'] != null) {
      final existingVoices = getAllVoices();
      for (var voiceData in data['voices'] as List) {
        final voice = VoiceProfile.fromMap(voiceData);
        if (!existingVoices.any((v) => v.id == voice.id)) {
          existingVoices.add(voice);
        }
      }
      await _saveVoices(existingVoices);
    }
    if (data['bookmarks'] != null) {
      final existingBookmarks = _prefs.getString(_bookmarksKey);
      var list = existingBookmarks != null ? jsonDecode(existingBookmarks) as List : [];
      for (var bmData in data['bookmarks'] as List) {
        if (!list.any((e) => e['id'] == bmData['id'])) {
          list.add(bmData);
        }
      }
      await _prefs.setString(_bookmarksKey, jsonEncode(list));
    }
  }
}
