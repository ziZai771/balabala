import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/book_provider.dart';
import '../models/book.dart';
import '../core/theme.dart';
import 'reader_screen.dart';
import 'webview_browser_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '选择书籍' : '书架'),
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              child: Text(
                '删除 (${_selectedIds.length})',
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                });
              },
              child: const Text('取消'),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => setState(() => _isSelectionMode = true),
            ),
        ],
      ),
      body: Consumer<BookProvider>(
        builder: (context, provider, _) {
          final books = provider.bookshelfBooks;
          
          if (books.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return RefreshIndicator(
            onRefresh: () async => provider.loadBooks(),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.7,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                return _buildBookCard(context, books[index]);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBookDialog(context),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 80,
            color: AppTheme.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '书架空空如也',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 添加书籍',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _showAddBookDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加书籍'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(BuildContext context, Book book) {
    final isSelected = _selectedIds.contains(book.id);
    
    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(book.id);
            } else {
              _selectedIds.add(book.id);
            }
          });
        } else {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => ReaderScreen(book: book),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 300),
            ),
          );
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedIds.add(book.id);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isSelected ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 封面
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 40,
                    color: AppTheme.textTertiary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 标题
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            // 进度
            if (book.totalLength > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${((book.currentPosition / book.totalLength) * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ),
            // 选择模式指示器
            if (_isSelectionMode)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textTertiary,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  void _showAddBookDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '添加书籍',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              _buildAddOption(
                context,
                icon: Icons.file_open_rounded,
                title: '从本地文件导入',
                subtitle: '支持 TXT、MD 等文本格式',
                onTap: () async {
                  Navigator.pop(context);
                  final provider = Provider.of<BookProvider>(context, listen: false);
                  final book = await provider.pickAndAddBook();
                  if (book != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已添加《${book.title}》')),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildAddOption(
                context,
                icon: Icons.link_rounded,
                title: '从网址导入',
                subtitle: '在浏览器中浏览网页，一键进入阅读模式',
                onTap: () {
                  Navigator.pop(context);
                  _showUrlInputDialog(context);
                },
              ),
              const SizedBox(height: 12),
              _buildAddOption(
                context,
                icon: Icons.content_paste_rounded,
                title: '粘贴文本',
                subtitle: '直接粘贴文本内容',
                onTap: () {
                  Navigator.pop(context);
                  _showPasteTextDialog(context);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  void _showUrlInputDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('输入网址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.link_rounded),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              var url = controller.text.trim();
              if (url.isNotEmpty) {
                // 规范化URL：缺少协议时自动补全 https://
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                Navigator.pop(context);
                // 打开WebView浏览器，让用户浏览网页后手动进入阅读模式
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WebViewBrowserScreen(initialUrl: url),
                  ),
                );
              }
            },
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }

  void _showPasteTextDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('粘贴文本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: '在此粘贴文本内容...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(context);
                final provider = Provider.of<BookProvider>(context, listen: false);
                final book = await provider.addPastedText(text);
                if (book != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加《${book.title}》')),
                  );
                }
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _deleteSelected() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除书籍'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 本书吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final provider = Provider.of<BookProvider>(context, listen: false);
              for (final id in _selectedIds) {
                provider.deleteBook(id);
              }
              setState(() {
                _isSelectionMode = false;
                _selectedIds.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
}
