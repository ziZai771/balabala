import '../models/chapter.dart';

/// 从章节标题中解析章节号（如"第123章 xxx" → 123）。
/// 支持阿拉伯数字和中文数字。解析失败返回 null。
int? extractChapterNumber(String title) {
  // 阿拉伯数字：第123章 / 第123节 / 123章
  final arabic = RegExp(r'第\s*(\d+)\s*[章节卷回话篇部集]').firstMatch(title);
  if (arabic != null) {
    return int.tryParse(arabic.group(1)!);
  }
  final arabic2 = RegExp(r'^\s*(\d+)\s*[章节回话]').firstMatch(title);
  if (arabic2 != null) {
    return int.tryParse(arabic2.group(1)!);
  }
  // 中文数字：第十二章
  final chinese = RegExp(r'第\s*([零一二三四五六七八九十百千万两]+)\s*[章节卷回话篇部集]').firstMatch(title);
  if (chinese != null) {
    return chineseToInt(chinese.group(1)!);
  }
  return null;
}

/// 中文数字转阿拉伯数字（支持到万）。
int? chineseToInt(String s) {
  const digits = {
    '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  const units = {'十': 10, '百': 100, '千': 1000, '万': 10000};

  int result = 0;
  int section = 0;
  int number = 0;
  for (final ch in s.split('')) {
    if (digits.containsKey(ch)) {
      number = digits[ch]!;
    } else if (units.containsKey(ch)) {
      final unit = units[ch]!;
      if (unit == 10000) {
        section = (section + number) * unit;
        result += section;
        section = 0;
      } else {
        section += (number == 0 ? 1 : number) * unit;
      }
      number = 0;
    }
  }
  result += section + number;
  return result;
}

/// 按章节号对章节列表排序（正序，第一章在最前）。
/// 无法解析章节号的章节保持原相对顺序。
void sortChaptersByNumber(List<Chapter> chapters) {
  chapters.sort((a, b) {
    final na = extractChapterNumber(a.title);
    final nb = extractChapterNumber(b.title);
    if (na != null && nb != null) {
      return na.compareTo(nb);
    }
    // 无法解析章节号时保持原顺序
    return 0;
  });
}
