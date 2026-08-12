import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/voice_profile.dart';
import '../providers/voice_provider.dart';
import '../core/theme.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('朗读音色'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddVoiceDialog(context),
          ),
        ],
      ),
      body: Consumer<VoiceProvider>(
        builder: (context, provider, _) {
          if (provider.voices.isEmpty) {
            return _buildEmptyState(context);
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 当前音色
              if (provider.currentVoice != null) ...[
                _buildCurrentVoiceCard(context, provider.currentVoice!),
                const SizedBox(height: 24),
              ],
              
              // 音色分类
              _buildVoiceSection(context, '系统音色', provider.voices
                  .where((v) => v.type == VoiceType.system).toList(), provider),
              const SizedBox(height: 16),
              _buildVoiceSection(context, '自定义音色', provider.voices
                  .where((v) => v.type == VoiceType.custom).toList(), provider),
              const SizedBox(height: 16),
              _buildVoiceSection(context, 'AI音色', provider.voices
                  .where((v) => v.type == VoiceType.ai).toList(), provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.record_voice_over_rounded,
            size: 80,
            color: AppTheme.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无音色配置',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角 + 添加音色',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentVoiceCard(BuildContext context, VoiceProfile voice) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  voice.type == VoiceType.ai
                      ? Icons.auto_awesome_rounded
                      : voice.type == VoiceType.custom
                          ? Icons.person_rounded
                          : Icons.record_voice_over_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前音色',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      voice.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  voice.type == VoiceType.ai ? 'AI' : voice.type == VoiceType.custom ? '自定义' : '系统',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip('速度 ${voice.speed.toStringAsFixed(1)}x'),
              const SizedBox(width: 8),
              _buildInfoChip('音调 ${voice.pitch.toStringAsFixed(1)}x'),
              if (voice.enableEmotion) ...[
                const SizedBox(width: 8),
                _buildInfoChip('情绪朗读'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }

  Widget _buildVoiceSection(
    BuildContext context,
    String title,
    List<VoiceProfile> voices,
    VoiceProvider provider,
  ) {
    if (voices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...voices.map((voice) => _buildVoiceItem(context, voice, provider)),
      ],
    );
  }

  Widget _buildVoiceItem(
    BuildContext context,
    VoiceProfile voice,
    VoiceProvider provider,
  ) {
    final isCurrent = provider.currentVoice?.id == voice.id;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent
            ? Border.all(color: AppTheme.primaryColor, width: 1.5)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isCurrent
                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                : AppTheme.textTertiary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            voice.type == VoiceType.ai
                ? Icons.auto_awesome_rounded
                : voice.type == VoiceType.custom
                    ? Icons.person_rounded
                    : Icons.record_voice_over_rounded,
            color: isCurrent ? AppTheme.primaryColor : AppTheme.textSecondary,
            size: 22,
          ),
        ),
        title: Text(
          voice.name,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          '速度 ${voice.speed.toStringAsFixed(1)}x · 音调 ${voice.pitch.toStringAsFixed(1)}x',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: isCurrent
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '使用中',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded, color: AppTheme.textSecondary),
                onSelected: (value) {
                  if (value == 'use') {
                    provider.setCurrentVoice(voice.id);
                  } else if (value == 'edit') {
                    _showEditVoiceDialog(context, voice);
                  } else if (value == 'delete') {
                    _confirmDeleteVoice(context, voice, provider);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'use', child: Text('使用此音色')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: AppTheme.errorColor)),
                  ),
                ],
              ),
        onTap: () => provider.setCurrentVoice(voice.id),
      ),
    );
  }

  void _showAddVoiceDialog(BuildContext context) {
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
              Text('添加音色', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              _buildAddVoiceOption(
                context,
                icon: Icons.record_voice_over_rounded,
                title: '系统音色',
                subtitle: '使用手机系统自带的TTS音色',
                onTap: () {
                  Navigator.pop(context);
                  _showSystemVoiceConfig(context);
                },
              ),
              const SizedBox(height: 12),
              _buildAddVoiceOption(
                context,
                icon: Icons.upload_file_rounded,
                title: '上传自定义音色',
                subtitle: '上传语音样本文件，生成个性化音色',
                onTap: () {
                  Navigator.pop(context);
                  _uploadCustomVoice(context);
                },
              ),
              const SizedBox(height: 12),
              _buildAddVoiceOption(
                context,
                icon: Icons.auto_awesome_rounded,
                title: 'AI音色（大模型）',
                subtitle: '配置API密钥，使用AI进行情绪化朗读',
                onTap: () {
                  Navigator.pop(context);
                  _showAiVoiceConfig(context);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddVoiceOption(
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

  void _showSystemVoiceConfig(BuildContext context) {
    final nameController = TextEditingController();
    double speed = 1.0;
    double pitch = 1.0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('添加系统音色'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '音色名称',
                  hintText: '例如：温柔女声',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('速度: ${speed.toStringAsFixed(1)}x'),
              Slider(
                value: speed,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: (v) => setDialogState(() => speed = v),
              ),
              Text('音调: ${pitch.toStringAsFixed(1)}x'),
              Slider(
                value: pitch,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: (v) => setDialogState(() => pitch = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  final provider = Provider.of<VoiceProvider>(context, listen: false);
                  provider.addVoice(VoiceProfile(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    type: VoiceType.system,
                    speed: speed,
                    pitch: pitch,
                  ));
                  Navigator.pop(context);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadCustomVoice(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'ogg', 'm4a', 'flac'],
        allowMultiple: false,
      );

      debugPrint('_uploadCustomVoice: result=${result != null} files=${result?.files.length ?? 0}');
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        debugPrint('_uploadCustomVoice: file=${file.name} path=${file.path} mounted=$mounted');
        final nameController = TextEditingController(text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));

        if (mounted) {
          debugPrint('_uploadCustomVoice: showing dialog');
          showDialog(
            context: this.context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('自定义音色'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '音色名称',
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
                  onPressed: () {
                    if (nameController.text.trim().isNotEmpty && file.path != null) {
                      final provider = Provider.of<VoiceProvider>(context, listen: false);
                      provider.addCustomVoice(
                        name: nameController.text.trim(),
                        voicePath: file.path!,
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加自定义音色: ${nameController.text.trim()}')),
                      );
                    }
                  },
                  child: const Text('添加'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('_uploadCustomVoice: error $e');
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('文件选择失败')),
        );
      }
    }
  }

  void _showAiVoiceConfig(BuildContext context) {
    final nameController = TextEditingController();
    final apiKeyController = TextEditingController();
    final endpointController = TextEditingController();
    String provider = 'openai';
    String modelName = 'tts-1';
    bool enableEmotion = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('配置AI音色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: '音色名称',
                    hintText: '例如：OpenAI TTS',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: provider,
                  decoration: InputDecoration(
                    labelText: 'AI提供商',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'openai', child: Text('OpenAI TTS')),
                    DropdownMenuItem(value: 'volcengine', child: Text('火山引擎TTS')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义API')),
                  ],
                  onChanged: (v) => setDialogState(() => provider = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyController,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: '本地服务可任意填写',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.visibility_off_rounded),
                      onPressed: () {},
                    ),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointController,
                  decoration: InputDecoration(
                    labelText: 'API端点（可选）',
                    hintText: provider == 'openai' ? 'https://api.openai.com/v1/audio/speech' : '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: modelName),
                  decoration: InputDecoration(
                    labelText: '模型名称',
                    hintText: 'tts-1 / tts-1-hd',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => modelName = v,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用情绪化朗读'),
                  subtitle: const Text('根据文本情感调整朗读语气'),
                  value: enableEmotion,
                  onChanged: (v) => setDialogState(() => enableEmotion = v),
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty && apiKeyController.text.trim().isNotEmpty) {
                  final voiceProvider = Provider.of<VoiceProvider>(context, listen: false);
                  voiceProvider.addAiVoice(
                    name: nameController.text.trim(),
                    provider: provider,
                    apiKey: apiKeyController.text.trim(),
                    modelName: modelName,
                    endpoint: endpointController.text.trim(),
                    enableEmotion: enableEmotion,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加AI音色: ${nameController.text.trim()}')),
                  );
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditVoiceDialog(BuildContext context, VoiceProfile voice) {
    final nameController = TextEditingController(text: voice.name);
    double speed = voice.speed;
    double pitch = voice.pitch;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('编辑音色'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '音色名称',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('速度: ${speed.toStringAsFixed(1)}x'),
              Slider(
                value: speed,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: (v) => setDialogState(() => speed = v),
              ),
              Text('音调: ${pitch.toStringAsFixed(1)}x'),
              Slider(
                value: pitch,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: (v) => setDialogState(() => pitch = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  voice.name = nameController.text.trim();
                  voice.speed = speed;
                  voice.pitch = pitch;
                  Provider.of<VoiceProvider>(context, listen: false).updateVoice(voice);
                  Navigator.pop(context);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteVoice(BuildContext context, VoiceProfile voice, VoiceProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除音色'),
        content: Text('确定要删除音色"${voice.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteVoice(voice.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
}
