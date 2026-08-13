import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/voice_profile.dart';
import '../providers/voice_provider.dart';
import '../services/tts_service.dart';
import '../core/theme.dart';

class TtsControlBar extends StatefulWidget {
  final Book book;
  final VoidCallback onClose;

  const TtsControlBar({
    super.key,
    required this.book,
    required this.onClose,
  });

  @override
  State<TtsControlBar> createState() => _TtsControlBarState();
}

class _TtsControlBarState extends State<TtsControlBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  final TtsService _ttsService = TtsService();
  Timer? _sleepTimer;
  Timer? _countdownTimer;
  int? _sleepMinutes;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();

    // 监听音色变化，实时应用到当前TTS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<VoiceProvider>(context, listen: false).addListener(_onVoiceChanged);
    });
  }

  void _onVoiceChanged() {
    _ttsService.applyCurrentVoice();
  }

  @override
  void dispose() {
    _animationController.dispose();
    try {
      Provider.of<VoiceProvider>(context, listen: false).removeListener(_onVoiceChanged);
    } catch (_) {}
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();
    _sleepMinutes = minutes;
    _remainingSeconds = minutes * 60;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      _ttsService.stop();
      if (mounted) {
        setState(() {
          _sleepMinutes = null;
          _remainingSeconds = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定时关闭已触发，朗读已停止')),
        );
      }
    });
    // 每秒更新倒计时显示
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) _remainingSeconds--;
      });
    });
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('将在 $minutes 分钟后停止朗读')),
      );
    }
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();
    _sleepTimer = null;
    _countdownTimer = null;
    _sleepMinutes = null;
    _remainingSeconds = 0;
    if (mounted) setState(() {});
  }

  String _formatRemaining(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(Icons.record_voice_over_rounded,
                    color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  '正在朗读',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.primaryColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 音色选择
                Consumer<VoiceProvider>(
                  builder: (context, voiceProvider, _) {
                    return GestureDetector(
                      onTap: () => _showVoiceSelector(context),
                      child: Column(
                        children: [
                          Icon(Icons.voice_chat_rounded,
                              color: AppTheme.textSecondary, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            voiceProvider.currentVoice?.name ?? '音色',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // 速度控制
                _buildSpeedControl(),
                // 播放/暂停
                StreamBuilder<TtsState>(
                  stream: _ttsService.stateStream,
                  initialData: TtsState.playing,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data == TtsState.playing;
                    return GestureDetector(
                      onTap: () async {
                        if (isPlaying) {
                          await _ttsService.pause();
                        } else {
                          await _ttsService.resume();
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    );
                  },
                ),
                // 停止
                GestureDetector(
                  onTap: () {
                    _ttsService.stop();
                    widget.onClose();
                  },
                  child: Column(
                    children: [
                      Icon(Icons.stop_rounded,
                          color: AppTheme.textSecondary, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        '停止',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 定时关闭
                GestureDetector(
                  onTap: () => _showSleepTimerSelector(context),
                  child: Column(
                    children: [
                      Icon(
                        _sleepMinutes != null
                            ? Icons.timer_off_rounded
                            : Icons.timer_rounded,
                        color: _sleepMinutes != null
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondary,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sleepMinutes != null
                            ? _formatRemaining(_remainingSeconds)
                            : '定时',
                        style: TextStyle(
                          fontSize: 11,
                          color: _sleepMinutes != null
                              ? AppTheme.primaryColor
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedControl() {
    return Consumer<VoiceProvider>(
      builder: (context, voiceProvider, _) {
        final speed = _ttsService.currentVoice?.speed ??
            voiceProvider.currentVoice?.speed ??
            1.0;
        return GestureDetector(
          onTap: () => _showSpeedSelector(context),
          child: Column(
            children: [
              Icon(Icons.speed_rounded, color: AppTheme.textSecondary, size: 22),
              const SizedBox(height: 4),
              Text(
                '${speed.toStringAsFixed(1)}x',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVoiceSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Consumer<VoiceProvider>(
        builder: (context, voiceProvider, _) {
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
                  Text('选择音色', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...voiceProvider.voices.map((voice) => ListTile(
                          leading: Icon(
                            voice.type == VoiceType.ai
                                ? Icons.auto_awesome_rounded
                                : voice.type == VoiceType.custom
                                    ? Icons.person_rounded
                                    : Icons.record_voice_over_rounded,
                            color: voice.isDefault ? AppTheme.primaryColor : AppTheme.textSecondary,
                          ),
                          title: Text(voice.name),
                          subtitle: Text(
                            voice.type == VoiceType.ai
                                ? 'AI音色'
                                : voice.type == VoiceType.custom
                                    ? '自定义音色'
                                    : '系统音色',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          trailing: voice.isDefault
                              ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor)
                              : null,
                          onTap: () {
                            voiceProvider.setCurrentVoice(voice.id);
                            // 立即将新音色应用到 TTS 服务
                            _ttsService.setVoice(voice);
                            Navigator.pop(context);
                          },
                        )),
                      ],
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

  void _showSpeedSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Consumer<VoiceProvider>(
        builder: (context, voiceProvider, _) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              // 使用 TtsService 中的当前速度，而不是 VoiceProfile 中的
              final currentVoice =
                  _ttsService.currentVoice ?? voiceProvider.currentVoice;
              double currentSpeed = currentVoice?.speed ?? 1.0;
              // 实时变速 + 静默持久化（按钮离散调整与拖动结束共用）
              void applySpeed(double value) {
                final v = value.clamp(0.5, 5.0);
                setSheetState(() => currentSpeed = v);
                _ttsService.setSpeed(v);
                final voice = voiceProvider.currentVoice;
                if (voice != null) {
                  voice.speed = v;
                  voiceProvider.updateVoiceQuietly(voice);
                }
              }

              IconButton buildStepButton({
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
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                );
              }

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
                      Text('朗读速度',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text('0.5x',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)),
                          buildStepButton(
                            icon: Icons.remove_circle_outline,
                            enabled: currentSpeed > 0.5,
                            onTap: () => applySpeed(currentSpeed - 0.25),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16),
                                activeTrackColor: AppTheme.primaryColor,
                                inactiveTrackColor: AppTheme.dividerColor,
                                thumbColor: AppTheme.primaryColor,
                              ),
                              child: Slider(
                                value: currentSpeed,
                                min: 0.5,
                                max: 5.0,
                                divisions: 18,
                                label:
                                    '${currentSpeed.toStringAsFixed(1)}x',
                                onChanged: (value) {
                                  setSheetState(() => currentSpeed = value);
                                  // 只实时变速。不要调 updateVoice：会触发
                                  // notifyListeners → applyCurrentVoice →
                                  // 重启朗读，拖动时同一句循环重播
                                  _ttsService.setSpeed(value);
                                },
                                onChangeEnd: (value) {
                                  // 拖动结束才持久化，且不触发通知
                                  applySpeed(value);
                                },
                              ),
                            ),
                          ),
                          buildStepButton(
                            icon: Icons.add_circle_outline,
                            enabled: currentSpeed < 5.0,
                            onTap: () => applySpeed(currentSpeed + 0.25),
                          ),
                          Text('5.0x',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          '当前速度: ${currentSpeed.toStringAsFixed(1)}x',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showSleepTimerSelector(BuildContext context) {
    if (_sleepTimer != null) {
      _cancelSleepTimer();
      return;
    }

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
              Text('定时关闭', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _sleepTimerChip(context, 15),
                  _sleepTimerChip(context, 30),
                  _sleepTimerChip(context, 60),
                  _sleepTimerChip(context, 120),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sleepTimerChip(BuildContext context, int minutes) {
    return ActionChip(
      label: Text(minutes >= 60 ? '${minutes ~/ 60}小时' : '$minutes分钟'),
      onPressed: () {
        Navigator.pop(context);
        _startSleepTimer(minutes);
      },
      avatar: const Icon(Icons.timer_outlined, size: 18),
    );
  }
}
