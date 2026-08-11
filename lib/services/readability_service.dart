import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/chapter.dart';
import '../utils/chapter_number.dart';
import 'http_util.dart';

class ReadabilityResult {
  final String title;
  final String content;
  final String? author;
  final DateTime? publishDate;
  final String? excerpt;
  final String? featuredImage;

  ReadabilityResult({
    required this.title,
    required this.content,
    this.author,
    this.publishDate,
    this.excerpt,
    this.featuredImage,
  });
}

class ReadabilityService {
  static final ReadabilityService _instance = ReadabilityService._internal();
  factory ReadabilityService() => _instance;
  ReadabilityService._internal();

  /// 从URL提取正文内容
  Future<ReadabilityResult?> extractFromUrl(String url) async {
    try {
      // 规范化URL：缺少协议时自动补全 https://
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      final response = await HttpUtil.get(url);

      if (response.statusCode == 200) {
        return _extractFromHtml(HttpUtil.decodeBody(response), url);
      }
    } catch (e) {
      // 处理错误
    }
    return null;
  }

  /// 从HTML中提取正文
  ReadabilityResult? _extractFromHtml(String html, String url) {
    try {
      final document = html_parser.parse(html);
      
      // 移除无用元素
      _removeElements(document, 'script, style, nav, footer, header, aside, '
          '.sidebar, .ad, .advertisement, .menu, .comment, .comments, '
          '[role="navigation"], [role="banner"], [role="complementary"]');

      // 提取标题
      String title = _extractTitle(document) ?? '';

      // 提取正文
      String content = _extractContent(document);

      // 提取作者
      String? author = _extractMeta(document, 'author');

      // 提取发布日期
      DateTime? publishDate = _extractPublishDate(document);

      // 提取摘要
      String? excerpt = _extractMeta(document, 'description');

      // 提取特色图片
      String? featuredImage = _extractFeaturedImage(document);

      if (content.isEmpty) {
        return null;
      }

      return ReadabilityResult(
        title: title,
        content: content,
        author: author,
        publishDate: publishDate,
        excerpt: excerpt,
        featuredImage: featuredImage,
      );
    } catch (e) {
      return null;
    }
  }

  void _removeElements(html_dom.Document document, String selector) {
    final elements = document.querySelectorAll(selector);
    for (final element in elements) {
      element.remove();
    }
  }

  String? _extractTitle(html_dom.Document document) {
    // 尝试多种方式获取标题
    final ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle != null) {
      return ogTitle.attributes['content'];
    }

    final h1 = document.querySelector('h1');
    if (h1 != null && h1.text.trim().isNotEmpty) {
      return h1.text.trim();
    }

    final titleTag = document.querySelector('title');
    if (titleTag != null) {
      String t = titleTag.text.trim();
      // 移除站点名称后缀
      final separators = [' - ', ' — ', ' – ', ' | ', ' :: '];
      for (final sep in separators) {
        if (t.contains(sep)) {
          t = t.split(sep).first.trim();
        }
      }
      return t;
    }

