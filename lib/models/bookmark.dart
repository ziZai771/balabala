class Bookmark {
  final String id;
  String bookId;
  int position;
  String text;
  String note;
  DateTime createdAt;
  int chapterIndex;

  Bookmark({
    required this.id,
    required this.bookId,
    required this.position,
    this.text = '',
    this.note = '',
    DateTime? createdAt,
    this.chapterIndex = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id, 'bookId': bookId, 'position': position,
    'text': text, 'note': note,
    'createdAt': createdAt.toIso8601String(),
    'chapterIndex': chapterIndex,
  };

  factory Bookmark.fromMap(Map<String, dynamic> map) => Bookmark(
    id: map['id'] ?? '',
    bookId: map['bookId'] ?? '',
    position: map['position'] ?? 0,
    text: map['text'] ?? '',
    note: map['note'] ?? '',
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    chapterIndex: map['chapterIndex'] ?? 0,
  );
}
