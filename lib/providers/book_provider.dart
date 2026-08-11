import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../services/storage_service.dart';
import '../services/file_service.dart';
import '../services/readability_service.dart';
import '../services/chapter_service.dart';
import '../services/http_util.dart';

class BookProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final FileService _fileService = FileService();
  final ReadabilityService _readabilityService = ReadabilityService();
  final _uuid = const Uuid();

  List<Book> _books = [];
  List<Book> get books => _books;
  
  List<Book> get bookshelfBooks => _books.where((b) => b.isInBookshelf).toList();
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Book? _currentBook;
  Book? get currentBook => _currentBook;

  BookProvider() {
    loadBooks();
  }

  void loadBooks() {
    _books = _storage.getAllBooks();
    debugPrint('BookProvider.loadBooks: loaded ${_books.length} books');
    for (var b in _books) {
      debugPrint('  book: id=${b.id} title=${b.title} isInBookshelf=${b.isInBookshelf} contentLen=${b.content.length}');
    }
    notifyListeners();
  }

  Future<Book?> pickAndAddBook() async {
    _isLoading = true;
    notifyListeners();

    try {
      final book = await _fileService.pickTextFile();
      if (book != null) {
        book.isInBookshelf = true;
        await _storage.addBook(book);
        _books.add(book);
        _isLoading = false;
        notifyListeners();
        return book;
      }
    } catch (e) {
      // 处理错误
    }
    
    _isLoading = false;
    notifyListeners();
    return null;
  }

  Future<Book?> addUrlBook(String url) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 先尝试直接读取文本
      final book = await _fileService.fetchUrlContent(url);
      if (book != null) {
        book.isInBookshelf = true;
        await _storage.addBook(book);
        _books.add(book);
        _isLoading = false;
        notifyListeners();
        return book;
      }

      // 直接读取失败（HTML 页面），走在线阅读路径：
      // 1) 提取当前章节正文（用户输入的是章节页）
      // 2) 若正文提取失败或过短（用户输入的是书籍首页/目录页），
      //    把当前页当作目录页直接提取整本书章节列表。
      debugPrint('addUrlBook: extractFromUrl start: $url');
      final result = await _readabilityService.extractFromUrl(url);
      debugPrint('addUrlBook: extractFromUrl done, result=${result != null}, contentLen=${result?.content.length ?? 0}');

      // 正文质量校验：过短的正文视为垃圾内容（JS 加载站、反爬页、广告页等）
      const minContentLength = 200;
      final validContent = result != null && result.content.trim().length >= minContentLength;

      // 尝试构建整本书（目录 + 章节列表）。无论正文是否有效都要尝试，
      // 因为用户可能直接输入了目录页 URL。
      List<Chapter> tocChapters = [];
      String bookTitle = '';
      final validResult = validContent ? result : null;
      if (validResult != null) {
        bookTitle = validResult.title;
      }

      // 第一步：若当前页是章节页，尝试找"目录页"链接
      try {
        final response = await HttpUtil.get(url);
        debugPrint('addUrlBook: chapter page status=${response.statusCode}');
        if (response.statusCode == 200) {
          final tocUrl = _readabilityService.findTocUrl(HttpUtil.decodeBody(response), url);
          debugPrint('addUrlBook: findTocUrl -> $tocUrl');
          if (tocUrl != null) {
            tocChapters = await _readabilityService.extractToc(tocUrl);
            debugPrint('addUrlBook: extractToc(tocUrl) -> ${tocChapters.length} chapters');
            final extractedTitle = await _readabilityService.extractBookTitle(tocUrl);
            if (extractedTitle != null && extractedTitle.isNotEmpty) {
              bookTitle = extractedTitle;
            }
          }
        }
      } catch (e) {
        debugPrint('addUrlBook: toc extraction error: $e');
      }

      // 第二步：若还没拿到目录（当前页可能直接就是目录页），
      // 把当前 URL 当作目录页提取。
      if (tocChapters.isEmpty) {
        try {
          final directToc = await _readabilityService.extractToc(url);
          debugPrint('addUrlBook: extractToc(direct) -> ${directToc.length} chapters');
          if (directToc.length >= 5) {
            tocChapters = directToc;
            final extractedTitle = await _readabilityService.extractBookTitle(url);
            if (extractedTitle != null && extractedTitle.isNotEmpty) {
              bookTitle = extractedTitle;
            }
          }
        } catch (e) {
          debugPrint('addUrlBook: direct toc extraction error: $e');
        }
      }

      // 正文无效且没有目录 → 无法导入
      if (!validContent && tocChapters.isEmpty) {
        debugPrint('addUrlBook: rejected (no valid content, no toc)');
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final newBook = Book(
        id: _uuid.v4(),
        title: bookTitle,
        url: url,
        source: BookSource.url,
        content: validContent ? validResult!.content : '',
        totalLength: validContent ? validResult!.content.length : 0,
        isInBookshelf: true,
        chapterCount: tocChapters.isNotEmpty ? tocChapters.length : (validContent ? 1 : 0),
        chapters: tocChapters,
      );
      // 定位到当前正在阅读的章节（忽略 http/https 协议差异）
      if (tocChapters.isNotEmpty) {
        final normUrl = url.replaceFirst(RegExp(r'^https?://'), '');
        final currentIndex = tocChapters.indexWhere(
            (c) => (c.url ?? '').replaceFirst(RegExp(r'^https?://'), '') == normUrl);
        if (currentIndex >= 0) {
          newBook.currentChapter = currentIndex;
        }
      }
      await _storage.addBook(newBook);
      _books.add(newBook);
      _isLoading = false;
      notifyListeners();
      return newBook;
    } catch (e) {
      debugPrint('addUrlBook: error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  Future<void> addToBookshelf(String bookId) async {
    await _storage.addToBookshelf(bookId);
    final book = _books.firstWhere((b) => b.id == bookId);
    book.isInBookshelf = true;
    notifyListeners();
  }

  Future<void> removeFromBookshelf(String bookId) async {
    await _storage.removeFromBookshelf(bookId);
    final book = _books.firstWhere((b) => b.id == bookId);
    book.isInBookshelf = false;
    notifyListeners();
  }

  Future<void> deleteBook(String bookId) async {
    await _storage.deleteBook(bookId);
    _books.removeWhere((b) => b.id == bookId);
    notifyListeners();
  }

  void setCurrentBook(Book book) {
    _currentBook = book;
    notifyListeners();
  }

  Future<void> updateReadingProgress(String bookId, int position) async {
    final book = _books.firstWhere((b) => b.id == bookId);
    book.currentPosition = position;
    book.lastReadAt = DateTime.now();
    await _storage.updateBook(book);
    notifyListeners();
  }

  /// 更新书籍信息并持久化
  Future<void> updateBook(Book book) async {
    await _storage.updateBook(book);
    notifyListeners();
  }

  Book? getBookById(String id) {
    try {
      return _books.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 从粘贴的文本创建书籍
  Future<Book?> addPastedText(String text) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 从文本前几行提取标题
      String title = _extractTitleFromText(text);
      final chapters = ChapterService().parseChapters(text);
      final book = Book(
        id: _uuid.v4(),
        title: title,
        source: BookSource.local,
        content: text,
        totalLength: text.length,
        isInBookshelf: true,
        chapterCount: chapters.length,
        chapters: chapters,
      );
      await _storage.addBook(book);
      _books.add(book);
      _isLoading = false;
      notifyListeners();
      return book;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// 从文本内容提取标题
  String _extractTitleFromText(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && trimmed.length < 100) {
        if (!trimmed.contains('。') &&
            !trimmed.contains('，') &&
            !trimmed.contains('？') &&
            !trimmed.contains('！')) {
          return trimmed;
        }
      }
    }
    // 取前20个字符作为标题
    final preview = text.trim();
    if (preview.length > 20) {
      return '${preview.substring(0, 20)}...';
    }
    return preview;
  }

  /// 检查URL是否已添加
  bool isUrlAdded(String url) {
    return _books.any((b) => b.url == url);
  }
}