    return null;
  }

  String _extractContent(html_dom.Document document) {
    // 尝试多种正文选择器。笔趣阁等小说站正文容器通常是 #chaptercontent / .content / #content。
    final selectors = [
      '#chaptercontent',
      '#chapterContent',
      '.chapter-content',
      '.chapter_content',
      '.read-content',
      '.content',
      '#content',
      '.article-content',
      '.entry-content',
      '.post-content',
      'article',
      '[role="main"]',
      '.post',
      '.article',
      'main',
    ];

    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) {
        final text = _extractTextWithBreaks(element);
        if (text.length > 200) {
          return _cleanText(text);
        }
      }
    }

    // 部分站点（如 52bqg）用 base64 编码正文（形如 <p>5L2g5aW9...</p>，
    // 页面加载时由 JS 解码渲染）。此时 DOM 里看不到正文文字，
    // 直接提取 base64 串解码还原正文。
    final base64Text = _extractBase64Content(document);
    if (base64Text != null) {
      return _cleanText(base64Text);
    }

    // 如果找不到特定容器，尝试提取body中所有段落。
    // 优先用 <p> 段落；若 <p> 太少（正文可能用 <br> 分隔），
    // 则退化为提取 body 中所有文本，由 _cleanText 把 <br> 转为换行。
    final paragraphs = document.querySelectorAll('p');
    final buffer = StringBuffer();
    for (final p in paragraphs) {
      final text = p.text.trim();
      // 过滤掉广告/提示文字（如"一秒记住【笔趣阁】"、"更新快，无弹窗"等）
      if (text.length > 20 && !_isAdText(text)) {
        buffer.writeln(text);
        buffer.writeln();
      }
    }

    // 若 <p> 段落过少，说明正文可能用 <br> 分隔，直接取 body 文本
    if (buffer.length < 200) {
      final body = document.body;
      if (body != null) {
        return _cleanText(_extractTextWithBreaks(body));
      }
    }

    return _cleanText(buffer.toString());
  }

  /// 尝试从页面中提取 base64 编码的正文。
  ///
  /// 部分笔趣阁类站点把正文段落以 base64 形式嵌入 HTML
  /// （解码后为 `<p>...</p>`），由前端 JS 解码渲染。DOM 文本层
  /// 看不到正文，但 HTML 源码里存在大量长 base64 串。
  ///
  /// 策略：收集页面中所有长度 >= 100 的 base64 候选串，逐个解码，
  /// 统计解码后为 `<p>` 开头的 HTML 段落数；段落数 >= 3 且解码后
  /// 总长度 > 200 时认定为正文。
  String? _extractBase64Content(html_dom.Document document) {
    try {
      final html = document.outerHtml;
      final pattern = RegExp('["\']([A-Za-z0-9+/]{100,}={0,2})["\']');
      final matches = pattern.allMatches(html);
      if (matches.isEmpty) return null;

      final buffer = StringBuffer();
      int pCount = 0;
      final base64 = base64Decode;

      for (final m in matches) {
        final candidate = m.group(1)!;
        try {
          final bytes = base64(candidate);
          final text = utf8.decode(bytes, allowMalformed: true);
          // 只接受包含 <p> 标签的 HTML 片段（排除纯文本/JSON等误匹配）
          if (!text.contains('<p')) continue;
          // 过滤"相邻推荐/猜你喜欢"等推荐位区块（章节页底部常见，
          // 也是 base64 编码的 <p> 段落，会被一起解码进来）
          if (text.contains('相邻推荐') ||
              text.contains('猜你喜欢') ||
              text.contains('相关推荐') ||
              text.contains('章节评论')) {
            continue;
          }
          buffer.write(text);
          pCount++;
        } catch (_) {
          // 非合法 base64，跳过
        }
      }

      if (pCount >= 3 && buffer.length > 200) {
        return buffer.toString();
      }
    } catch (_) {}
    return null;
  }

  /// 判断文本是否为广告/提示文字（应过滤掉）。
  bool _isAdText(String text) {
    return text.contains('笔趣阁') ||
        text.contains('一秒记住') ||
        text.contains('更新快') ||
        text.contains('无弹窗') ||
        text.contains('手机阅读') ||
        text.contains('请收藏') ||
        text.contains('加入书架') ||
        text.contains('最新章节') ||
        text.contains('天才一秒记住') ||
        text.contains('记住本站') ||
        // 站点插入的"请关闭浏览器阅读模式/去广告"提示（常出现在正文首段）
        text.contains('请关闭浏览器阅读模式') ||
        text.contains('阅读模式后查看') ||
        text.contains('无法翻页') ||
        text.contains('章节内容丢失');
  }

  /// 提取元素文本，并把 <br> 标签转换为换行（保留段落结构）。
  /// 直接取 element.text 会把 <br> 当作无分隔，导致整章连成一个段落；
  /// 这里遍历子节点，遇到 <br> 时插入换行。
  /// 同时跳过 <a> 标签（网页导航/UI元素大多是 <a>，正文里基本没有链接），
  /// 避免把"上一章/下一章/目录/关灯"等网页UI文字混入正文。
  String _extractTextWithBreaks(html_dom.Element element) {
    final buffer = StringBuffer();
    void walk(html_dom.Node node) {
      if (node is html_dom.Text) {
        buffer.write(node.text);
      } else if (node is html_dom.Element) {
        if (node.localName == 'br') {
          buffer.write('\n');
          return;
        }
        // 跳过 <a> 标签（网页导航/UI元素），避免混入"上一章/下一章/目录"等文字
        if (node.localName == 'a') {
          return;
        }
        // 跳过广告/提示段落（如"一秒记住【笔趣阁】"、"更新快，无弹窗"等）
        if (node.localName == 'p' && _isAdText(node.text)) {
          return;
        }
        // 块级元素（p、div、li 等）之间也视为换行
        final isBlock = const {
          'p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
          'section', 'article', 'blockquote', 'tr', 'table',
        }.contains(node.localName);
        if (isBlock && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write('\n');
        }
        for (final child in node.nodes) {
          walk(child);
        }
        if (isBlock && !buffer.toString().endsWith('\n')) {
          buffer.write('\n');
        }
      }
    }
    for (final child in element.nodes) {
      walk(child);
    }
    return buffer.toString();
  }

  String _cleanText(String text) {
    // 清理HTML实体。注意：有些站点会用 `&n bsp;` 或 `&nbsp` 等变体混淆，
    // 这里用正则统一处理 `&nbsp;` 及其带空格/缺分号的变体。
    text = text
        .replaceAll(RegExp(r'&n\s*b\s*s\s*p\s*;?', caseSensitive: false), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'&#\d+;'), ' ')
        .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ');

    // 把 <br> 标签替换为换行（在移除标签前处理，避免被 <[^>]*> 一并删掉）
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    // 移除残留的HTML标签
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    // 清理多余空白：保留换行结构，只压缩行内连续空白。
    // 注意：不能把 \n 也替换成空格，否则会破坏段落结构（整章变成一个段落）。
    // 先把所有换行统一为 \n，再把行内连续空白压缩为单个空格。
    text = text.replaceAll(RegExp(r'\r\n?'), '\n');
    // 压缩行内连续空白（空格、制表符、全角空格等，但不含换行）
    text = text.replaceAll(RegExp(r'[ \t\u3000]+'), ' ');
    // 把连续多个换行规范化为双换行（段落分隔）
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // 去掉行首行尾多余空格
    text = text.replaceAll(RegExp(r' *\n *'), '\n');

    // 行级过滤：删除站点插入的防复制提示行（如"请关闭浏览器阅读模式后查看本章节"）
    final lines = text.split('\n').where((line) {
      final l = line.trim();
      if (l.isEmpty) return true;
      return !(l.contains('请关闭浏览器阅读模式') ||
          l.contains('阅读模式后查看') ||
          l.contains('无法翻页') ||
          l.contains('章节内容丢失'));
    }).toList();
    text = lines.join('\n');

    // 行级过滤后可能产生连续空行，再次规范化
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  /// 查找"下一章"链接
  String? findNextChapterLink(String html, String currentUrl) {
    try {
      final document = html_parser.parse(html);
      final nextKeywords = ['下一页', '下一章', '下一节', '下一卷', '下一部分',
          'next', 'next chapter', 'next page', 'next section',
          '下一页', '下一章', '下一节'];

      // 查找包含"下一章"等关键词的链接
      final links = document.querySelectorAll('a');
      for (final link in links) {
        final text = link.text.trim().toLowerCase();
        final href = link.attributes['href'] ?? '';

        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }

        for (final keyword in nextKeywords) {
          if (text.contains(keyword.toLowerCase())) {
            // 解析相对URL
            return _resolveUrl(currentUrl, href);
          }
        }
      }

      // 也检查class/id中包含next的链接
      final nextLinks = document.querySelectorAll(
        'a[class*="next"], a[id*="next"], a[rel="next"], '
        '.next a, .pagination a:last-child'
      );
      for (final link in nextLinks) {
        final href = link.attributes['href'] ?? '';
        if (href.isNotEmpty && !href.startsWith('#') && !href.startsWith('javascript:')) {
          return _resolveUrl(currentUrl, href);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 解析相对URL为绝对URL
  String _resolveUrl(String baseUrl, String relativeUrl) {
    try {
      return Uri.parse(relativeUrl).isAbsolute
          ? relativeUrl
          : Uri.parse(baseUrl).resolve(relativeUrl).toString();
    } catch (_) {
      return relativeUrl;
    }
  }

  /// 提取多章节内容（从当前页开始，自动翻页提取）
  Future<String> extractMultiChapter(String startUrl, {int maxChapters = 10}) async {
    final buffer = StringBuffer();
    String? currentUrl = startUrl;
    int chapterCount = 0;

    while (currentUrl != null && chapterCount < maxChapters) {
      try {
        final response = await HttpUtil.get(currentUrl);

        if (response.statusCode != 200) break;

        final body = HttpUtil.decodeBody(response);
        final result = _extractFromHtml(body, currentUrl);
        if (result != null) {
          if (chapterCount > 0) {
            buffer.writeln('\n\n--- 第 ${chapterCount + 1} 章 ---\n\n');
          }
          buffer.writeln(result.content);
        }

        // 查找下一章链接
        currentUrl = findNextChapterLink(body, currentUrl);
        chapterCount++;

        // 避免请求过快
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        break;
      }
    }

    return buffer.toString();
  }

  /// 从章节页 HTML 中查找书籍目录页（TOC）的 URL。
  /// 常见目录链接文字：目录、章节目录、返回目录、查看目录、全部章节。
  /// 优先匹配"全部章节/完整目录"等指向完整章节列表页的链接（如 /newbook/），
  /// 因为普通目录页（/book/）常只显示最新若干章（倒序），无法取到完整书籍。
  String? findTocUrl(String html, String currentUrl) {
    try {
      final document = html_parser.parse(html);
      final links = document.querySelectorAll('a');

      // 第一优先：指向完整章节列表页的链接（"全部章节"、"完整目录"、"章节目录"等）
      final fullTocKeywords = ['全部章节', '完整目录', '章节目录', '章节列表', '全部目录'];
      for (final link in links) {
        final text = link.text.trim();
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }
        for (final keyword in fullTocKeywords) {
          if (text.contains(keyword)) {
            return _resolveUrl(currentUrl, href);
          }
        }
      }

      // 第二优先：href 形如 /newbook/ 或 /new/ 的完整章节列表页
      for (final link in links) {
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }
        if (RegExp(r'/(newbook|new|all|list|toc)/', caseSensitive: false).hasMatch(href)) {
          return _resolveUrl(currentUrl, href);
        }
      }

      // 兜底：普通"目录"链接
      final tocKeywords = ['目录', '返回目录', '查看目录'];
      for (final link in links) {
        final text = link.text.trim();
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }
        for (final keyword in tocKeywords) {
          if (text.contains(keyword)) {
            return _resolveUrl(currentUrl, href);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从目录页提取整本书的章节列表（标题 + URL）。
  /// 自动跟随目录分页（如 _2.html、index_2.html），直到没有更多分页。
  /// [maxPages] 默认 40：按每页 100 章估算可覆盖 4000 章的书；
  /// 超长篇小说（5000+ 章）可在调用处传更大的值。
  Future<List<Chapter>> extractToc(String tocUrl, {int maxPages = 40}) async {
    final chapters = <Chapter>[];
    final seenUrls = <String>{};
    String? currentUrl = tocUrl;
    int page = 0;

    while (currentUrl != null && page < maxPages) {
      try {
        final response = await HttpUtil.get(currentUrl);
        if (response.statusCode != 200) break;

        final body = HttpUtil.decodeBody(response);
        final document = html_parser.parse(body);

        // 若当前目录页只显示最新若干章（如 /book/ 页），
        // 优先跳转到"全部章节"完整列表页（如 /newbook/），避免只取到部分章节。
        final fullTocUrl = _findFullTocUrl(document, currentUrl);
        if (fullTocUrl != null && fullTocUrl != currentUrl) {
          currentUrl = fullTocUrl;
          continue;
        }

        // 提取本页所有章节链接：优先 <dd><a>，其次 <li><a>，最后任意 <a>
        final ddLinks = document.querySelectorAll('dd a');
        final liLinks = document.querySelectorAll('li a');
        final allLinks = document.querySelectorAll('a');

        final candidates = ddLinks.isNotEmpty
            ? ddLinks
            : (liLinks.isNotEmpty ? liLinks : allLinks);

        final before = chapters.length;
        for (final link in candidates) {
          final href = link.attributes['href'] ?? '';
          if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
            continue;
          }
          final title = link.text.trim();
          if (title.isEmpty) continue;
          // 只收集看起来像章节的链接（含"第"字或数字，且不是目录/首页等导航）
          if (!_looksLikeChapterTitle(title)) continue;

          final absUrl = _resolveUrl(currentUrl, href);
          if (seenUrls.contains(absUrl)) continue;
          seenUrls.add(absUrl);

          chapters.add(Chapter(
            title: title,
            startIndex: chapters.length,
            url: absUrl,
          ));
        }

        // 首轮（page==0）当前页提取章节过少（< 50 章）→ 尝试移动版域名。
        // 部分站点 PC 版目录页只显示最新 30 章或为空壳（完整章节列表
        // 只在 m. 移动版渲染），如 52bqg 的"新版目录"index_1.html。
        if (page == 0 && chapters.length - before < 50 && currentUrl.contains('www.')) {
          // 优先跳转到移动版的完整目录页（index_N.html，若当前页有该链接）
          String? mobileFullToc;
          for (final link in document.querySelectorAll('a')) {
            final href = link.attributes['href'] ?? '';
            if (RegExp(r'index_\d+\.html$').hasMatch(href)) {
              mobileFullToc = _resolveUrl(currentUrl, href).replaceFirst('www.', 'm.');
              break;
            }
          }
          final mobileUrl = mobileFullToc ?? currentUrl.replaceFirst('www.', 'm.');
          if (mobileUrl != currentUrl) {
            currentUrl = mobileUrl;
            continue;
          }
        }

        // 查找下一页目录链接
        currentUrl = _findNextTocPage(document, currentUrl);
        page++;

        // 避免请求过快
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (_) {
        break;
      }
    }

    // 目录页顶部常有一个"最新章节"区块，其章节是倒序排列的（最新章在最上）。
    // 若直接按抓取顺序返回，会把倒序区块混入正序目录，导致章节顺序混乱。
    // 因此这里按章节号排序，保证目录始终是正序（第一章在最前）。
    // 排序前先去重：部分站点目录会有同一章多个变体条目（标题略不同、
    // URL 不同），保留章节号首次出现的一条即可，避免重复条目导致
    // 排序后标题与 URL 错位（跳转落到错误章节）。
    final seenNumbers = <int>{};
    final deduped = <Chapter>[];
    for (final ch in chapters) {
      final num = extractChapterNumber(ch.title);
      if (num != null && !seenNumbers.add(num)) {
        continue;
      }
      deduped.add(ch);
    }
    chapters
      ..clear()
      ..addAll(deduped);

    sortChaptersByNumber(chapters);

    // 排序后重新生成 startIndex
    for (var i = 0; i < chapters.length; i++) {
      chapters[i] = Chapter(
        title: chapters[i].title,
        startIndex: i,
        url: chapters[i].url,
      );
    }

    return chapters;
  }

  /// 在目录页中查找指向"全部章节"完整列表页的链接（如 /newbook/）。
  /// 普通目录页（/book/）常只显示最新若干章，需跳转到完整列表页才能取到整本书。
  String? _findFullTocUrl(html_dom.Document document, String currentUrl) {
    try {
      final links = document.querySelectorAll('a');
      final fullTocKeywords = ['全部章节', '完整目录', '章节目录', '章节列表', '全部目录'];
      for (final link in links) {
        final text = link.text.trim();
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }
        for (final keyword in fullTocKeywords) {
          if (text.contains(keyword)) {
            return _resolveUrl(currentUrl, href);
          }
        }
      }
      // 兜底：href 形如 /newbook/ 或 /new/ 的完整章节列表页
      for (final link in links) {
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }
        if (RegExp(r'/(newbook|new|all|list|toc)/', caseSensitive: false).hasMatch(href)) {
          return _resolveUrl(currentUrl, href);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从目录页提取书籍标题（小说名）。
  /// 优先级：`《书名》` → `.bookname` 容器 → `<h1>`（过滤站点名）→ `<title>` 剥离后缀。
  Future<String?> extractBookTitle(String tocUrl) async {
    try {
      final response = await HttpUtil.get(tocUrl);
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(HttpUtil.decodeBody(response));

      // 常见站点名/通用词，h1 命中这些时不能作为书名
      const siteNames = [
        '笔趣阁', '小说', '阅读网', '书城', '文学', '起点', '纵横',
        '章节', '目录', '首页', '无弹窗', '全文', '全集',
      ];

      // 1. 优先取 <h1>（真实书名，过滤站点名）——比《》全文匹配更可靠：
      //    《》匹配会命中页面推荐位/猜你喜欢里的其他书（如 7biqi 目录页
      //    推荐《万界点名册》），h1 始终是当前书的标题。
      final h1 = document.querySelector('h1');
      if (h1 != null) {
        final t = h1.text.trim().replaceAll(RegExp(r'[《》]'), '');
        if (t.isNotEmpty && t.length < 100 && !siteNames.any(t.contains)) {
          return t;
        }
      }

      // 2. .bookname 容器（笔趣阁类站点目录页常见）
      final bookname = document.querySelector('.bookname, .book-name, .book-title, .info h1');
      if (bookname != null) {
        final t = bookname.text.trim().replaceAll(RegExp(r'[《》]'), '');
        if (t.isNotEmpty && t.length < 100 && !siteNames.any(t.contains)) {
          return t;
        }
      }

      // 3. 《书名》样式（部分站点 h1 是站点名时才用）
      final bookRegex = RegExp(r'《([^《》]{1,30})》');
      final anyMatch = bookRegex.firstMatch(document.body?.text ?? '');
      if (anyMatch != null && anyMatch.group(1)!.trim().isNotEmpty) {
        return anyMatch.group(1)!.trim();
      }

      // 4. <title> 剥离站点名后缀
      final titleTag = document.querySelector('title');
      if (titleTag != null) {
        String t = titleTag.text.trim();
        // 剥离站点名后缀（如 " - 顶点中文"、"最新章节列表" 等）
        final separators = [' - ', ' — ', ' – ', ' | ', ' :: ', '_'];
        for (final sep in separators) {
          final idx = t.indexOf(sep);
          if (idx > 0) {
            t = t.substring(0, idx);
            break;
          }
        }
        // 去掉"最新章节列表"等目录页特征词
        t = t.replaceAll('最新章节列表', '').replaceAll('最新章节', '');
        t = t.replaceAll(RegExp(r'[《》]'), '');
        t = t.trim();
        if (t.isNotEmpty && t.length < 100 && !siteNames.any(t.contains)) {
          return t;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 判断链接文字是否像章节标题（含"第X章/节/回/话"等，或纯数字章节）。
  bool _looksLikeChapterTitle(String title) {
    if (title.contains('目录') || title.contains('首页') || title.contains('上一章') ||
        title.contains('下一章') || title.contains('上一页') || title.contains('下一页') ||
        title.contains('返回') || title.contains('书架') || title.contains('登录') ||
        title.contains('注册')) {
      return false;
    }
    return RegExp(r'第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章节卷回话篇部集]').hasMatch(title) ||
        RegExp(r'^\s*\d+\s*[章节回话]').hasMatch(title);
  }

  /// 在目录页中查找下一页目录链接（如 _2.html、_3.html）。
  String? _findNextTocPage(html_dom.Document document, String currentUrl) {
    try {
      final links = document.querySelectorAll('a');
      for (final link in links) {
        final text = link.text.trim();
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
          continue;
        }
        // 下一页目录：文字为"下一页"或"下页"，或 href 形如 _N.html / index_N.html
        if (text.contains('下一页') || text.contains('下页') || text.contains('后一页')) {
          return _resolveUrl(currentUrl, href);
        }
        if (RegExp(r'(?:_\d+\.html$)|(?:index_\d+\.html$)').hasMatch(href)) {
          return _resolveUrl(currentUrl, href);
        }
      }
    } catch (_) {}
    return null;
  }

  String? _extractMeta(html_dom.Document document, String name) {
    final meta = document.querySelector('meta[name="$name"], meta[property="article:$name"]');
    if (meta != null) {
      return meta.attributes['content'];
    }
    return null;
  }

  DateTime? _extractPublishDate(html_dom.Document document) {
    final selectors = [
      'meta[property="article:published_time"]',
      'meta[name="pubdate"]',
      'meta[name="publishdate"]',
      'time[datetime]',
    ];

    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) {
        final dateStr = element.attributes['content'] ?? element.attributes['datetime'];
        if (dateStr != null) {
          try {
            return DateTime.parse(dateStr);
          } catch (_) {}
        }
      }
    }
    return null;
  }

  String? _extractFeaturedImage(html_dom.Document document) {
    final selectors = [
      'meta[property="og:image"]',
      'meta[name="twitter:image"]',
      'link[rel="image_src"]',
    ];

    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) {
        return element.attributes['content'] ?? element.attributes['href'];
      }
    }
    return null;
  }
}
