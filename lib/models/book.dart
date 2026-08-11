import 'chapter.dart';

class Book {
  final String id;
  String title;
  String author;
  String coverPath;
  String filePath;
  BookSource source;
  String content;
  int currentPosition;
  int totalLength;
  DateTime addedAt;
  DateTime lastReadAt;
  bool isInBookshelf;
  String encoding;
  String url;
  int chapterCount;
  int currentChapter;
  List<Chapter> chapters;
  // 本书的屏蔽词列表（阅读设置中添加，上限 10 个、每个限长 50 字）。
  // 阅读时正文中的屏蔽词会被等长替换为 *（保持字符偏移，不影响进度/TTS 定位）。
  List<String> blockedWords;

  Book({
    required this.id,
    this.title = '',
    this.author = '',
    this.coverPath = '',
    this.filePath = '',
    this.source = BookSource.local,
    this.content = '',
    this.currentPosition = 0,
    this.totalLength = 0,
    DateTime? addedAt,
    DateTime? lastReadAt,
    this.isInBookshelf = false,
    this.encoding = 'utf-8',
    this.url = '',
    this.chapterCount = 0,
    this.currentChapter = 0,
    List<Chapter>? chapters,
    List<String>? blockedWords,
  })  : addedAt = addedAt ?? DateTime.now(),
        lastReadAt = lastReadAt ?? DateTime.now(),
        chapters = chapters ?? [],
        blockedWords = blockedWords ?? [];

  Map<String, dynamic> toMap() => {
    'id': id, 'title': title, 'author': author,
    'coverPath': coverPath, 'filePath': filePath,
    'source': source.index, 'content': content,
    'currentPosition': currentPosition, 'totalLength': totalLength,
    'addedAt': addedAt.toIso8601String(),
    'lastReadAt': lastReadAt.toIso8601String(),
    'isInBookshelf': isInBookshelf, 'encoding': encoding,
    'url': url, 'chapterCount': chapterCount,
    'currentChapter': currentChapter,
    'chapters': chapters.map((c) => c.toMap()).toList(),
    'blockedWords': blockedWords,
  };

  factory Book.fromMap(Map<String, dynamic> map) => Book(
    id: map['id'] ?? '',
    title: map['title'] ?? '',
    author: map['author'] ?? '',
    coverPath: map['coverPath'] ?? '',
    filePath: map['filePath'] ?? '',
    source: BookSource.values[map['source'] ?? 0],
    content: map['content'] ?? '',
    currentPosition: map['currentPosition'] ?? 0,
    totalLength: map['totalLength'] ?? 0,
    addedAt: DateTime.tryParse(map['addedAt'] ?? '') ?? DateTime.now(),
    lastReadAt: DateTime.tryParse(map['lastReadAt'] ?? '') ?? DateTime.now(),
    isInBookshelf: map['isInBookshelf'] ?? false,
    encoding: map['encoding'] ?? 'utf-8',
    url: map['url'] ?? '',
    chapterCount: map['chapterCount'] ?? 0,
    currentChapter: map['currentChapter'] ?? 0,
    chapters: (map['chapters'] as List? ?? [])
        .map((e) => Chapter.fromMap(e))
        .toList(),
    blockedWords: (map['blockedWords'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
  );
}

enum BookSource { local, url }
