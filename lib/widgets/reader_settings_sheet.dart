import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reading_config.dart';
import '../models/book.dart';
import '../providers/reading_provider.dart';
import '../providers/book_provider.dart';
import '../core/theme.dart';

class ReaderSettingsSheet extends StatefulWidget {
  // 当前书籍（用于屏蔽词管理；每本书独立维护）
  final Book? book;
  // 屏蔽词变更后回调（触发阅读页重建，让过滤立即生效）
  final VoidCallback? onBlockedWordsChanged;

  const ReaderSettingsSheet({super.key, this.book, this.onBlockedWordsChanged});

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  final TextEditingController _blockWordController = TextEditingController();
  // 屏蔽词上限与单条长度限制
  static const int _maxBlockedWords = 10;
  static const int _maxBlockWordLength = 50;

  @override
  void dispose() {
    _blockWordController.dispose();
    super.dispose();
  }

  void _addBlockWord() {
    final word = _blockWordController.text.trim();
    final book = widget.book;
    if (word.isEmpty) return;
    if (book == null) return;
    if (word.length > _maxBlockWordLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('屏蔽词不能超过 $_maxBlockWordLength 字')),
      );
      return;
    }
    if (book.blockedWords.contains(word)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该屏蔽词已存在')),
      );
      return;
    }
    if (book.blockedWords.length >= _maxBlockedWords) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多添加 $_maxBlockedWords 个屏蔽词')),
      );
      return;
    }
    setState(() {
      book.blockedWords.add(word);
      _blockWordController.clear();
    });
    Provider.of<BookProvider>(context, listen: false).updateBook(book);
    widget.onBlockedWordsChanged?.call();
  }

  void _removeBlockWord(String word) {
    final book = widget.book;
    if (book == null) return;
    setState(() {
      book.blockedWords.remove(word);
    });
    Provider.of<BookProvider>(context, listen: false).updateBook(book);
    widget.onBlockedWordsChanged?.call();
  }

  /// 加减号步进按钮（与拖动滑条并存），到达边界时置灰不可点
  Widget _buildStepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 26),
      color: AppTheme.primaryColor,
      disabledColor: AppTheme.textTertiary.withValues(alpha: 0.5),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  void _setLineHeight(ReadingProvider provider, ReadingConfig config, double value) {
    provider.updateConfig(
      ReadingConfig(
        fontSize: config.fontSize,
        fontFamily: config.fontFamily,
        lineHeight: value,
        theme: config.theme,
        animation: config.animation,
        nightMode: config.nightMode,
        screenBrightness: config.screenBrightness,
        voiceProfileId: config.voiceProfileId,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Consumer<ReadingProvider>(
        builder: (context, provider, _) {
          final config = provider.config;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 拖拽指示器
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),

                // 字体大小
                _buildSectionTitle('字体大小'),
                Row(
                  children: [
                    Icon(Icons.text_fields, size: 16, color: AppTheme.textSecondary),
                    _buildStepButton(
                      icon: Icons.remove_circle_outline,
                      enabled: config.fontSize > 12,
                      onTap: () => provider.setFontSize((config.fontSize - 1).clamp(12.0, 36.0)),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          activeTrackColor: AppTheme.primaryColor,
                          inactiveTrackColor: AppTheme.dividerColor,
                          thumbColor: AppTheme.primaryColor,
                        ),
                        child: Slider(
                          value: config.fontSize,
                          min: 12,
                          max: 36,
                          divisions: 24,
                          label: '${config.fontSize.round()}',
                          onChanged: (value) => provider.setFontSize(value),
                        ),
                      ),
                    ),
                    _buildStepButton(
                      icon: Icons.add_circle_outline,
                      enabled: config.fontSize < 36,
                      onTap: () => provider.setFontSize((config.fontSize + 1).clamp(12.0, 36.0)),
                    ),
                    Icon(Icons.text_fields, size: 24, color: AppTheme.textSecondary),
                  ],
                ),
                Center(
                  child: Text(
                    '当前字号: ${config.fontSize.round()}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 行间距
                _buildSectionTitle('行间距'),
                Row(
                  children: [
                    Text('1.0', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    _buildStepButton(
                      icon: Icons.remove_circle_outline,
                      enabled: config.lineHeight > 1.0,
                      onTap: () => _setLineHeight(provider, config, (config.lineHeight - 0.1).clamp(1.0, 3.0)),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          activeTrackColor: AppTheme.primaryColor,
                          inactiveTrackColor: AppTheme.dividerColor,
                          thumbColor: AppTheme.primaryColor,
                        ),
                        child: Slider(
                          value: config.lineHeight,
                          min: 1.0,
                          max: 3.0,
                          divisions: 20,
                          label: config.lineHeight.toStringAsFixed(1),
                          onChanged: (value) => _setLineHeight(provider, config, value),
                        ),
                      ),
                    ),
                    _buildStepButton(
                      icon: Icons.add_circle_outline,
                      enabled: config.lineHeight < 3.0,
                      onTap: () => _setLineHeight(provider, config, (config.lineHeight + 0.1).clamp(1.0, 3.0)),
                    ),
                    Text('3.0', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
                Center(
                  child: Text(
                    '当前行间距: ${config.lineHeight.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 阅读主题
                _buildSectionTitle('阅读主题'),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildThemeButton('经典', ReadingTheme.classic, config.theme, provider),
                      const SizedBox(width: 12),
                      _buildThemeButton('护眼', ReadingTheme.green, config.theme, provider),
                      const SizedBox(width: 12),
                      _buildThemeButton('深色', ReadingTheme.dark, config.theme, provider),
                      const SizedBox(width: 12),
                      _buildThemeButton('灰色', ReadingTheme.gray, config.theme, provider),
                      const SizedBox(width: 12),
                      _buildThemeButton('纸质', ReadingTheme.paper, config.theme, provider),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 翻页动画
                _buildSectionTitle('翻页动画'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildAnimationChip('无', PageAnimation.none, config.animation, provider),
                    _buildAnimationChip('滑动', PageAnimation.slide, config.animation, provider),
                  ],
                ),
                const SizedBox(height: 24),

                // 夜间模式
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('夜间模式'),
                  value: config.nightMode,
                  onChanged: (value) => provider.setNightMode(value),
                  activeColor: AppTheme.primaryColor,
                ),

                // 翻页方式
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('上下滚动模式'),
                  subtitle: Text(
                    config.scrollMode ? '上下滑动滚动阅读' : '左右滑动翻页阅读',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  value: config.scrollMode,
                  onChanged: (value) => provider.setScrollMode(value),
                  activeColor: AppTheme.primaryColor,
                ),

                // 屏蔽词管理（每本书独立）
                if (widget.book != null) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('屏蔽词（$_maxBlockedWords 个上限，每个 $_maxBlockWordLength 字内）'),
                  const SizedBox(height: 4),
                  Text(
                    '正文与朗读中将直接剔除屏蔽词',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  // 已有屏蔽词列表
                  if (widget.book!.blockedWords.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '暂无屏蔽词',
                        style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.book!.blockedWords.map((word) {
                        return InputChip(
                          label: Text(word),
                          onDeleted: () => _removeBlockWord(word),
                          deleteIconColor: AppTheme.primaryColor,
                          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                          side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                          labelStyle: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  // 添加输入框
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _blockWordController,
                          maxLength: _maxBlockWordLength,
                          decoration: const InputDecoration(
                            hintText: '输入要屏蔽的词',
                            isDense: true,
                            counterText: '',
                            border: OutlineInputBorder(),
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _addBlockWord(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: widget.book!.blockedWords.length >= _maxBlockedWords
                            ? null
                            : _addBlockWord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildThemeButton(
    String label,
    ReadingTheme theme,
    ReadingTheme currentTheme,
    ReadingProvider provider,
  ) {
    final isSelected = theme == currentTheme;
    final bgColor = AppTheme.readingBackgrounds[theme] ?? AppTheme.readingBackgrounds[ReadingTheme.classic]!;
    final textColor = AppTheme.readingTextColors[theme] ?? AppTheme.readingTextColors[ReadingTheme.classic]!;

    return GestureDetector(
      onTap: () => provider.setTheme(theme),
      child: Container(
        width: 60,
        height: 80,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 8)]
              : null,
        ),
        child: Center(
          child: Text(
            'Aa',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimationChip(
    String label,
    PageAnimation animation,
    PageAnimation currentAnimation,
    ReadingProvider provider,
  ) {
    final isSelected = animation == currentAnimation;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => provider.setAnimation(animation),
      selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      checkmarkColor: AppTheme.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
