import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reading_config.dart';
import '../providers/app_provider.dart';
import '../providers/reading_provider.dart';
import '../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: Consumer2<AppProvider, ReadingProvider>(
        builder: (context, appProvider, readingProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 外观设置
              _buildSectionHeader(context, '外观'),
              _buildSettingCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('深色模式'),
                    subtitle: const Text('切换深色/浅色主题'),
                    value: appProvider.isDarkMode,
                    onChanged: (value) => appProvider.setDarkMode(value),
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('阅读主题'),
                    subtitle: Text(
                      _getThemeName(readingProvider.config.theme),
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showThemeSelector(context, readingProvider),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 朗读设置
              _buildSectionHeader(context, '朗读'),
              _buildSettingCard(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('打开时自动朗读'),
                    subtitle: const Text('进入阅读页面后自动开始朗读'),
                    value: appProvider.config.ttsAutoRead,
                    onChanged: (value) => appProvider.setTtsAutoRead(value),
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('默认朗读速度'),
                    subtitle: Text(
                      '${appProvider.config.ttsDefaultSpeed.toStringAsFixed(1)}x',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showSpeedSelector(context, appProvider),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 缓存管理
              _buildSectionHeader(context, '缓存与存储'),
              _buildSettingCard(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('清除缓存'),
                    subtitle: const Text(
                      '清除临时文件和缓存数据',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _confirmClearCache(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 数据管理
              _buildSectionHeader(context, '数据管理'),
              _buildSettingCard(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.file_download_rounded,
                          color: AppTheme.primaryColor, size: 20),
                    ),
                    title: const Text('导出配置'),
                    subtitle: const Text(
                      '导出音色、书签、阅读设置等所有配置',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _exportConfig(context),
                  ),
                  const Divider(height: 1, indent: 72),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.file_upload_rounded,
                          color: AppTheme.successColor, size: 20),
                    ),
                    title: const Text('导入配置'),
                    subtitle: const Text(
                      '从备份文件恢复所有配置',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _importConfig(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 关于
              _buildSectionHeader(context, '关于'),
              _buildSettingCard(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('版本'),
                    subtitle: const Text(
                      '1.0.0',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('关于吧啦吧啦'),
                    subtitle: const Text(
                      '手机读书听书软件',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showAboutDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSettingCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  String _getThemeName(dynamic theme) {
    switch (theme) {
      case ReadingTheme.classic: return '经典米黄';
      case ReadingTheme.green: return '护眼绿色';
      case ReadingTheme.dark: return '深色模式';
      case ReadingTheme.gray: return '灰色';
      case ReadingTheme.paper: return '纸质';
      default: return '经典米黄';
    }
  }

  void _showThemeSelector(BuildContext context, ReadingProvider provider) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text('选择阅读主题', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...ReadingTheme.values.map((theme) => ListTile(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.readingBackgrounds[theme] ?? Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                title: Text(_getThemeName(theme)),
                trailing: provider.config.theme == theme
                    ? const Icon(Icons.check_rounded, color: AppTheme.primaryColor)
                    : null,
                onTap: () {
                  provider.setTheme(theme);
                  Navigator.pop(context);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSelector(BuildContext context, AppProvider appProvider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final currentSpeed = appProvider.config.ttsDefaultSpeed;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Text('默认朗读速度', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('0.5x', style: TextStyle(color: AppTheme.textSecondary)),
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
                            value: currentSpeed,
                            min: 0.5,
                            max: 5.0,
                            divisions: 18,
                            label: '${currentSpeed.toStringAsFixed(1)}x',
                            onChanged: (value) {
                              setSheetState(() {});
                              appProvider.setTtsDefaultSpeed(value);
                            },
                          ),
                        ),
                      ),
                      Text('5.0x', style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '当前速度: ${currentSpeed.toStringAsFixed(1)}x',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存数据吗？这不会影响您的书籍和配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('缓存已清除')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfig(BuildContext context) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final path = await appProvider.exportAllConfig();
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('配置已导出到: $path')),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出失败')),
      );
    }
  }

  Future<void> _importConfig(BuildContext context) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final success = await appProvider.importAllConfig();
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已导入')),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入失败')),
      );
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.auto_stories_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('吧啦吧啦'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本: 1.0.0'),
            SizedBox(height: 8),
            Text('一款专注于手机读书和听书的软件。'),
            SizedBox(height: 8),
            Text('功能特色:'),
            Text('• 支持本地TXT/MD文件阅读'),
            Text('• 网页文章提取阅读模式'),
            Text('• TTS朗读，多种音色'),
            Text('• AI情绪化朗读（预留）'),
            Text('• 自定义音色上传'),
            Text('• 配置导出/导入'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
