/// 章节信息
class Chapter {
  final String title;
  final int startIndex; // 章节标题在全文中的起始字符位置
  final String? url; // 在线阅读时该章节对应的线上 URL

  const Chapter({
    required this.title,
    required this.startIndex,
    this.url,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'startIndex': startIndex,
    'url': url,
  };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
    title: map['title'] ?? '',
    startIndex: map['startIndex'] ?? 0,
    url: map['url'],
  );
}
