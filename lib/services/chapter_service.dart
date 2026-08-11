import '../models/chapter.dart';

/// 章节解析服务：从书籍全文内容中识别章节标题并生成章节索引
class ChapterService {
  static final ChapterService _instance = ChapterService._internal();
  factory ChapterService() => _instance;
  ChapterService._internal();

  /// 匹配常见章节标题的正则：
  /// - 第X章 / 第X节 / 第X卷 / 第X回 / 第X话 / 第X篇 / 第X部
  /// - 支持中文数字（一二三...）和阿拉伯数字
  /// - 标题行通常独立成行，且较短
  static final RegExp _chapterPattern = RegExp(
    r'^\s*(第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章节卷回话篇部集])\s*[：:、.\s]*(.*)$',
  );

  /// 解析全文，返回章节列表。
  /// 若未识别到任何章节，返回空列表。
  ///
  /// 会跳过书籍开头的目录（TOC）块：目录中的章节标题连续出现（相邻标题
  /// 之间仅隔 0~1 个空行），且数量 >= 2。若开头没有这样的目录块，则所有
  /// 标题行都视为正文章节。这样每个章节的 startIndex 指向正文中的真实位置，
  /// 而不是目录条目。
  List<Chapter> parseChapters(String content) {
    if (content.isEmpty) return [];

    final chapters = <Chapter>[];
    final lines = content.split('\n');

    // 第一步：判断开头是否存在目录块。
    // 目录块 = 开头连续出现的标题行（相邻标题行间隔 <= 2 行），且数量 >= 2。
    // 只扫描文件**开头 500 行**：真实目录表都在文件头部；正文中偶尔出现的
    // 标题样式行（如章节引用、作者感言）散布全书，扫描全文会把它们误判成
    // "目录块"并跳过后续所有章节（20MB 大书实测丢几百章）。
    // 同时，正文中重复引用的标题行（与相邻章节标题相同）不作为目录条目。
    const tocScanLimit = 500;
    int tocEndLine = 0; // 目录块结束后的第一个正文行号
    int titleRun = 0; // 当前连续标题行计数
    int lastTitleLine = -1;
    String lastTitleFull = '';
    bool inToc = false;

    final scanEnd = lines.length < tocScanLimit ? lines.length : tocScanLimit;
    for (int i = 0; i < scanEnd; i++) {
      final trimmed = lines[i].trim();
      final isTitle = _chapterPattern.firstMatch(trimmed) != null;

      if (isTitle) {
        // 归一化（压缩内部连续空格）后与相邻章节标题比较，
        // 识别正文中的重复引用行（如"第五百五十四章  叶遮天"双空格变体）
        final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
        final lastNormalized = lastTitleFull.replaceAll(RegExp(r'\s+'), ' ');
        final isDuplicateRef = lastTitleLine != -1 &&
            (i - lastTitleLine) <= 2 &&
            normalized == lastNormalized;
        if (isDuplicateRef) {
          // 正文中重复引用的标题行（与相邻章节标题完全相同）→ 视为正文，重置序列
          titleRun = 0;
          lastTitleLine = -1;
          lastTitleFull = '';
          continue;
        }
        if (lastTitleLine == -1 || (i - lastTitleLine) <= 2) {
          // 属于当前连续标题行序列
          titleRun++;
        } else {
          // 出现较大间隔：标题行序列中断
          if (titleRun >= 2) {
            // 已识别到目录块，结束扫描
            tocEndLine = i;
            inToc = true;
            break;
          }
          // 不是目录，重置计数继续
          titleRun = 1;
        }
        lastTitleLine = i;
        lastTitleFull = trimmed;
      } else if (trimmed.isNotEmpty) {
        // 遇到正文行（非标题、非空行）
        if (titleRun >= 2) {
          // 已识别到目录块，结束扫描
          tocEndLine = i;
          inToc = true;
          break;
        }
        // 标题行序列太短，不是目录，重置计数
        titleRun = 0;
        lastTitleLine = -1;
        lastTitleFull = '';
      }
      // 空行：不改变状态，继续
    }

    // 若扫描到文件末尾仍未识别出目录块，则视为无目录
    if (!inToc) {
      tocEndLine = 0;
    }

    // 第二步：从目录块之后开始记录正文章节
    int charOffset = 0;
    for (int i = 0; i < lines.length; i++) {
      if (i >= tocEndLine) {
        final trimmed = lines[i].trim();
        final match = _chapterPattern.firstMatch(trimmed);
        if (match != null) {
          // 章节标题：保留完整标题（如"第十三章：海流氓与计划"）
          chapters.add(Chapter(title: trimmed, startIndex: charOffset));
        }
      }
      // 累加字符偏移（含换行符）
      charOffset += lines[i].length + 1;
    }

    return chapters;
  }

  /// 根据字符位置查找所在章节索引。
  /// 返回章节在列表中的下标；若位置在第一章之前或没有章节，返回 0。
  int findChapterIndex(List<Chapter> chapters, int charIndex) {
    if (chapters.isEmpty) return 0;
    int result = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (chapters[i].startIndex <= charIndex) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }
}
