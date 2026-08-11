class ReadingHistory {
  final String id;
  String bookId;
  String bookTitle;
  int position;
  int durationSeconds;
  DateTime readAt;

  ReadingHistory({
    required this.id,
    required this.bookId,
    this.bookTitle = '',
    this.position = 0,
    this.durationSeconds = 0,
    DateTime? readAt,
  }) : readAt = readAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id, 'bookId': bookId, 'bookTitle': bookTitle,
    'position': position, 'durationSeconds': durationSeconds,
    'readAt': readAt.toIso8601String(),
  };

  factory ReadingHistory.fromMap(Map<String, dynamic> map) => ReadingHistory(
    id: map['id'] ?? '',
    bookId: map['bookId'] ?? '',
    bookTitle: map['bookTitle'] ?? '',
    position: map['position'] ?? 0,
    durationSeconds: map['durationSeconds'] ?? 0,
    readAt: DateTime.tryParse(map['readAt'] ?? '') ?? DateTime.now(),
  );
}
