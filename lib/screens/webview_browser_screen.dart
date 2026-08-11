import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../providers/book_provider.dart';
import '../services/readability_service.dart';
import '../services/http_util.dart';
import '../core/theme.dart';
import 'reader_screen.dart';

class WebViewBrowserScreen extends StatefulWidget {
  final String initialUrl;

  const WebViewBrowserScreen({super.key, required this.initialUrl});

  @override
  State<WebViewBrowserScreen> createState() => _WebViewBrowserScreenState();
}

class _WebViewBrowserScreenState extends State<WebViewBrowserScreen> {
  InAppWebViewController? _webViewController;
  final _readabilityService = ReadabilityService();
  bool _isLoading = true;
  String _currentUrl = '';
  String _currentTitle = '';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              minHeight: 2,
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useWideViewPort: true,
                supportZoom: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                userAgent: 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStart: (controller, url) {
                if (mounted) {
                  setState(() {
                    _isLoading = true;
                    _currentUrl = url?.toString() ?? '';
                  });
                }
              },
              onLoadStop: (controller, url) async {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _currentUrl = url?.toString() ?? '';
                  });
                }
                final title = await controller.getTitle();
                if (mounted && title != null) {
                  setState(() => _currentTitle = title);
                }
              },
              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() => _progress = progress / 100);
                }
              },
              onTitleChanged: (controller, title) {
                if (mounted) {
                  setState(() => _currentTitle = title ?? '');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currentTitle.isNotEmpty ? _currentTitle : '浏览网页',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (_currentUrl.isNotEmpty)
            Text(
              _currentUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: Material(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _enterReadingMode,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_stories_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text(
                      '阅读模式',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _enterReadingMode() async {
    // 从WebView获取当前URL
    String url = _currentUrl.isNotEmpty ? _currentUrl : widget.initialUrl;
    if (_webViewController != null) {
      final currentUrl = await _webViewController!.getUrl();
      if (currentUrl != null) {
        url = currentUrl.toString();
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在提取正文...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final result = await _readabilityService.extractFromUrl(url);

      const minContentLength = 200;
      final validContent = result != null && result.content.trim().length >= minContentLength;

      if (validContent && mounted) {
        // 尝试从章节页找到目录页并提取整本书目录（章节标题 + URL）
        List<Chapter> tocChapters = [];
        String bookTitle = result.title;
        try {
          final response = await HttpUtil.get(url);
          if (response.statusCode == 200) {
            final tocUrl = _readabilityService.findTocUrl(HttpUtil.decodeBody(response), url);
            if (tocUrl != null) {
              tocChapters = await _readabilityService.extractToc(tocUrl);
              // 从目录页提取书籍标题（小说名），而非章节标题
              final extractedTitle = await _readabilityService.extractBookTitle(tocUrl);
              if (extractedTitle != null && extractedTitle.isNotEmpty) {
                bookTitle = extractedTitle;
              }
            }
          }
        } catch (_) {
          // 目录提取失败，退化为单章
        }

        if (!mounted) return;

        // 使用 addPastedText 创建书籍并等待完成
        final provider = Provider.of<BookProvider>(context, listen: false);
        final addedBook = await provider.addPastedText(result.content);

        if (addedBook == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('创建书籍失败')),
            );
          }
          return;
        }

        // 更新标题、URL、来源和目录
        addedBook.title = bookTitle.isNotEmpty ? bookTitle : _currentTitle;
        addedBook.url = url;
        addedBook.source = BookSource.url;
        if (tocChapters.isNotEmpty) {
          addedBook.chapters = tocChapters;
          addedBook.chapterCount = tocChapters.length;
          // 定位到当前正在阅读的章节（忽略 http/https 协议差异）
          final normUrl = url.replaceFirst(RegExp(r'^https?://'), '');
          final currentIndex = tocChapters.indexWhere(
              (c) => (c.url ?? '').replaceFirst(RegExp(r'^https?://'), '') == normUrl);
          if (currentIndex >= 0) {
            addedBook.currentChapter = currentIndex;
          }
        }
        // 保存更新
        await provider.updateBook(addedBook);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ReaderScreen(book: addedBook),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法提取正文内容，请确认当前页面包含文章')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提取失败: $e')),
        );
      }
    }
  }
}
