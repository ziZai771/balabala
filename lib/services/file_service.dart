import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import 'chapter_service.dart';
import 'http_util.dart';

class FileService {
  static final FileService _instance = FileService._internal();
  factory FileService() => _instance;
  FileService._internal();

  final _uuid = const Uuid();

  /// 选择本地txt文件
  Future<Book?> pickTextFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json', 'xml', 'html', 'srt', 'lrc'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final path = file.path;
        if (path == null) return null;

        final content = await _readFileContent(path);
        final fileName = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        final chapters = ChapterService().parseChapters(content);

        return Book(
          id: _uuid.v4(),
          title: fileName,
          filePath: path,
          source: BookSource.local,
          content: content,
          totalLength: content.length,
          encoding: _detectEncoding(path),
          chapterCount: chapters.length,
          chapters: chapters,
        );
      }
    } catch (e) {
      // 处理错误
    }
    return null;
  }

  /// 读取文件内容
  /// 注意：不能对整份文件用严格 UTF-8 解码——文件尾部若有截断/损坏的
  /// 多字节序列，严格模式会抛 FormatException，回退 latin1 后**整个文件**
  /// 的中文全部乱码。用 allowMalformed 只损坏尾部 1-2 个字符，正文不受影响。
  Future<String> _readFileContent(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();

    // 优先按 UTF-8 解码（宽松模式容忍尾部损坏字节）
    String utf8Content;
    try {
      utf8Content = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      utf8Content = '';
    }

    // UTF-8 解码成功且包含中文 → 直接使用
    if (utf8Content.isNotEmpty && _hasChinese(utf8Content)) {
      return utf8Content;
    }

    // 否则回退 latin1 / 原始字节（纯英文或 GBK 等场景）
    try {
      return latin1.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  /// 判断文本是否包含中文字符
  bool _hasChinese(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        return true;
      }
    }
    return false;
  }

  /// 检测文件编码
  String _detectEncoding(String path) {
    return 'utf-8';
  }

  /// 从URL读取文本内容
  Future<Book?> fetchUrlContent(String url) async {
    try {
      // 规范化URL：缺少协议时自动补全 https://
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      final uri = Uri.parse(url);
      final response = await HttpUtil.get(url);

      if (response.statusCode == 200) {
        String content;
        try {
          content = utf8.decode(response.bodyBytes);
        } catch (_) {
          content = response.body;
        }

        // HTML 页面交给 Readability 提取正文，这里只处理纯文本内容
        if (_isHtmlContent(content)) {
          return null;
        }

        // 检测是否为可读文本
        if (!_isReadableContent(content)) {
          return null;
        }

        final title = _extractTitle(content) ??
            (uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '')
                : '未命名文档');
        final chapters = ChapterService().parseChapters(content);

        return Book(
          id: _uuid.v4(),
          title: title,
          url: url,
          source: BookSource.url,
          content: content,
          totalLength: content.length,
          chapterCount: chapters.length,
          chapters: chapters,
        );
      }
    } catch (e) {
      // 处理错误
    }
    return null;
  }

  /// 判断是否为 HTML 页面内容
  bool _isHtmlContent(String content) {
    final trimmed = content.trimLeft().toLowerCase();
    return trimmed.startsWith('<!doctype') ||
        trimmed.startsWith('<html') ||
        trimmed.contains('<body') ||
        trimmed.contains('<div') ||
        trimmed.contains('<p>');
  }

  /// 判断是否为可读文本内容
  bool _isReadableContent(String content) {
    if (content.isEmpty) return false;

    // 计算中文字符比例
    int chineseChars = 0;
    int totalChars = content.length;

    for (final rune in content.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        chineseChars++;
      }
    }

    final chineseRatio = chineseChars / totalChars;

    // 如果中文字符占比超过10%，认为是可读文本
    // 或者总字符数超过500且包含段落结构
    if (chineseRatio > 0.1) return true;
    if (totalChars > 500 && content.contains('\n\n')) return true;

    return false;
  }

  /// 从内容中提取标题
  String? _extractTitle(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && trimmed.length < 100) {
        // 检查是否像标题（不包含标点符号的短行）
        if (!trimmed.contains('。') &&
            !trimmed.contains('，') &&
            !trimmed.contains('？')) {
          return trimmed;
        }
      }
    }
    return null;
  }

  /// 保存书籍封面到本地
  Future<String?> saveCover(String url) async {
    try {
      final response = await HttpUtil.get(url);
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final coverDir = Directory('${dir.path}/covers');
        if (!await coverDir.exists()) {
          await coverDir.create(recursive: true);
        }
        final filePath = '${coverDir.path}/${_uuid.v4()}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }
    } catch (e) {
      // 静默失败
    }
    return null;
  }

  /// 导出配置到文件
  Future<String?> exportConfig(String jsonData) async {
    try {
      final result = await FilePicker.saveFile(
        dialogTitle: '导出配置',
        fileName: 'balabala_config.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        // file_picker 11+ 在 Android/iOS 必须提供 bytes，插件负责写入文件
        bytes: utf8.encode(jsonData),
      );

      if (result != null) {
        return result;
      }
    } catch (e) {
      // 处理错误
    }
    return null;
  }

  /// 从文件导入配置
  Future<String?> importConfig() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          final file = File(path);
          return await file.readAsString();
        }
      }
    } catch (e) {
      // 处理错误
    }
    return null;
  }
}
