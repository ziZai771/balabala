import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/reading_config.dart';
import '../models/voice_profile.dart';
import '../providers/book_provider.dart';
import '../providers/app_provider.dart';
import '../providers/reading_provider.dart';
import '../providers/voice_provider.dart';
import '../services/tts_service.dart';
import '../services/chapter_service.dart';
import '../services/readability_service.dart';
import '../core/theme.dart';
import '../widgets/reader_settings_sheet.dart';
import '../widgets/tts_control_bar.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late PageController _pageController;
  late AnimationController _uiAnimationController;
  bool _showUI = true;
  int _currentCharIndex = 0;
  // 否则 UI 显示/隐藏两种布局的页首位置错位，每次 toggle 锚点逐次前移
  bool _suppressPageCharSync = false;
  String _displayText = '';
  List<String> _pages = [];
  int _currentPage = 0;
  bool _isTtsPlaying = false;
  StreamSubscription? _ttsPageCompleteSub;

  List<int> _pageStartPara = [];
  List<int> _pageStartChar = [];
  List<int> _chapterPageStart = [];
  double _pageViewportHeight = 0;
double _lastBuildUsableH = 0;
// 分割调度去重（延迟分割防抖）
bool _splitScheduled = false;

  // TTS 段落高亮
  List<String> _paragraphs = [];
  int _currentTtsParagraph = -1;
  List<String> _ttsLines = [];
  List<GlobalKey> _paragraphKeys = [];
  List<double> _paragraphHeights = [];
  List<int> _paragraphOffsets = [];

  bool _initialized = false;
  bool _isLoading = true;
  String _emptyMessage = '';
  final _readabilityService = ReadabilityService();
  double _scrollProgress = 0.0;
  // 滚动模式下当前可见的段落索引（用于计算进度）
  int _currentVisibleParagraph = 0;

  // 加载序号：防止连续章节跳转时多个 _loadChapterWindow/_loadLocalChapterWindow
  int _loadSeq = 0;
  int _splitSeq = 0;
  Offset? _pointerDownPos;

  // ===== 在线阅读章节窗口缓存 =====
  List<int> _windowChapters = [];
  final Map<int, String> _chapterCache = {};
  List<int> _chapterParaStart = [];
  int _windowStartFullOffset = 0;
  static const int _preloadCount = 2;
  bool _extendingWindow = false;
  String? _jumpLogPath;

  void _logJump(String msg) {
    final path = _jumpLogPath;
    if (path == null) return;
    try {
      final f = File(path);
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $msg\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _initJumpLog() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _jumpLogPath = '${dir.path}/jump_log.txt';
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _initJumpLog();
    _scrollController = ScrollController();
    _pageController = PageController(initialPage: 0);
    _uiAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    final book = widget.book;
    _currentCharIndex = book.currentPosition;
    _displayText = book.content;

    // 滚动模式下监听滚动位置，更新阅读进度
    _scrollController.addListener(_onScrollChanged);

    _ttsPageCompleteSub = TtsService().pageCompleteStream.listen((_) {
      if (!mounted) return;
      _onTtsPageComplete();
    });
  }

  /// _currentVisibleParagraph 只在 itemBuilder 中单调递增（index > 当前值才更新），
  int _paragraphIndexAtOffset(double offset) {
    if (_paragraphs.isEmpty) return 0;
    if (_paragraphHeights.length == _paragraphs.length) {
      double acc = 0;
      for (int i = 0; i < _paragraphs.length; i++) {
        acc += _paragraphHeights[i] + 12;
        if (offset < acc) return i;
      }
      return _paragraphs.length - 1;
    }
    final ratio = (offset / _scrollController.position.maxScrollExtent).clamp(0.0, 1.0);
    return (ratio * _paragraphs.length).floor().clamp(0, _paragraphs.length - 1);
  }

  (int, int) _currentChapterWindowRange() {
    if (_windowChapters.isEmpty || _chapterParaStart.isEmpty) {
      return (0, _displayText.length);
    }
    final pos = _windowChapters.indexOf(widget.book.currentChapter);
    if (pos < 0 || pos >= _chapterParaStart.length) {
      return (0, _displayText.length);
    }
    final startPara = _chapterParaStart[pos];
    final start = startPara < _paragraphOffsets.length
        ? _paragraphOffsets[startPara]
        : 0;
    int end = _displayText.length;
    if (pos + 1 < _chapterParaStart.length) {
      final nextStartPara = _chapterParaStart[pos + 1];
      if (nextStartPara < _paragraphOffsets.length) {
        end = _paragraphOffsets[nextStartPara];
      }
    }
    return (start, end);
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    if (_paragraphs.isEmpty) return;
    final visible = _paragraphIndexAtOffset(_scrollController.offset);
    // 精确到视口顶部的字符位置：段落起点 + 段内偏移（按像素比例估算）。
    // 此前用"段落比例 × 全文长度"映射，大段落（数千字）时视口停在段落中部，
    // 朗读却从段落开头（视口上方）开始，表现为"滑下去了朗读还是从上面开始"。
    int newIndex;
    if (_paragraphOffsets.length == _paragraphs.length &&
        _paragraphHeights.length == _paragraphs.length) {
      double paraTopPx = 0;
      for (int i = 0; i < visible; i++) {
        paraTopPx += _paragraphHeights[i] + 12;
      }
      final offsetInPara =
          (_scrollController.offset - paraTopPx).clamp(0.0, _paragraphHeights[visible]);
      final frac =
          _paragraphHeights[visible] > 0 ? offsetInPara / _paragraphHeights[visible] : 0.0;
      newIndex = _paragraphOffsets[visible] +
          (_paragraphs[visible].length * frac).round();
      newIndex = newIndex.clamp(0, _displayText.length);
    } else {
      newIndex = ((visible / _paragraphs.length).clamp(0.0, 1.0) * _displayText.length).round();
    }
    final (chStart, chEnd) = _currentChapterWindowRange();
    final chLen = chEnd - chStart;
    final progress = chLen > 0
        ? ((newIndex - chStart) / chLen).clamp(0.0, 1.0)
        : 0.0;
    final progressChanged = (progress - _scrollProgress).abs() > 0.002;
    final indexChanged = (newIndex - _currentCharIndex).abs() > _displayText.length * 0.005;
    if (progressChanged || indexChanged) {
      _scrollProgress = progress;
      _currentCharIndex = newIndex;
      _currentVisibleParagraph = visible;
      if (mounted) setState(() {});
    }

    // 滚动到窗口末尾时向前扩展窗口（预加载下一批章节并拼接），
    if (!_extendingWindow &&
        widget.book.chapters.isNotEmpty &&
        _paragraphs.isNotEmpty) {
      final visible = _paragraphIndexAtOffset(_scrollController.offset);
      if (visible >= _paragraphs.length - 1) {
        debugPrint('_onScrollChanged: extendForward trigger visible=$visible '
            'total=$_paragraphs.length window=$_windowChapters');
        if (widget.book.source == BookSource.url) {
          _extendWindowForward();
        } else {
          _extendLocalWindowForward();
        }
      } else if (visible <= 0) {
        debugPrint('_onScrollChanged: extendBackward trigger visible=$visible '
            'total=$_paragraphs.length window=$_windowChapters');
        if (widget.book.source == BookSource.url) {
          _extendWindowBackward();
        } else {
          _extendLocalWindowBackward();
        }
      }
    }

    if (widget.book.chapters.isNotEmpty &&
        _windowChapters.isNotEmpty &&
        _chapterParaStart.isNotEmpty) {
      final visible = _paragraphIndexAtOffset(_scrollController.offset);
      final chapterIndex = _chapterIndexAtParagraph(visible);
      if (chapterIndex >= 0 && chapterIndex != widget.book.currentChapter) {
        debugPrint('_onScrollChanged: syncChapter $chapterIndex '
            '(was ${widget.book.currentChapter}) visible=$visible');
        widget.book.currentChapter = chapterIndex;
        Provider.of<BookProvider>(context, listen: false).updateBook(widget.book);
      }
    }
  }

  int _chapterIndexAtParagraph(int paraIndex) {
    if (_windowChapters.isEmpty || _chapterParaStart.isEmpty) return -1;
    int chapterPos = 0;
    for (var i = 0; i < _chapterParaStart.length; i++) {
      if (paraIndex >= _chapterParaStart[i]) {
        chapterPos = i;
      } else {
        break;
      }
    }
    return _windowChapters[chapterPos];
  }

  List<String> _pageTtsLines() {
    List<String> splitLines(String text) => text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        // 过滤纯省略号/装饰分隔行（如 "……"、"……"、"——"），避免朗读怪声/停顿
        .where((l) => !RegExp(r'^[…\.\-\—=~*☆★\s]{2,}$').hasMatch(l))
        .toList();
    if (Provider.of<ReadingProvider>(context, listen: false).config.scrollMode) {
      if (_displayText.isEmpty) return [];
      final start = _currentCharIndex.clamp(0, _displayText.length - 1);
      final end = (start + 2000).clamp(start, _displayText.length);
      return splitLines(_displayText.substring(start, end));
    }
    return splitLines(_getCurrentPageText());
  }

  void _speakTtsLine(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= _ttsLines.length) return;
    setState(() => _currentTtsParagraph = lineIndex);
    TtsService().speak(_applyBlockedWords(_ttsLines[lineIndex]),
        startPosition: 0);
    // 滑动窗口预合成：播放 n 时预取 n+5（跳过省略号等无效隔行的影响）
    final target = lineIndex + 5;
    if (target < _ttsLines.length) {
      TtsService().prefetch(_applyBlockedWords(_ttsLines[target]));
    }
  }

  void _onTtsPageComplete() {
    if (_ttsLines.isNotEmpty && _currentTtsParagraph < _ttsLines.length - 1) {
      _speakTtsLine(_currentTtsParagraph + 1);
      return;
    }
    // 当前批读完了
    _ttsLines = [];
    _currentTtsParagraph = -1;
    final isScroll = Provider.of<ReadingProvider>(context, listen: false)
        .config
        .scrollMode;
    if (isScroll) {
      final next = _currentCharIndex + 2000;
      if (next < _displayText.length) {
        _currentCharIndex = next;
        _ttsLines = _pageTtsLines();
        if (_ttsLines.isNotEmpty) {
          // 滚动跟随：新一批朗读文本来自更靠后的字符位置，把列表滚动过去，
          _scrollToCharIndex(_currentCharIndex);
          _speakTtsLine(0);
        } else {
          _stopTts();
        }
      } else {
        _stopTts();
      }
      return;
    }
    if (_currentPage < _pages.length - 1) {
      _nextPage();
      _ttsLines = _pageTtsLines();
      if (_ttsLines.isNotEmpty) {
        _speakTtsLine(0);
      } else {
        _stopTts();
      }
    } else {
      _stopTts();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initReader();
      });
    }
  }

  void _initReader() {
    final book = widget.book;
    // 兼容旧数据：若书籍未解析过章节，则从内容重新解析并持久化
    if (book.chapters.isEmpty && book.content.isNotEmpty) {
      final chapters = ChapterService().parseChapters(book.content);
      if (chapters.isNotEmpty) {
        book.chapters = chapters;
        book.chapterCount = chapters.length;
        Provider.of<BookProvider>(context, listen: false).updateBook(book);
      }
    }
    Provider.of<BookProvider>(context, listen: false).setCurrentBook(book);
    Provider.of<ReadingProvider>(context, listen: false).loadBookmarks(book.id);

    if (book.source == BookSource.url && book.chapters.isNotEmpty) {
      _loadChapterWindow(book.currentChapter);
    } else if (book.source == BookSource.local && book.chapters.isNotEmpty) {
      // 而非一次性分页整本书。整本书分页会把 16M+ 字符切成数万页，占满堆内存，
      final chapterIndex = ChapterService().findChapterIndex(book.chapters, book.currentPosition);
      _loadLocalChapterWindow(chapterIndex);
    } else {
      if (book.source == BookSource.url && book.content.isEmpty) {
        _windowChapters = [];
        _windowStartFullOffset = 0;
        setState(() {
          _isLoading = false;
          _emptyMessage = '无法加载该书内容';
        });
        return;
      }
      _windowChapters = [];
      _windowStartFullOffset = 0;
      _splitPages();
    }
    Provider.of<ReadingProvider>(context, listen: false).addListener(_onConfigChanged);
  }

  Future<void> _loadChapterWindow(int centerIndex, {int? seekFullOffset}) async {
    final book = widget.book;
    if (centerIndex < 0 || centerIndex >= book.chapters.length) return;

    final seq = ++_loadSeq;
    debugPrint('_loadChapterWindow: seq=$seq center=$centerIndex '
        'totalChapters=${book.chapters.length} '
        'currentChapter=${book.currentChapter} currentPosition=${book.currentPosition}');
    if (mounted) setState(() => _isLoading = true);

    final start = (centerIndex - _preloadCount).clamp(0, book.chapters.length - 1);
    final end = (centerIndex + _preloadCount).clamp(0, book.chapters.length - 1);

    final indices = <int>[];
    for (var i = start; i <= end; i++) {
      if (!_chapterCache.containsKey(i)) indices.add(i);
    }
    if (indices.isNotEmpty) {
      await Future.wait(indices.map((i) => _fetchChapterText(i)));
    }

    if (!mounted) return;
    if (seq != _loadSeq) return;

    var buffer = StringBuffer();
    final windowChapters = <int>[];
    for (var i = start; i <= end; i++) {
      final text = _chapterCache[i];
      if (text == null || text.isEmpty) continue;
      windowChapters.add(i);
      buffer.write(text.trimRight());
      buffer.write('\n\n');
    }

    if (!windowChapters.contains(centerIndex)) {
      await _fetchChapterText(centerIndex);
      if (!mounted || seq != _loadSeq) return;
      final retryText = _chapterCache[centerIndex];
      if (retryText == null || retryText.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      windowChapters.clear();
      final buffer2 = StringBuffer();
      for (var i = start; i <= end; i++) {
        final text = _chapterCache[i];
        if (text == null || text.isEmpty) continue;
        windowChapters.add(i);
        buffer2.write(text);
        buffer2.write('\n\n');
      }
      if (!windowChapters.contains(centerIndex)) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      buffer = buffer2;
    }

    final chapterText = buffer.toString();
    final currentChapter = book.chapters[centerIndex];
    final wasTargetChapter = book.currentChapter == centerIndex;
    final restorePos = wasTargetChapter ? book.currentPosition : 0;

    setState(() {
      _displayText = chapterText;
      _windowChapters = windowChapters;
      _currentCharIndex = 0;
      _currentPage = 0;
      _currentVisibleParagraph = 0;
      book.currentChapter = centerIndex;
      book.url = currentChapter.url ?? '';
      book.content = chapterText;
      book.totalLength = chapterText.length;
    });

    await _splitPages(jumpAfterSplit: false);

    if (seq != _loadSeq || !mounted) return;

    int? seekInWindow;
    if (seekFullOffset != null && book.chapters.isNotEmpty) {
      final chRatio = centerIndex / book.chapters.length;
      final chStart = _chapterStartChar(centerIndex);
      final posInWindow = _windowChapters.indexOf(centerIndex);
      final nextGlobal = posInWindow >= 0 && posInWindow + 1 < _windowChapters.length
          ? _windowChapters[posInWindow + 1]
          : null;
      final chEnd = nextGlobal != null
          ? _chapterStartChar(nextGlobal)
          : chapterText.length;
      final chLen = (chEnd - chStart).clamp(0, chapterText.length - chStart);
      final inChapter = (seekFullOffset / book.totalLength - chRatio)
          .clamp(0.0, 1.0);
      seekInWindow = (chStart + inChapter * chLen).round().clamp(0, chapterText.length);
    }

    if (_windowChapters.isNotEmpty) {
      final chapterStart = _chapterStartChar(centerIndex);
      final target = seekInWindow ?? (chapterStart + restorePos);
      if (target < _displayText.length) {
        _currentCharIndex = target;
        if (mounted) {
          final cfg = Provider.of<ReadingProvider>(context, listen: false).config;
          if (cfg.scrollMode) {
            _scrollToCharIndex(target);
          } else {
            int? targetPage;
            // 跳转章节（非当前章恢复进度）时用段落级锚点定位到章节首页
            if (seekFullOffset == null && !wasTargetChapter) {
              final pos = _windowChapters.indexOf(centerIndex);
              if (pos >= 0 && pos < _chapterParaStart.length &&
                  _chapterParaStart[pos] < _paragraphs.length) {
                targetPage = _pageIndexForPara(_chapterParaStart[pos]);
              }
            }
            _currentPage = targetPage ?? _pageIndexForChar(target);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentPage);
            }
          }
        }
      }
    }

    if (mounted) {
      Provider.of<BookProvider>(context, listen: false).updateBook(book);
      if (!wasTargetChapter) {
        _saveProgress();
      }
    }
  }

  Future<void> _fetchChapterText(int chapterIndex) async {
    if (_chapterCache.containsKey(chapterIndex)) return;
    final book = widget.book;
    if (chapterIndex < 0 || chapterIndex >= book.chapters.length) return;
    final chapter = book.chapters[chapterIndex];
    final chapterUrl = chapter.url;
    if (chapterUrl == null || chapterUrl.isEmpty) return;

    try {
      final result = await _readabilityService.extractFromUrl(chapterUrl);
      if (result == null || result.content.isEmpty) return;
      _chapterCache[chapterIndex] = '${chapter.title}\n\n${result.content}';
    } catch (_) {
      // 网络失败：不缓存，下次可重试
    }
  }

  int _localChapterEnd(int chapterIndex) {
    final book = widget.book;
    if (book.chapters.isEmpty) return book.content.length;
    if (chapterIndex >= book.chapters.length - 1) return book.content.length;
    return book.chapters[chapterIndex + 1].startIndex;
  }

  ///   - [seekFullOffset] 不为 null 时跳到该全文偏移（进度条拖拽，可能是章节中间）；
  Future<void> _loadLocalChapterWindow(int centerIndex,
      {bool restorePosition = true, int? seekFullOffset}) async {
    final book = widget.book;
    if (book.chapters.isEmpty) {
      _windowChapters = [];
      _windowStartFullOffset = 0;
      _displayText = book.content;
      await _splitPages();
      return;
    }
    if (centerIndex < 0 || centerIndex >= book.chapters.length) return;

    // 本次加载序号：若加载期间又有新的加载请求（_loadSeq 变大），
    final seq = ++_loadSeq;
    debugPrint('_loadLocalChapterWindow: seq=$seq center=$centerIndex restore=$restorePosition');

    final start = (centerIndex - _preloadCount).clamp(0, book.chapters.length - 1);
    final end = (centerIndex + _preloadCount).clamp(0, book.chapters.length - 1);

    final windowChapters = <int>[];
    final buffer = StringBuffer();
    for (var i = start; i <= end; i++) {
      final chStart = book.chapters[i].startIndex;
      final chEnd = _localChapterEnd(i);
      if (chEnd <= chStart) continue;
      final text = book.content.substring(chStart, chEnd);
      windowChapters.add(i);
      _chapterCache[i] = text;
      buffer.write(text.trimRight());
      buffer.write('\n\n');
    }

    if (windowChapters.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final chapterText = buffer.toString();
    final windowStartFullOffset = book.chapters[start].startIndex;
    final fullPos = restorePosition
        ? book.currentPosition
        : (seekFullOffset ?? book.chapters[centerIndex].startIndex);
    final slicePos = (fullPos - windowStartFullOffset).clamp(0, chapterText.length);

    setState(() {
      _displayText = chapterText;
      _windowChapters = windowChapters;
      _windowStartFullOffset = windowStartFullOffset;
      _currentCharIndex = slicePos;
      _currentPage = 0;
      _currentVisibleParagraph = 0;
      book.currentChapter = centerIndex;
    });

    await _splitPages(jumpAfterSplit: false);

    // 加载期间有更新的加载请求（用户又跳转了），丢弃本次过期结果，
    if (seq != _loadSeq || !mounted) return;

    // 1) 窗口拼接时每章间加了 '\n\n' 分隔符，字符偏移（全文偏移相减）不含分隔符，
    if (_currentCharIndex < _displayText.length) {
      if (mounted) {
        final cfg = Provider.of<ReadingProvider>(context, listen: false).config;
        if (!restorePosition && seekFullOffset == null) {
          final pos = _windowChapters.indexOf(centerIndex);
          final useChapterAnchor =
              pos >= 0 && pos < _chapterParaStart.length && _chapterParaStart[pos] < _paragraphs.length;
          final anchorChar = useChapterAnchor
              ? _paragraphOffsets[_chapterParaStart[pos]]
              : _currentCharIndex;
          _currentCharIndex = anchorChar;
          if (cfg.scrollMode) {
            _scrollToCharIndex(anchorChar);
          } else {
            final targetPage = useChapterAnchor
                ? _pageIndexForPara(_chapterParaStart[pos])
                : _pageIndexForChar(anchorChar);
            _currentPage = targetPage;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentPage);
            }
          }
        } else if (cfg.scrollMode) {
          _scrollToCharIndex(_currentCharIndex);
        } else {
          _currentPage = _pageIndexForChar(_currentCharIndex);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPage);
          }
        }
      }
    }

    if (mounted) {
      Provider.of<BookProvider>(context, listen: false).updateBook(book);
      if (!restorePosition) {
        _saveProgress();
      }
    }
  }

  Future<bool> _extendLocalWindowForward() async {
    if (_extendingWindow) return false;
    final book = widget.book;
    if (book.source != BookSource.local || book.chapters.isEmpty) return false;
    if (_windowChapters.isEmpty) return false;

    final lastIndex = _windowChapters.last;
    if (lastIndex >= book.chapters.length - 1) return false; // 已是最后一章

    _extendingWindow = true;
    try {
      final added = <int>[];
      final buffer = StringBuffer(_displayText);
      for (var i = 1; i <= _preloadCount; i++) {
        final idx = lastIndex + i;
        if (idx >= book.chapters.length) break;
        final chStart = book.chapters[idx].startIndex;
        final chEnd = _localChapterEnd(idx);
        if (chEnd <= chStart) continue;
        final text = book.content.substring(chStart, chEnd);
        added.add(idx);
        _chapterCache[idx] = text;
        buffer.write(text);
        buffer.write('\n\n');
      }

      if (added.isEmpty) return false;
      if (!mounted) return false;

      setState(() {
        _displayText = buffer.toString();
        _windowChapters = [..._windowChapters, ...added];
      });
      await _splitPages();
      return true;
    } finally {
      _extendingWindow = false;
    }
  }

  Future<bool> _extendLocalWindowBackward() async {
    if (_extendingWindow) return false;
    final book = widget.book;
    if (book.source != BookSource.local || book.chapters.isEmpty) return false;
    if (_windowChapters.isEmpty) return false;

    final firstIndex = _windowChapters.first;
    if (firstIndex <= 0) return false; // 已是第一章

    _extendingWindow = true;
    try {
      final added = <int>[];
      final buffer = StringBuffer();
      int insertedChars = 0;
      for (var i = _preloadCount; i >= 1; i--) {
        final idx = firstIndex - i;
        if (idx < 0) continue;
        final chStart = book.chapters[idx].startIndex;
        final chEnd = _localChapterEnd(idx);
        if (chEnd <= chStart) continue;
        final text = book.content.substring(chStart, chEnd);
        added.add(idx);
        _chapterCache[idx] = text;
        buffer.write(text);
        buffer.write('\n\n');
        insertedChars += text.length + 2;
      }
      buffer.write(_displayText);

      if (added.isEmpty) return false;
      if (!mounted) return false;

      setState(() {
        _displayText = buffer.toString();
        _windowChapters = [...added, ..._windowChapters];
        _windowStartFullOffset = book.chapters[added.first].startIndex;
        _currentCharIndex += insertedChars;
      });
      await _splitPages();
      return true;
    } finally {
      _extendingWindow = false;
    }
  }

  Future<bool> _extendWindowForward() async {
    if (_extendingWindow) return false;
    final book = widget.book;
    if (book.source != BookSource.url || book.chapters.isEmpty) return false;
    if (_windowChapters.isEmpty) return false;

    final lastIndex = _windowChapters.last;
    if (lastIndex >= book.chapters.length - 1) return false; // 已是最后一章

    debugPrint('_extendWindowForward: lastIndex=$lastIndex totalChapters=${book.chapters.length}');
    _extendingWindow = true;
    try {
      final newIndices = <int>[];
      for (var i = 1; i <= _preloadCount; i++) {
        final idx = lastIndex + i;
        if (idx >= book.chapters.length) break;
        if (!_chapterCache.containsKey(idx)) newIndices.add(idx);
      }
      if (newIndices.isNotEmpty) {
        await Future.wait(newIndices.map((i) => _fetchChapterText(i)));
      }

      final added = <int>[];
      final buffer = StringBuffer(_displayText);
      for (var i = 1; i <= _preloadCount; i++) {
        final idx = lastIndex + i;
        if (idx >= book.chapters.length) break;
        final text = _chapterCache[idx];
        if (text == null || text.isEmpty) continue;
        added.add(idx);
        buffer.write(text);
        buffer.write('\n\n');
      }

      if (added.isEmpty) return false;

      if (!mounted) return false;
      setState(() {
        _displayText = buffer.toString();
        _windowChapters = [..._windowChapters, ...added];
      });
      await _splitPages();
      return true;
    } finally {
      _extendingWindow = false;
    }
  }

  Future<bool> _extendWindowBackward() async {
    if (_extendingWindow) return false;
    final book = widget.book;
    if (book.source != BookSource.url || book.chapters.isEmpty) return false;
    if (_windowChapters.isEmpty) return false;

    final firstIndex = _windowChapters.first;
    if (firstIndex <= 0) return false; // 已是第一章

    debugPrint('_extendWindowBackward: firstIndex=$firstIndex totalChapters=${book.chapters.length}');
    _extendingWindow = true;
    try {
      final newIndices = <int>[];
      for (var i = 1; i <= _preloadCount; i++) {
        final idx = firstIndex - i;
        if (idx < 0) break;
        if (!_chapterCache.containsKey(idx)) newIndices.add(idx);
      }
      if (newIndices.isNotEmpty) {
        await Future.wait(newIndices.map((i) => _fetchChapterText(i)));
      }

      final added = <int>[];
      final buffer = StringBuffer();
      int insertedChars = 0;
      for (var i = _preloadCount; i >= 1; i--) {
        final idx = firstIndex - i;
        if (idx < 0) continue;
        final text = _chapterCache[idx];
        if (text == null || text.isEmpty) continue;
        added.add(idx);
        buffer.write(text);
        buffer.write('\n\n');
        insertedChars += text.length + 2;
      }
      buffer.write(_displayText);

      if (added.isEmpty) return false;

      if (!mounted) return false;
      setState(() {
        _displayText = buffer.toString();
        _windowChapters = [...added, ..._windowChapters];
        _currentCharIndex += insertedChars;
      });
      await _splitPages();
      return true;
    } finally {
      _extendingWindow = false;
    }
  }

  void _onConfigChanged() {
    if (!mounted) return;
    _splitPages();
  }

  Future<void> _splitPages({bool jumpAfterSplit = true}) async {
    if (_displayText.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 分割序号：compute 返回后若期间又有新的分割请求（_splitSeq 变大），
    final splitSeq = ++_splitSeq;

    final config = Provider.of<ReadingProvider>(context, listen: false).config;
    final pageSize = _calculatePageSize(config);
    final text = _displayText;
    final isScrollMode = config.scrollMode;
    // 视口宽度（用于在 isolate 中测量段落高度）
    final viewportWidth = MediaQuery.of(context).size.width;
    var viewportHeight = _pageViewportHeight;
    if (viewportHeight <= 0) {
      viewportHeight = MediaQuery.of(context).size.height - 200;
    }

    if (mounted) setState(() => _isLoading = true);

    // 注意：多行文本的行距（TextHeightBehavior/strut）可能使实际行高略大于单字符测量值，
    final textStyle = TextStyle(
      fontSize: config.fontSize,
      fontFamily: config.fontFamily == 'System' ? null : config.fontFamily,
      height: config.lineHeight,
    );
    final samplePainter = TextPainter(
      text: TextSpan(text: '测测\n测测', style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // 多行样本实测单行高度：单行测量与多行实际渲染存在行距（leading）差异，
    final oneLinePainter = TextPainter(
      text: TextSpan(text: '测测', style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final twoLineHeight = samplePainter.height;
    final oneLineHeight = oneLinePainter.height;
    // 多行行高 = 两行总高 - 单行高（去掉首行的行距重叠部分）
    final actualLineHeight = (twoLineHeight - oneLineHeight).clamp(oneLineHeight * 0.5, oneLineHeight * 2);

    final chapterStartOffsets = <int>[];
    final chapterTitles = <String>[];
    if (!isScrollMode && _windowChapters.isNotEmpty) {
      int acc = 0;
      for (final idx in _windowChapters) {
        final cached = _chapterCache[idx];
        if (cached != null) {
          chapterStartOffsets.add(acc);
          acc += cached.length + 2;
        }
        if (idx >= 0 && idx < widget.book.chapters.length) {
          chapterTitles.add(widget.book.chapters[idx].title.trim());
        }
      }
    }

    final (paraHeights, paraLineBreaks) = await _measureParagraphHeights(
      text: text.replaceAll('\r', ''),
      textStyle: textStyle,
      maxLineWidth: viewportWidth - 40 - config.fontSize,
    );

    final result = await compute(
      _splitTextInIsolate,
      _SplitTask(
        text,
        pageSize,
        isScrollMode,
        config.fontSize,
        config.lineHeight,
        config.fontFamily,
        viewportWidth,
        viewportHeight,
        actualLineHeight,
        chapterStartOffsets,
        chapterTitles,
        paraHeights,
        paraLineBreaks,
      ),
    );
    if (!mounted || splitSeq != _splitSeq) return;

    _pages = result.pages;
    _paragraphs = result.paragraphs;
    _paragraphHeights = result.paragraphHeights;
    _paragraphOffsets = result.paragraphOffsets;
    _pageStartPara = result.pageStartPara;
    _pageStartChar = result.pageStartChar;
    _paragraphKeys = List<GlobalKey>.generate(_paragraphs.length, (_) => GlobalKey());

    _chapterParaStart = _computeChapterParaStart();
    _chapterPageStart = _computeChapterPageStart();

    if (_pages.isNotEmpty) {
      _currentPage = _pageIndexForChar(_currentCharIndex);
      if (_currentPage >= _pages.length) _currentPage = _pages.length - 1;
      if (_currentPage < 0) _currentPage = 0;
    }

    // 章节加载路径（jumpAfterSplit=false）由调用方自行精确定位，
    if (!jumpAfterSplit) {
      setState(() => _isLoading = false);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cfg = Provider.of<ReadingProvider>(context, listen: false).config;
      if (cfg.scrollMode) {
        setState(() => _isLoading = false);
        final pi = _findParagraphIndex(_currentCharIndex);
        _logJump('splitDone charIndex=$_currentCharIndex paraIndex=$pi '
            'paraCount=${_paragraphs.length} '
            'paraOffset=${pi < _paragraphOffsets.length ? _paragraphOffsets[pi] : -1} '
            'paraHeight=${pi < _paragraphHeights.length ? _paragraphHeights[pi] : -1} '
            'viewport=${MediaQuery.of(context).size.width}');
        _scrollToCharIndex(_currentCharIndex);
        return;
      }
      _suppressPageCharSync = true;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage.clamp(0, _pages.length - 1));
      }
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients &&
            _pageController.page?.round() != _currentPage) {
          _suppressPageCharSync = true;
          _pageController.jumpToPage(_currentPage.clamp(0, _pages.length - 1));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _suppressPageCharSync = false;
        });
      });
    });
  }

  int _calculatePageSize(ReadingConfig config) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final padding = 40.0;
    final availableWidth = screenWidth - padding * 2;
    final availableHeight = screenHeight - 200;
    final charWidth = config.fontSize * 1.0;
    final charHeight = config.fontSize * config.lineHeight;
    final charsPerLine = (availableWidth / charWidth).floor();
    final linesPerPage = (availableHeight / charHeight).floor();
    return (charsPerLine * linesPerPage).clamp(100, 2000);
  }

  /// 段落分割：与 _splitTextInIsolate 保持一致。
  /// 超长段落（在线识别正文常见：段落间只有单 \n 无空行分隔，
  /// 整章/大半章被合并成一段）按行切分为自然段，否则朗读高亮会覆盖整页。
  List<String> _splitParagraphs(String text) {
    final paragraphs = <String>[];
    for (final raw in text.split(RegExp(r'\n\s*\n'))) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^[-=—_]{4,}$').hasMatch(t)) continue;
      final clean = raw.replaceAll('\r', '');
      if (clean.trim().isEmpty) continue;
      if (clean.length > 500 && clean.contains('\n')) {
        for (final line in clean.split('\n')) {
          if (line.trim().isNotEmpty) paragraphs.add(line.trim());
        }
      } else {
        paragraphs.add(clean);
      }
    }
    return paragraphs;
  }

  Future<(List<double>?, List<List<int>>?)> _measureParagraphHeights({
    required String text,
    required TextStyle textStyle,
    required double maxLineWidth,
  }) async {
    try {
      final paragraphs = _splitParagraphs(text);
      final heights = <double>[];
      final lineBreaks = <List<int>>[];
      final textScaler = MediaQuery.textScalerOf(context);
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      );
      for (var i = 0; i < paragraphs.length; i++) {
        if (i > 0 && i % 40 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        textPainter.text = TextSpan(text: paragraphs[i], style: textStyle);
        textPainter.layout(maxWidth: maxLineWidth);
        heights.add(textPainter.height);
        final breaks = <int>[];
        final p = paragraphs[i];
        if (p.isNotEmpty) {
          int offset = 0;
          var guard = 0;
          while (offset < p.length && guard < 100000) {
            guard++;
            if (p.codeUnitAt(offset) == 10) {
              offset++;
              continue;
            }
            final range =
                textPainter.getLineBoundary(TextPosition(offset: offset));
            if (range.end <= offset) {
              offset++;
              continue;
            }
            breaks.add(range.end);
            offset = range.end;
          }
        }
        lineBreaks.add(breaks);
      }
      textPainter.dispose();
      return (heights, lineBreaks);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    _uiAnimationController.dispose();
    _ttsPageCompleteSub?.cancel();
    try {
      Provider.of<ReadingProvider>(context, listen: false).removeListener(_onConfigChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('HOTRELOAD_TEST_123');
    return Consumer<ReadingProvider>(
      builder: (context, readingProvider, _) {
        final config = readingProvider.config;
        final bgColor = config.nightMode
            ? AppTheme.darkBackground
            : AppTheme.readingBackgrounds[config.theme] ?? AppTheme.readingBackgrounds[ReadingTheme.classic]!;
        final textColor = config.nightMode
            ? AppTheme.darkTextPrimary
            : AppTheme.readingTextColors[config.theme] ?? AppTheme.readingTextColors[ReadingTheme.classic]!;

        return Scaffold(
          backgroundColor: bgColor,
          body: Stack(
            children: [
              // 阅读内容
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _emptyMessage.isNotEmpty
                                  ? Center(
                                      child: Text(
                                        _emptyMessage,
                                        style: TextStyle(
                                          color: textColor.withValues(alpha: 0.6),
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : config.scrollMode
                                      ? _buildScrollContent(config, textColor)
                                      : _buildPageContent(config, textColor),
                            ),
                            if (_isLoading)
                              const Positioned.fill(
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 底部进度
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              config.scrollMode
                                  ? '滚动阅读'
                                  : _currentChapterPageLabel(),
                              style: TextStyle(
                                fontSize: 12,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                            Text(
                              config.scrollMode
                                  ? '${(_scrollProgress * 100).toStringAsFixed(0)}%'
                                  : '${((_fullTextOffset() / widget.book.totalLength) * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (config.scrollMode)
                Positioned.fill(
                  child: _TapToToggle(onToggle: _toggleUI),
                ),

              AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: SafeArea(
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded, color: textColor),
                          onPressed: () => _exitReader(),
                        ),
                        IconButton(
                          icon: Icon(Icons.menu_book_rounded, color: textColor),
                          onPressed: () => _showChapterList(),
                        ),
                        const Spacer(),
                        Consumer<ReadingProvider>(
                          builder: (context, rp, _) {
                            return IconButton(
                              icon: Icon(
                                rp.isBookmarked
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                color: rp.isBookmarked ? AppTheme.primaryColor : textColor,
                              ),
                              onPressed: () => _toggleBookmark(),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.text_fields_rounded, color: textColor),
                          onPressed: () => _showSettings(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                bottom: _showUI ? 0 : -400,
                left: 0,
                right: 0,
                child: _buildBottomControls(bgColor, textColor),
              ),

              if (_isTtsPlaying)
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: TtsControlBar(
                    book: widget.book,
                    onClose: () => _stopTts(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 上下滚动模式
  /// 使用 ListView.builder 按需构建段落，避免一次性渲染整个大文本导致卡顿
  Widget _buildScrollContent(ReadingConfig config, Color textColor) {
    // 按段落分割（复用 _paragraphs，若为空则重新分割）
    if (_paragraphs.isEmpty && _displayText.isNotEmpty) {
      _paragraphs = _splitParagraphs(_displayText);
    }
    if (_paragraphKeys.length != _paragraphs.length) {
      _paragraphKeys = List<GlobalKey>.generate(_paragraphs.length, (_) => GlobalKey());
    }
    final hasHeights = _paragraphHeights.length == _paragraphs.length;

    final textStyle = TextStyle(
      fontSize: config.fontSize,
      fontFamily: config.fontFamily == 'System' ? null : config.fontFamily,
      height: config.lineHeight,
      color: textColor,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: _paragraphs.length,
      itemExtentBuilder: hasHeights
          ? (index, _) => _paragraphHeights[index] + 12 // 12 = 段落底部 margin
          : null,
      itemBuilder: (context, index) {
        final paragraph = _paragraphs[index];
        if (index > _currentVisibleParagraph) {
          _currentVisibleParagraph = index;
        }
        // TTS 高亮当前朗读段落
        final isHighlighted = _isTtsPlaying &&
            _currentTtsParagraph >= 0 &&
            _currentTtsParagraph < _ttsLines.length &&
            paragraph.trim().isNotEmpty &&
            paragraph
                .trim()
                .contains(_applyBlockedWords(_ttsLines[_currentTtsParagraph]));
        final itemHeight = hasHeights ? _paragraphHeights[index] + 12 : null;
        Widget content = Container(
          key: _paragraphKeys[index],
          margin: const EdgeInsets.only(bottom: 12),
          decoration: isHighlighted
              ? BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: SelectionArea(
            child: Text(
              _applyBlockedWords(paragraph),
              style: textStyle,
            ),
          ),
        );
        if (itemHeight != null) {
          content = SizedBox(height: itemHeight, child: content);
        }
        return content;
      },
    );
  }

  /// 延迟分割的稳定确认：键盘动画/布局变化期间高度会持续变化，
  void _trySplitAfterStable(int attempt) {
    if (!mounted) return;
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      _splitScheduled = false;
      return;
    }
    // 高度已与保存值一致（键盘动画结束、布局恢复）→ 无需分割
    if ((_pageViewportHeight - _lastBuildUsableH).abs() <= 1) {
      _splitScheduled = false;
      return;
    }
    if (attempt < 4) {
      Future<void>.delayed(const Duration(milliseconds: 250),
          () => _trySplitAfterStable(attempt + 1));
      return;
    }
    // 持续变化超时：按当前值分割（旋转屏幕/字体变化等真实场景）
    _splitScheduled = false;
    _pageViewportHeight = _lastBuildUsableH;
    _splitPages();
  }

  Widget _buildPageContent(ReadingConfig config, Color textColor) {
    if (_pages.isEmpty) {
      // _pages 为空（加载中/尚未分割）时不渲染文本：
      // 直接 _buildTextContent 会用 _getCurrentPageText 返回整本 _displayText
      return const SizedBox.shrink();
    }

    final animation = config.animation;

    // 若实测高度与上次分割时不同（如旋转屏幕、字体变化），触发重新分割，
    // 比完全不留白观感更稳，避免正文顶到屏幕边缘）。toggle 只切换控制栏
    const bottomReserve = 60.0;
    Widget pageView = LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // viewInsets 更新，直接比较会误触发重分割（vh 被键盘高度污染，
        // 键盘操作导致转圈 + 页面重建跳转几次）。处理：
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final splitUsableH =
            (h + keyboardHeight - bottomReserve).clamp(0.0, h + keyboardHeight);
        _lastBuildUsableH = splitUsableH;
        if (splitUsableH > 0 &&
            !_isLoading &&
            !_splitScheduled &&
            (_pageViewportHeight - splitUsableH).abs() > 1) {
          _splitScheduled = true;
          Future<void>.delayed(const Duration(milliseconds: 250),
              () => _trySplitAfterStable(0));
        }
        return _buildPageView(config, textColor, animation);
      },
    );

    return Listener(
      // 区分点击与滑动：记录按下位置，抬起时位移超过阈值视为滑动，
      onPointerDown: (event) {
        _pointerDownPos = event.localPosition;
      },
      onPointerUp: (event) {
        if (config.scrollMode) {
          _toggleUI();
          return;
        }
        final down = _pointerDownPos;
        _pointerDownPos = null;
        if (down != null) {
          final dx = (event.localPosition.dx - down.dx).abs();
          final dy = (event.localPosition.dy - down.dy).abs();
          if (dx > 15 || dy > 15) return;
        }
        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = event.localPosition.dx;
        if (tapX < screenWidth / 3) {
          _previousPage();
        } else if (tapX > screenWidth * 2 / 3) {
          _nextPage();
        } else {
          _toggleUI();
        }
      },
      child: pageView,
    );
  }

  Widget _buildPageView(ReadingConfig config, Color textColor, PageAnimation animation) {
    Widget pageView;
    switch (animation) {
      case PageAnimation.slide:
        pageView = PageView.builder(
          key: const ValueKey('slide'),
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          onPageChanged: (page) {
            setState(() {
              _currentPage = page;
              if (_suppressPageCharSync) {
                _suppressPageCharSync = false;
              } else {
                _currentCharIndex = _charIndexForPage(page);
              }
            });
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
            _saveProgress();
          },
          itemCount: _pages.length,
          itemBuilder: (context, index) {
            return ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildTextContent(config, textColor, pageIndex: index),
              ),
            );
          },
        );
      case PageAnimation.curl:
        // 点击左右 1/3 区域翻页（_nextPage/_previousPage 更新 _currentPage），
        pageView = _buildAnimatedPageSwitcher(
          config,
          textColor,
          keyName: 'curl',
          curlStyle: true,
        );
      case PageAnimation.fade:
        pageView = _buildAnimatedPageSwitcher(
          config,
          textColor,
          keyName: 'fade',
          curlStyle: false,
        );
      case PageAnimation.none:
        pageView = PageView.builder(
          key: const ValueKey('none'),
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (page) {
            setState(() {
              _currentPage = page;
              if (_suppressPageCharSync) {
                _suppressPageCharSync = false;
              } else {
                _currentCharIndex = _charIndexForPage(page);
              }
            });
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
            _saveProgress();
          },
          itemCount: _pages.length,
          itemBuilder: (context, index) {
            return ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildTextContent(config, textColor, pageIndex: index),
              ),
            );
          },
        );
    }
    return pageView;
  }

  /// 动画效果：每页内容包 TweenAnimationBuilder，页面首次构建时从透明淡入（fade），
  Widget _buildAnimatedPageSwitcher(
    ReadingConfig config,
    Color textColor, {
    required String keyName,
    required bool curlStyle,
  }) {
    final animationDuration = const Duration(milliseconds: 250);
    return PageView.builder(
      key: ValueKey(keyName),
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      onPageChanged: (page) {
        setState(() {
          _currentPage = page;
          if (_suppressPageCharSync) {
            _suppressPageCharSync = false;
          } else {
            _currentCharIndex = _charIndexForPage(page);
          }
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        _saveProgress();
      },
      itemCount: _pages.length,
      itemBuilder: (context, index) {
        final content = RepaintBoundary(
          child: _buildTextContent(config, textColor,
              pageIndex: index, enableSelection: false),
        );
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: animationDuration,
          curve: Curves.easeOut,
          builder: (context, value, child) {
            if (!curlStyle) {
              return Opacity(opacity: value, child: child);
            }
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset((1 - value) * 24, 0),
                child: child,
              ),
            );
          },
          child: ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              child: content,
            ),
          ),
        );
      },
    );
  }

  /// 屏蔽词过滤：把正文中的屏蔽词**直接剔除**（删除），显示与 TTS 朗读
  String _applyBlockedWords(String text) {
    final words = widget.book.blockedWords
        .where((w) => w.trim().length >= 2)
        .toList();
    if (words.isEmpty) return text;
    var result = text;
    for (final w in words) {
      final word = w.trim();
      if (word.isEmpty) continue;
      result = result.replaceAll(word, '');
    }
    return result;
  }

  Widget _buildTextContent(ReadingConfig config, Color textColor,
      {int? pageIndex, bool enableSelection = true}) {
    final text = pageIndex != null && pageIndex < _pages.length
        ? _pages[pageIndex]
        : _getCurrentPageText();
    final displayText = _applyBlockedWords(text);

    if (_isTtsPlaying && _currentTtsParagraph >= 0) {
      return _buildHighlightedText(displayText, config, textColor);
    }

    final textWidget = Text(
      displayText,
      style: TextStyle(
        fontSize: config.fontSize,
        fontFamily: config.fontFamily == 'System' ? null : config.fontFamily,
        height: config.lineHeight,
        color: textColor,
      ),
    );
    if (!enableSelection) return textWidget;
    return SelectionArea(child: textWidget);
  }

  Widget _buildHighlightedText(String text, ReadingConfig config, Color textColor) {
    final paragraphs = text.split('\n');
    final highlightColor = AppTheme.primaryColor.withValues(alpha: 0.15);
    final currentLine = (_isTtsPlaying &&
            _currentTtsParagraph >= 0 &&
            _currentTtsParagraph < _ttsLines.length)
        ? _applyBlockedWords(_ttsLines[_currentTtsParagraph])
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(paragraphs.length, (index) {
        final lineText = paragraphs[index].trim();
        final isHighlighted = currentLine.isNotEmpty &&
            lineText.isNotEmpty &&
            currentLine.contains(lineText);
        return GestureDetector(
          onTapUp: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            final tapX = details.localPosition.dx;
            if (tapX < screenWidth / 3) {
              _previousPage();
            } else if (tapX > screenWidth * 2 / 3) {
              _nextPage();
            } else {
              _startTtsFromParagraph(index, paragraphs);
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isHighlighted ? highlightColor : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              paragraphs[index],
              style: TextStyle(
                fontSize: config.fontSize,
                fontFamily: config.fontFamily == 'System' ? null : config.fontFamily,
                height: config.lineHeight,
                color: textColor,
              ),
            ),
          ),
        );
      }),
    );
  }

  /// 判断段落是否在当前TTS朗读位置
  bool _isParagraphInCurrentPage(int paragraphIndex, String paragraphText) {
    if (!_isTtsPlaying || _currentTtsParagraph < 0) return false;
    if (_currentTtsParagraph >= _paragraphs.length) return false;
    // 用真实段落起始偏移，避免 +2 假设漂移
    final charPos = (_paragraphOffsets.length == _paragraphs.length)
        ? _paragraphOffsets[_currentTtsParagraph]
        : _paragraphs
            .take(_currentTtsParagraph)
            .fold(0, (sum, p) => sum + p.length + 2);
    return charPos >= _currentCharIndex &&
        charPos < _currentCharIndex + _getCurrentPageText().length;
  }

  Widget _buildBottomControls(Color bgColor, Color textColor) {
    final config = Provider.of<ReadingProvider>(context, listen: false).config;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bgColor.withValues(alpha: 0),
            bgColor.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: textColor.withValues(alpha: 0.2),
                thumbColor: AppTheme.primaryColor,
              ),
              child: Slider(
                value: config.scrollMode
                    ? _scrollProgress
                    : _pageChapterProgress(),
                onChanged: (value) {
                  setState(() {
                    if (config.scrollMode) {
                      final (chStart, chEnd) = _currentChapterWindowRange();
                      final chLen = chEnd - chStart;
                      final targetInWindow =
                          (chStart + value * chLen).round().clamp(chStart, chEnd - 1);
                      _currentCharIndex = targetInWindow;
                      _scrollProgress = value;
                      _scrollToCharIndex(targetInWindow);
                    } else {
                      _currentPage = (value * (_pages.length - 1)).round();
                      _currentCharIndex = _charIndexForPage(_currentPage);
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(_currentPage);
                      }
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded),
                color: textColor,
                onPressed: _previousPage,
              ),
              IconButton(
                icon: Icon(
                  _isTtsPlaying ? Icons.stop_circle_outlined : Icons.headphones_rounded,
                ),
                color: AppTheme.primaryColor,
                iconSize: 32,
                onPressed: () => _toggleTts(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded),
                color: textColor,
                onPressed: _nextPage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getCurrentPageText() {
    if (_pages.isEmpty) return '';
    if (_currentPage >= _pages.length) _currentPage = _pages.length - 1;
    return _pages[_currentPage];
  }

  void _toggleUI() {
    setState(() {
      _showUI = !_showUI;
      if (_showUI) {
        _uiAnimationController.forward();
      } else {
        _uiAnimationController.reverse();
      }
    });
  }

  void _nextPage() {
    debugPrint('HOTRELOAD_TEST_123');
    final config = Provider.of<ReadingProvider>(context, listen: false).config;
    if (config.scrollMode) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final target = _scrollController.offset + MediaQuery.of(context).size.height - 200;
      if (target < maxExtent) {
        _scrollController.animateTo(
          target.clamp(0.0, maxExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else if (widget.book.chapters.isNotEmpty) {
        if (widget.book.source == BookSource.url) {
          _extendWindowForward();
        } else {
          _extendLocalWindowForward();
        }
      }
      return;
    }

    if (_currentPage < _pages.length - 1) {
      setState(() {
        _currentPage++;
        _currentCharIndex = _charIndexForPage(_currentPage);
      });
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _saveProgress();
    } else if (widget.book.chapters.isNotEmpty &&
        widget.book.currentChapter < widget.book.chapters.length - 1) {
      if (widget.book.source == BookSource.url) {
        _loadChapterWindow(widget.book.currentChapter + 1);
      } else {
        _loadLocalChapterWindow(widget.book.currentChapter + 1,
            restorePosition: false);
      }
    }
  }

  void _previousPage() {
    final config = Provider.of<ReadingProvider>(context, listen: false).config;
    if (config.scrollMode) {
      final target = _scrollController.offset - MediaQuery.of(context).size.height + 200;
      if (target > 0) {
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else if (widget.book.chapters.isNotEmpty) {
        if (widget.book.source == BookSource.url) {
          _extendWindowBackward();
        } else {
          _extendLocalWindowBackward();
        }
      }
      return;
    }

    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
        _currentCharIndex = _charIndexForPage(_currentPage);
      });
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _saveProgress();
    } else if (widget.book.chapters.isNotEmpty &&
        widget.book.currentChapter > 0) {
      if (widget.book.source == BookSource.url) {
        _loadChapterWindow(widget.book.currentChapter - 1);
      } else {
        _loadLocalChapterWindow(widget.book.currentChapter - 1,
            restorePosition: false);
      }
    }
  }

  void _saveProgress() {
    final book = widget.book;
    if (book.source == BookSource.url && _windowChapters.isNotEmpty) {
      final chapterIndex = _chapterIndexAtChar(_currentCharIndex);
      if (chapterIndex >= 0) {
        final chapterText = _chapterCache[chapterIndex];
        final chapterStart = _chapterStartChar(chapterIndex);
        final inChapterPos = (_currentCharIndex - chapterStart).clamp(0, chapterText?.length ?? 0);
        book.currentChapter = chapterIndex;
        book.currentPosition = inChapterPos;
        Provider.of<BookProvider>(context, listen: false).updateBook(book);
        return;
      }
    }
    if (book.source == BookSource.local && _windowChapters.isNotEmpty) {
      final fullOffset = _windowStartFullOffset + _currentCharIndex;
      Provider.of<BookProvider>(context, listen: false)
          .updateReadingProgress(book.id, fullOffset);
      return;
    }
    Provider.of<BookProvider>(context, listen: false)
        .updateReadingProgress(book.id, _currentCharIndex);
  }

  int _chapterIndexAtChar(int charIndex) {
    if (_windowChapters.isEmpty) return -1;
    final paraIndex = _findParagraphIndex(charIndex);
    int chapterPos = 0;
    for (var i = 0; i < _chapterParaStart.length; i++) {
      if (paraIndex >= _chapterParaStart[i]) {
        chapterPos = i;
      } else {
        break;
      }
    }
    return _windowChapters[chapterPos];
  }

  int _chapterStartChar(int chapterIndex) {
    if (_windowChapters.isEmpty) return 0;
    final pos = _windowChapters.indexOf(chapterIndex);
    if (pos < 0) return 0;
    final paraStart = _chapterParaStart[pos];
    if (paraStart < _paragraphOffsets.length) {
      return _paragraphOffsets[paraStart];
    }
    return 0;
  }

  List<int> _computeChapterParaStart() {
    if (_windowChapters.isEmpty || _paragraphOffsets.length != _paragraphs.length) {
      return [];
    }
    final starts = <int>[];
    final chapterCharStarts = <int>[];
    {
      int acc = 0;
      for (final idx in _windowChapters) {
        final cached = _chapterCache[idx];
        if (cached != null) {
          chapterCharStarts.add(acc);
          acc += cached.length + 2; // +2 为章节间分隔符 '\n\n'
        } else if (widget.book.source == BookSource.local &&
            idx >= 0 &&
            idx < widget.book.chapters.length) {
          chapterCharStarts.add(
              (widget.book.chapters[idx].startIndex - _windowStartFullOffset)
                  .clamp(0, _displayText.length));
        } else if (idx >= 0 && idx < widget.book.chapters.length) {
          final total = widget.book.chapters.length;
          final ratio = total > 1 ? idx / (total - 1) : 0.0;
          chapterCharStarts.add((ratio * _displayText.length).round());
        } else {
          chapterCharStarts.add(acc);
        }
      }
    }
    final titles = _windowChapters.map((idx) {
      if (idx >= 0 && idx < widget.book.chapters.length) {
        return widget.book.chapters[idx].title.trim();
      }
      return '';
    }).toList();
    int searchFrom = 0;
    for (final title in titles) {
      if (title.isEmpty) {
        starts.add(searchFrom.clamp(0, _paragraphs.length - 1));
        continue;
      }
      // 从上次位置向后找标题段（章节顺序递增），避免前面章节正文中的
      int found = -1;
      for (var i = searchFrom; i < _paragraphs.length; i++) {
        if (_paragraphs[i].trim() == title) {
          found = i;
          break;
        }
      }
      if (found < 0) {
        // 标题未找到（极端情况）：退化用偏移二分
        final start = chapterCharStarts[starts.length < chapterCharStarts.length ? starts.length : chapterCharStarts.length - 1];
        int lo = 0, hi = _paragraphOffsets.length - 1, ans = 0;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (_paragraphOffsets[mid] <= start) {
            ans = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        found = ans;
      }
      starts.add(found);
      searchFrom = found + 1;
    }
    return starts;
  }

  List<int> _computeChapterPageStart() {
    if (_windowChapters.isEmpty || _pageStartPara.isEmpty) return [];
    final starts = <int>[];
    for (final paraStart in _chapterParaStart) {
      int lo = 0, hi = _pageStartPara.length - 1, ans = 0;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (_pageStartPara[mid] <= paraStart) {
          ans = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      starts.add(ans);
    }
    return starts;
  }

  int _pageIndexForChar(int charIndex) {
    if (_pageStartChar.isEmpty) return 0;
    int lo = 0, hi = _pageStartChar.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_pageStartChar[mid] <= charIndex) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  int _pageIndexForPara(int paraIndex) {
    if (_pageStartPara.isEmpty) return 0;
    int lo = 0, hi = _pageStartPara.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_pageStartPara[mid] <= paraIndex) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  int _charIndexForPage(int page) {
    if (_pageStartChar.isEmpty) return 0;
    if (page < 0) page = 0;
    if (page >= _pageStartChar.length) page = _pageStartChar.length - 1;
    return _pageStartChar[page];
  }

  String _currentChapterPageLabel() {
    if (_pages.isEmpty) return '0/0';
    int chapterPos = 0;
    for (var i = 0; i < _chapterPageStart.length; i++) {
      if (_currentPage >= _chapterPageStart[i]) {
        chapterPos = i;
      } else {
        break;
      }
    }
    final chapterStart = _chapterPageStart.isEmpty ? 0 : _chapterPageStart[chapterPos];
    final chapterEnd = (chapterPos + 1 < _chapterPageStart.length)
        ? _chapterPageStart[chapterPos + 1]
        : _pages.length;
    final chapterCount = (chapterEnd - chapterStart).clamp(1, _pages.length);
    final inChapter =
        (_currentPage - chapterStart).clamp(0, chapterCount - 1);
    return '${inChapter + 1}/$chapterCount';
  }

  double _pageChapterProgress() {
    if (_pages.isEmpty || _chapterPageStart.isEmpty) {
      return _pages.isEmpty ? 0 : (_currentPage / (_pages.length - 1)).clamp(0.0, 1.0);
    }
    int chapterPos = 0;
    for (var i = 0; i < _chapterPageStart.length; i++) {
      if (_currentPage >= _chapterPageStart[i]) {
        chapterPos = i;
      } else {
        break;
      }
    }
    final chapterStart = _chapterPageStart[chapterPos];
    final chapterEnd = (chapterPos + 1 < _chapterPageStart.length)
        ? _chapterPageStart[chapterPos + 1]
        : _pages.length;
    final chapterCount = (chapterEnd - chapterStart).clamp(1, _pages.length);
    final inChapter = (_currentPage - chapterStart).clamp(0, chapterCount - 1);
    if (chapterCount <= 1) return 0;
    return (inChapter / (chapterCount - 1)).clamp(0.0, 1.0);
  }

  int _fullTextOffset() {
    if (widget.book.source == BookSource.local && _windowChapters.isNotEmpty) {
      return _windowStartFullOffset + _currentCharIndex;
    }
    return _currentCharIndex;
  }

  void _toggleBookmark() async {
    final readingProvider = Provider.of<ReadingProvider>(context, listen: false);
    final currentText = _getCurrentPageText();
    final fullOffset = _fullTextOffset();

    readingProvider.checkBookmark(widget.book.id, fullOffset);

    if (readingProvider.isBookmarked) {
      try {
        final bookmark = readingProvider.bookmarks.firstWhere(
          (b) => b.position == fullOffset,
        );
        await readingProvider.removeBookmark(bookmark.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('已移除书签'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(label: '撤销', onPressed: () async {
                await readingProvider.addBookmark(
                  widget.book.id,
                  fullOffset,
                  currentText,
                );
              }),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('操作失败'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      try {
        await readingProvider.addBookmark(
          widget.book.id,
          fullOffset,
          currentText,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('操作失败'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已添加书签'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: '撤销', onPressed: () async {
              try {
                final bookmark = readingProvider.bookmarks.firstWhere(
                  (b) => b.position == fullOffset,
                );
                await readingProvider.removeBookmark(bookmark.id);
              } catch (_) {}
            }),
          ),
        );
      }
    }
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderSettingsSheet(
        book: widget.book,
        onBlockedWordsChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// 显示章节目录
  void _showChapterList() {
    final chapters = widget.book.chapters;
    if (chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未识别到章节')),
      );
      return;
    }

    final currentChapterIndex = widget.book.source == BookSource.url
        ? widget.book.currentChapter
        : ChapterService().findChapterIndex(chapters, _fullTextOffset());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChapterListSheet(
        chapters: chapters,
        currentChapterIndex: currentChapterIndex,
        onSelect: (index) {
          Navigator.pop(context);
          _jumpToChapter(index);
        },
      ),
    );
  }

  void _jumpToChapter(int chapterIndex) {
    final chapters = widget.book.chapters;
    if (chapterIndex < 0 || chapterIndex >= chapters.length) return;

    if (widget.book.source == BookSource.url) {
      _loadChapterWindow(chapterIndex);
      return;
    }
    // 本地书籍：从 book.content 切片加载目标章节窗口
    if (widget.book.source == BookSource.local) {
      _loadLocalChapterWindow(chapterIndex, restorePosition: false);
      return;
    }

    final targetIndex = chapters[chapterIndex].startIndex;
    final config = Provider.of<ReadingProvider>(context, listen: false).config;

    setState(() {
      _currentCharIndex = targetIndex;
      if (config.scrollMode) {
        // 滚动模式：跳转到对应滚动位置
        _scrollToCharIndex(targetIndex);
      } else {
        _currentPage = _pageIndexForChar(targetIndex);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentPage);
        }
      }
    });

    _saveProgress();
  }

  void _scrollToCharIndex(int charIndex) {
    if (!_scrollController.hasClients || _paragraphs.isEmpty) return;
    final paraIndex = _findParagraphIndex(charIndex).clamp(0, _paragraphs.length - 1);
    _logJump('_scrollToCharIndex charIndex=$charIndex paraIndex=$paraIndex '
        'pixels=${_scrollController.position.pixels} '
        'maxExtent=${_scrollController.position.maxScrollExtent} '
        'viewport=${_scrollController.position.viewportDimension}');
    _jumpToParagraph(paraIndex, 0);
  }

  void _jumpToParagraph(int paraIndex, int attempt) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    double target;
    if (_paragraphHeights.length == _paragraphs.length) {
      target = 0;
      for (int i = 0; i < paraIndex; i++) {
        target += _paragraphHeights[i] + 12;
      }
    } else {
      if (attempt == 0) {
        _currentVisibleParagraph = 0;
      }
      final visible = _currentVisibleParagraph.clamp(1, _paragraphs.length - 1);
      final offsetPerPara = position.pixels > 0
          ? position.pixels / visible
          : position.viewportDimension / visible;
      target = paraIndex * offsetPerPara;
    }
    // 粗定位到目标段落（不额外加屏：加屏是盲目的，会在估算偏差大时
    final jumpTarget = target.clamp(0.0, position.maxScrollExtent);
    _logJump('_jumpToParagraph attempt=$attempt paraIndex=$paraIndex '
        'target=$target jumpTarget=$jumpTarget '
        'maxExtent=${position.maxScrollExtent} viewport=${position.viewportDimension}');
    _scrollController.jumpTo(jumpTarget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final ctx = _paragraphKeys[paraIndex].currentContext;
      _logJump('postFrame attempt=$attempt paraIndex=$paraIndex '
          'ctxBuilt=${ctx != null} pixels=${_scrollController.position.pixels} '
          'maxExtent=${_scrollController.position.maxScrollExtent}');
      if (ctx != null) {
        // 目标段落已构建，用无动画 ensureVisible 精确对齐到视口顶部，
        Scrollable.ensureVisible(
          ctx,
          duration: Duration.zero,
          alignment: 0.0,
        );
        _logJump('ensureVisible called paraIndex=$paraIndex');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final ctx2 = _paragraphKeys[paraIndex].currentContext;
          if (ctx2 == null) return;
          final box = ctx2.findRenderObject() as RenderBox?;
          if (box == null) return;
          final top = box.localToGlobal(Offset.zero).dy;
          final expectedTop = MediaQuery.of(context).padding.top + 60;
          _logJump('verify paraIndex=$paraIndex top=$top '
              'viewportTop=$expectedTop pixels=${_scrollController.position.pixels}');
          final diff = top - expectedTop;
          if (diff.abs() > 100 && attempt < 3) {
            _logJump('verify mismatch, correct by $diff attempt=${attempt + 1}');
            // 用实测偏差精确修正（注意方向）：
            final current = _scrollController.position.pixels;
            _scrollController.jumpTo(
                (current + diff).clamp(0.0, _scrollController.position.maxScrollExtent));
            _currentVisibleParagraph = paraIndex;
            _scrollProgress = (paraIndex / _paragraphs.length).clamp(0.0, 1.0);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              final ctx3 = _paragraphKeys[paraIndex].currentContext;
              if (ctx3 == null) return;
              final box3 = ctx3.findRenderObject() as RenderBox?;
              if (box3 == null) return;
              final top3 = box3.localToGlobal(Offset.zero).dy;
              final diff2 = top3 - expectedTop;
              _logJump('verify2 paraIndex=$paraIndex top=$top3 diff=$diff2');
              if (diff2.abs() > 100 && attempt + 1 < 3) {
                final cur2 = _scrollController.position.pixels;
                _scrollController.jumpTo(
                    (cur2 + diff2).clamp(0.0, _scrollController.position.maxScrollExtent));
              }
            });
          } else {
            _currentVisibleParagraph = paraIndex;
            _scrollProgress = (paraIndex / _paragraphs.length).clamp(0.0, 1.0);
            _currentCharIndex =
                _paragraphOffsets.length > paraIndex ? _paragraphOffsets[paraIndex] : _currentCharIndex;
          }
        });
      } else if (attempt < 5) {
        // 用当前实际位置与目标的段落距离精确修正偏移（不再盲目加屏），
        _logJump('ctx not built, correct by para distance attempt=${attempt + 1}');
        final currentPara = _paragraphIndexAtOffset(_scrollController.offset);
        final paraDiff = paraIndex - currentPara;
        final currentPixel = _scrollController.position.pixels;
        final avgParaHeight = _paragraphHeights.isNotEmpty
            ? (_paragraphHeights.reduce((a, b) => a + b) / _paragraphHeights.length) + 12
            : _scrollController.position.viewportDimension;
        final correction = paraDiff.abs() >= 3
            ? paraDiff * avgParaHeight
            : _scrollController.position.viewportDimension * 0.5;
        _scrollController.jumpTo((currentPixel + correction)
            .clamp(0.0, _scrollController.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _jumpToParagraph(paraIndex, attempt + 1);
        });
      } else {
        _logJump('retry exhausted attempt=$attempt paraIndex=$paraIndex');
      }
    });
  }

  void _toggleTts() {
    setState(() => _isTtsPlaying = !_isTtsPlaying);
    if (_isTtsPlaying) {
      _startTts();
    } else {
      _stopTts();
    }
  }

  void _startTts() async {
    final ttsService = TtsService();
    final voiceProvider = Provider.of<VoiceProvider>(context, listen: false);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final currentVoice = voiceProvider.currentVoice;

    if (currentVoice != null) {
      await ttsService.setVoice(currentVoice);
      // 应用设置中的默认朗读速度
      await ttsService.setSpeed(appProvider.config.ttsDefaultSpeed);
    }

    _ttsLines = _pageTtsLines();
    if (_ttsLines.isEmpty) {
      _stopTts();
      return;
    }
    await ttsService.speak(_applyBlockedWords(_ttsLines[0]), startPosition: 0);
    if (mounted) setState(() => _currentTtsParagraph = 0);
    // 滑动窗口预取第 6 段
    if (_ttsLines.length > 5) {
      ttsService.prefetch(_applyBlockedWords(_ttsLines[5]));
    }
    if (currentVoice?.type == VoiceType.ai) {
      // AI 音色是网络异步合成，需要等待播放真正开始（最长 20 秒），不能立即回退
      for (var i = 0; i < 40; i++) {
        if (ttsService.state == TtsState.playing) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (ttsService.state != TtsState.playing) {
      debugPrint('[TTS] _startTts: state=${ttsService.state} not playing, fallback to system');
      await ttsService.setVoice(VoiceProfile(
        id: 'system_fallback',
        name: '系统音色',
        type: VoiceType.system,
        language: 'zh-CN',
        speed: 1.0,
        pitch: 1.0,
      ));
    await ttsService.speak(_applyBlockedWords(_ttsLines[0]), startPosition: 0);
    }
    if (ttsService.state != TtsState.playing) {
      debugPrint('[TTS] _startTts: still not playing, stop');
      _stopTts();
      return;
    }
    if (mounted) setState(() {});
  }

  /// 从指定行开始朗读（点段落播放）
  void _startTtsFromParagraph(int lineIndex, List<String> lines) {
    _ttsLines = lines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (_ttsLines.isEmpty) return;
    final startLine = lineIndex.clamp(0, _ttsLines.length - 1).toInt();
    final charPos = (_currentCharIndex +
            lines.take(startLine).fold(0, (sum, l) => sum + l.length + 1))
        .toInt();
    final targetPage = _pageIndexForChar(charPos);

    setState(() {
      _currentPage = targetPage.clamp(0, _pages.length - 1).toInt();
      _currentCharIndex = charPos;
      _currentTtsParagraph = startLine;
      _isTtsPlaying = true;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentPage);
    }

    final ttsService = TtsService();
    ttsService.speak(_applyBlockedWords(_ttsLines[startLine]),
        startPosition: 0);
    // 滑动窗口预取
    final target = startLine + 5;
    if (target < _ttsLines.length) {
      ttsService.prefetch(_applyBlockedWords(_ttsLines[target]));
    }
  }

  int _findParagraphIndex(int charIndex) {
    if (_paragraphOffsets.length == _paragraphs.length) {
      int lo = 0, hi = _paragraphOffsets.length - 1;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        if (_paragraphOffsets[mid] <= charIndex) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      return lo;
    }
    int pos = 0;
    for (int i = 0; i < _paragraphs.length; i++) {
      pos += _paragraphs[i].length + 2;
      if (pos > charIndex) return i;
    }
    return 0;
  }

  void _stopTts() {
    TtsService().stop();
    setState(() {
      _isTtsPlaying = false;
      _currentTtsParagraph = -1;
      _ttsLines = [];
    });
  }

  void _exitReader() {
    _stopTts();
    _saveProgress();
    Navigator.pop(context);
  }
}

/// 使用 Listener 监听原始指针事件，区分点击和拖动
class _TapToToggle extends StatefulWidget {
  final VoidCallback onToggle;

  const _TapToToggle({required this.onToggle});

  @override
  State<_TapToToggle> createState() => _TapToToggleState();
}

class _TapToToggleState extends State<_TapToToggle> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.onToggle(),
      child: const SizedBox.expand(),
    );
  }
}

/// 后台 isolate 分割任务参数
class _SplitTask {
  final String text;
  final int pageSize;
  final bool scrollMode;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final double viewportWidth;
  final double viewportHeight;
  final double actualLineHeight;
  final List<int> chapterStartOffsets;
  final List<String> chapterTitles;
  final List<double>? measuredHeights;
  //  - 每页末尾是完整行（不会半行截断、标点单独成行）
  //  - 截断处是自然行尾，下一页从新行继续（阅读连续）
  final List<List<int>>? paragraphLineBreaks;

  const _SplitTask(
    this.text,
    this.pageSize,
    this.scrollMode,
    this.fontSize,
    this.lineHeight,
    this.fontFamily,
    this.viewportWidth,
    this.viewportHeight,
    this.actualLineHeight,
    this.chapterStartOffsets,
    this.chapterTitles,
    this.measuredHeights,
    this.paragraphLineBreaks,
  );
}

/// 后台 isolate 分割结果
class _SplitResult {
  final List<String> pages;
  final List<String> paragraphs;
  final List<double> paragraphHeights;
  final List<int> paragraphOffsets;
  final List<int> pageStartPara;
  final List<int> pageStartChar;

  const _SplitResult(
    this.pages,
    this.paragraphs,
    this.paragraphHeights,
    this.paragraphOffsets,
    this.pageStartPara,
    this.pageStartChar,
  );
}

_SplitResult _splitTextInIsolate(_SplitTask task) {
  final paragraphs = <String>[];
  for (final raw in task.text.split(RegExp(r'\n\s*\n'))) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    if (RegExp(r'^[-=—_]{4,}$').hasMatch(t)) continue;
    final clean = raw.replaceAll('\r', '');
    if (clean.trim().isEmpty) continue;
    // 超长段落（在线识别正文常见：段落间只有单 \n 无空行分隔，
    // 整章/大半章被合并成一段）按行切分为自然段，否则朗读高亮会覆盖整页。
    if (clean.length > 500 && clean.contains('\n')) {
      for (final line in clean.split('\n')) {
        if (line.trim().isNotEmpty) paragraphs.add(line.trim());
      }
    } else {
      paragraphs.add(clean);
    }
  }

    final paragraphOffsets = <int>[];
  {
    final crPrefix = List<int>.filled(task.text.length + 1, 0);
    for (int k = 0; k < task.text.length; k++) {
      crPrefix[k + 1] = crPrefix[k] + (task.text.codeUnitAt(k) == 13 ? 1 : 0);
    }
    final noCrText = task.text.replaceAll('\r', '');
    int searchFrom = 0;
    int searchFromNoCr = 0;
    for (final p in paragraphs) {
      int idx = task.text.indexOf(p, searchFrom);
      if (idx < 0) {
        final noCrIdx = noCrText.indexOf(p, searchFromNoCr);
        idx = noCrIdx < 0 ? -1 : noCrIdx + crPrefix[noCrIdx];
      }
      paragraphOffsets.add(idx);
      if (idx < 0) {
        searchFromNoCr = noCrText.indexOf(p, 0) + p.length;
      } else {
        searchFrom = idx + p.length;
        searchFromNoCr = idx - crPrefix[idx] + p.length;
      }
    }
  }

  final lineHeight = task.actualLineHeight;
  final heights = <double>[];
  if (task.measuredHeights != null &&
      task.measuredHeights!.length == paragraphs.length) {
    heights.addAll(task.measuredHeights!);
  } else {
    const horizontalPadding = 40;
    final maxLineWidth = task.viewportWidth - horizontalPadding;
    for (final p in paragraphs) {
      final textWidth = _estimateTextWidth(p, task.fontSize);
      final lines = task.scrollMode
          ? (textWidth / maxLineWidth).ceil().clamp(1, 100000)
          : ((textWidth / maxLineWidth).ceil() + 1).clamp(1, 100000);
      heights.add(lines * lineHeight);
    }
  }

  // 翻页模式：按段落实际渲染高度打包页面，使每页内容恰好填满一屏，
  final pages = <String>[];
  final pageStartPara = <int>[];
  final pageStartChar = <int>[];

  String cleanPageText(String raw) {
    var t = raw;
    while (t.startsWith('\n')) {
      t = t.substring(1);
    }
    while (t.endsWith('\n')) {
      t = t.substring(0, t.length - 1);
    }
    // 去掉末尾的空白行（\n\n + 可选空白）
    t = t.replaceAll(RegExp(r'(\n\s*)+$'), '');
    return t;
  }

  if (!task.scrollMode && task.viewportHeight > 0) {
    // 与渲染精确匹配，避免低估导致页面最后一行溢出被裁（半截字）
    final paraMargin = lineHeight * 1.5;
    final pageHeight = task.viewportHeight;
    final safePageHeight = pageHeight - lineHeight * 0.3;
    final chapterTitleSet = task.chapterTitles.toSet();

    int i = 0;
    while (i < paragraphs.length) {
      final pageStart = i;
      double used = 0;
      int j = i;
      // 累积当前页可容纳的完整段落：[pageStart, j)
      for (; j < paragraphs.length; j++) {
        final isFirst = (j == pageStart);
        final h = heights[j] + (isFirst ? 0 : paraMargin);
        final isChapterStart = chapterTitleSet.contains(paragraphs[j].trim());
        if (h > pageHeight && paragraphs[j].length > 20) break;
        if (j > pageStart && (used + h > safePageHeight || isChapterStart)) break;
        used += h;
      }

      if (j < paragraphs.length &&
          paragraphs[j].length > 20 &&
          heights[j] + (j == pageStart ? 0 : paraMargin) > pageHeight) {
        // 若当前页只有章节标题段（超长正文紧跟标题），把标题并入超长段
        if (j == pageStart + 1 &&
            chapterTitleSet.contains(paragraphs[pageStart].trim())) {
          final breaks2 = (task.paragraphLineBreaks != null &&
                  j < task.paragraphLineBreaks!.length)
              ? task.paragraphLineBreaks![j]
              : null;
          final totalChars2 = paragraphs[j].length;
          final paraHeight2 = heights[j];
          final charsPerPage2 = paraHeight2 > 0
              ? (totalChars2 * (safePageHeight - lineHeight) / paraHeight2).ceil().clamp(1, totalChars2)
              : totalChars2;
          final firstEnd =
              (0 + charsPerPage2).clamp(1, totalChars2);
          pages.add(cleanPageText(
              '${paragraphs[pageStart]}\n\n${paragraphs[j].substring(0, firstEnd)}'));
          pageStartPara.add(pageStart);
          pageStartChar.add(paragraphOffsets[pageStart]);
          var offset2 = firstEnd;
          if (breaks2 != null && breaks2.isNotEmpty) {
            final maxLineWidth2 = task.viewportWidth - 40;
            final linesPerPage =
                ((safePageHeight - lineHeight) / lineHeight).floor().clamp(1, 100000);
            final startLine = (firstEnd == 0)
                ? 0
                : breaks2.indexWhere((b) => b > firstEnd).clamp(0, breaks2.length - 1);
            var lineIdx = startLine;
            while (lineIdx < breaks2.length) {
              var endLine =
                  (lineIdx + linesPerPage).clamp(lineIdx + 1, breaks2.length);
            while (endLine < breaks2.length && endLine > lineIdx + 1) {
              final prev = breaks2[endLine - 2];
              final end = breaks2[endLine - 1];
              if (prev > end) break;
              final lastLine = paragraphs[j].substring(prev, end).trim();
              if (lastLine.isEmpty) {
                endLine = endLine - 1;
                continue;
              }
              final isShort = lastLine.length <= 2 ||
                  _estimateTextWidth(lastLine, task.fontSize) <
                      maxLineWidth2 * 0.5;
              final endsSentence = RegExp(r'[。！？…”』」]').hasMatch(lastLine);
              if (!isShort && endsSentence) {
                break;
              }
              endLine = endLine - 1;
            }
              final endChar = breaks2[endLine - 1];
              final startChar = lineIdx == startLine ? firstEnd : breaks2[lineIdx - 1];
              final cutStart = startChar.clamp(0, paragraphs[j].length);
              final cutEnd = endChar.clamp(cutStart, paragraphs[j].length);
              final text = paragraphs[j].substring(cutStart, cutEnd);
              pages.add(cleanPageText(text));
              pageStartPara.add(j);
              pageStartChar.add(paragraphOffsets[j] + (lineIdx == startLine ? firstEnd : breaks2[lineIdx - 1]));
              lineIdx = endLine;
            }
          } else {
            while (offset2 < totalChars2) {
              final end2 = (offset2 + charsPerPage2).clamp(offset2 + 1, totalChars2);
              pages.add(cleanPageText(paragraphs[j].substring(offset2, end2)));
              pageStartPara.add(j);
              pageStartChar.add(paragraphOffsets[j] + offset2);
              offset2 = end2;
            }
          }
          i = j + 1;
          continue;
        }
        if (j > pageStart) {
          pages.add(cleanPageText(paragraphs.sublist(pageStart, j).join('\n\n')));
          pageStartPara.add(pageStart);
          pageStartChar.add(paragraphOffsets[pageStart]);
        }
        final breaks = (task.paragraphLineBreaks != null &&
                j < task.paragraphLineBreaks!.length)
            ? task.paragraphLineBreaks![j]
            : null;
        final totalChars = paragraphs[j].length;
        final paraHeight = heights[j];
        final charsPerPage = paraHeight > 0
            ? (totalChars * (safePageHeight - lineHeight) / paraHeight).ceil().clamp(1, totalChars)
            : totalChars;
        if (breaks != null && breaks.isNotEmpty) {
          final maxLineWidth = task.viewportWidth - 40;
          final linesPerPage =
              ((safePageHeight - lineHeight) / lineHeight).floor().clamp(1, 100000);
          var lineIdx = 0;
          var lastChar = 0;
          while (lineIdx < breaks.length) {
            var endLine = (lineIdx + linesPerPage).clamp(lineIdx + 1, breaks.length);
            while (endLine < breaks.length && endLine > lineIdx + 1) {
              final prev = breaks[endLine - 2];
              final end = breaks[endLine - 1];
              if (prev > end) break;
              final lastLine = paragraphs[j].substring(prev, end).trim();
              if (lastLine.isEmpty) {
                endLine = endLine - 1;
                continue;
              }
              final isShort = lastLine.length <= 2 ||
                  _estimateTextWidth(lastLine, task.fontSize) <
                      maxLineWidth * 0.5;
              final endsSentence = RegExp(r'[。！？…”』」]').hasMatch(lastLine);
              if (!isShort && endsSentence) {
                break;
              }
              endLine = endLine - 1;
            }
            final endChar = breaks[endLine - 1];
            pages.add(cleanPageText(paragraphs[j].substring(lastChar, endChar)));
            pageStartPara.add(j);
            pageStartChar.add(paragraphOffsets[j] + lastChar);
            lastChar = endChar;
            lineIdx = endLine;
          }
        } else {
          var offset = 0;
          while (offset < totalChars) {
            final end = (offset + charsPerPage).clamp(offset + 1, totalChars);
            pages.add(cleanPageText(paragraphs[j].substring(offset, end)));
            pageStartPara.add(j);
            pageStartChar.add(paragraphOffsets[j] + offset);
            offset = end;
          }
        }
        i = j + 1;
        continue;
      }

      if (j < paragraphs.length &&
          j > pageStart &&
          !chapterTitleSet.contains(paragraphs[j].trim())) {
        final remaining = safePageHeight - used;
        if (remaining > lineHeight &&
            heights[j] > lineHeight) {
          final para = paragraphs[j];
          // 可放入的行数（留 0.3 行余量）
          final usable = remaining - lineHeight * 0.3;
          final maxLines = usable > 0 ? (usable / lineHeight).floor() : 0;
          String? prefix;
          String? suffix;
          final breaks = (task.paragraphLineBreaks != null &&
                  j < task.paragraphLineBreaks!.length)
              ? task.paragraphLineBreaks![j]
              : null;
          if (breaks != null && breaks.isNotEmpty && maxLines > 0) {
            int lines = maxLines;
            while (lines > 1 && lines < breaks.length) {
              final maxLineWidth = task.viewportWidth - 40;
              final prev = breaks[lines - 2];
              final end = breaks[lines - 1];
              if (prev > end) break;
              final lastLine = para.substring(prev, end).trim();
              if (lastLine.isEmpty) {
                lines = lines - 1;
                continue;
              }
              final isShort = lastLine.length <= 2 ||
                  _estimateTextWidth(lastLine, task.fontSize) <
                      maxLineWidth * 0.5;
              final endsSentence = RegExp(r'[。！？…”』」]').hasMatch(lastLine);
              if (!isShort && endsSentence) {
                break;
              }
              lines = lines - 1;
            }
            if (lines <= 0) {
            } else if (breaks.length <= lines) {
              prefix = para;
              suffix = null;
            } else {
              final cut = breaks[lines - 1].clamp(1, para.length - 1);
              prefix = para.substring(0, cut);
              suffix = para.substring(cut);
            }
          } else if (maxLines <= 0) {
          } else {
            // 回退：按字符比例切（尽量接近行边界）
            final prefixChars = usable > 0
                ? (para.length * usable / heights[j]).floor().clamp(1, para.length - 1)
                : 1;
            prefix = para.substring(0, prefixChars);
            suffix = para.substring(prefixChars);
          }
          final String pfx =
              prefix == null || prefix.trim().isEmpty ? '' : prefix;
          final String? sfx = suffix;
          if (pfx.isEmpty) {
          } else {
            var pfxClean = pfx;
            while (pfxClean.endsWith('\n')) {
              pfxClean = pfxClean.substring(0, pfxClean.length - 1);
            }
            String? sfxClean = sfx;
            // 后缀开头去换行/空白（避免下一页页头空行）
            while (sfxClean != null && sfxClean.isNotEmpty &&
                (sfxClean.startsWith('\n') || sfxClean.startsWith(' '))) {
              sfxClean = sfxClean.substring(1);
            }
            if (sfxClean != null && sfxClean.isEmpty) {
              // 后缀被清空：整段放当前页（防御）
              sfxClean = null;
            }
            pages.add(cleanPageText(
                '${paragraphs.sublist(pageStart, j).join('\n\n')}\n\n$pfxClean'));
            pageStartPara.add(pageStart);
            pageStartChar.add(paragraphOffsets[pageStart]);
            if (sfxClean == null) {
              i = j + 1;
            } else {
              paragraphs[j] = sfxClean;
              heights[j] = para.isNotEmpty
                  ? heights[j] * sfxClean.length / para.length
                  : 0;
              // 后缀在原文中的真实起点：paragraphs 是去 \r 的文本，pfxClean.length
              var origLen = 0;
              var matched = 0;
              final origStart = paragraphOffsets[j];
              if (origStart >= 0) {
                for (var k = origStart;
                    k < task.text.length && matched < pfxClean.length;
                    k++) {
                  origLen++;
                  if (task.text.codeUnitAt(k) != 13) matched++;
                }
              }
              paragraphOffsets[j] = origStart >= 0 ? origStart + origLen : -1;
              i = j;
            }
            continue;
          }
        }
      }
      final pageText = cleanPageText(paragraphs.sublist(pageStart, j).join('\n\n'));
      pages.add(pageText);
      pageStartPara.add(pageStart);
      pageStartChar.add(paragraphOffsets[pageStart]);
      i = j;
    }
  } else if (!task.scrollMode) {
    for (int i = 0; i < task.text.length; i += task.pageSize) {
      final end = (i + task.pageSize < task.text.length)
          ? i + task.pageSize
          : task.text.length;
      pages.add(task.text.substring(i, end));
    }
    for (int i = 0; i < pages.length; i++) {
      pageStartPara.add(0);
      pageStartChar.add(0);
    }
  }

  // 切点落在段内 \n 前单字上），把它移到下一页开头（与后续内容合并，
  for (var pi = 0; pi < pages.length - 1; pi++) {
    final lines = pages[pi].split('\n');
    if (lines.length < 2) continue;
    final lastLine = lines.last.trim();
    if (lastLine.isEmpty) continue;
    final isOrphan = lastLine.length <= 2 &&
        !RegExp(r'[。！？…”』」]').hasMatch(lastLine);
    if (isOrphan) {
      final next = pages[pi + 1];
      pages[pi] = lines.sublist(0, lines.length - 1).join('\n');
      pages[pi + 1] = '$lastLine${next.isEmpty ? '' : '\n\n$next'}';
    }
  }

  return _SplitResult(
      pages, paragraphs, heights, paragraphOffsets, pageStartPara, pageStartChar);
}
double _estimateTextWidth(String text, double fontSize) {
  double width = 0;
  for (final rune in text.runes) {
    final isFullWidth = (rune >= 0x2E80 && rune <= 0x9FFF) || // CJK 统一表意文字
        (rune >= 0xF900 && rune <= 0xFAFF) || // CJK 兼容表意文字
        (rune >= 0xFF00 && rune <= 0xFFEF) || // 全角标点
        (rune >= 0x3000 && rune <= 0x303F); // CJK 标点
    width += isFullWidth ? fontSize : fontSize / 2 * 1.1;
  }
  return width;
}

/// 章节目录底部弹窗
class _ChapterListSheet extends StatefulWidget {
  final List<Chapter> chapters;
  final int currentChapterIndex;
  final ValueChanged<int> onSelect;

  const _ChapterListSheet({
    required this.chapters,
    required this.currentChapterIndex,
    required this.onSelect,
  });

  @override
  State<_ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends State<_ChapterListSheet> {
  // 是否倒序排列（默认正序）
  bool _descending = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : Colors.white;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final total = widget.chapters.length;

    // 倒序时，显示索引 displayIndex 对应原始索引 total - 1 - displayIndex
    int displayToOriginal(int displayIndex) =>
        _descending ? total - 1 - displayIndex : displayIndex;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded,
                    color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  '目录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 正序/倒序切换按钮
                InkWell(
                  onTap: () => setState(() => _descending = !_descending),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _descending
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _descending ? '倒序' : '正序',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '共 $total 章',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 章节列表
          Expanded(
            child: ListView.builder(
              itemCount: total,
              itemBuilder: (context, displayIndex) {
                final originalIndex = displayToOriginal(displayIndex);
                final isCurrent = originalIndex == widget.currentChapterIndex;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isCurrent
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isCurrent
                        ? AppTheme.primaryColor
                        : AppTheme.textTertiary,
                    size: 18,
                  ),
                  title: Text(
                    widget.chapters[originalIndex].title,
                    style: TextStyle(
                      fontSize: 15,
                      color: isCurrent ? AppTheme.primaryColor : textColor,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () => widget.onSelect(originalIndex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
