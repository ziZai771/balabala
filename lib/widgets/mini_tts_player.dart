import 'package:flutter/material.dart';
import '../screens/reader_screen.dart';
import '../services/tts_service.dart';

/// 朗读悬浮窗：朗读进行中（非阅读页）显示在右下角。
/// 点击主体回到书中朗读位置（高亮续显）；含播放/暂停与停止按钮。
/// 退出 App 后无需桌面悬浮（由通知栏承担），本组件只存在于 App 页面内。
class MiniTtsPlayer extends StatefulWidget {
  const MiniTtsPlayer({super.key});

  @override
  State<MiniTtsPlayer> createState() => _MiniTtsPlayerState();
}

class _MiniTtsPlayerState extends State<MiniTtsPlayer> {
  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    _tts.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _tts.nowPlayingStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final book = _tts.nowPlayingBook;
    final state = _tts.state;
    if (book == null || state == TtsState.stopped) {
      return const SizedBox.shrink();
    }
    final isPlaying = state == TtsState.playing;

    // 青色高亮卡片：浅色/深色背景下都醒目
    const teal = Color(0xFF00A8A8);

    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      color: teal,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _openReader,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.headphones_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    Text(
                      isPlaying ? '正在朗读' : '已暂停',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: Colors.white,
                  size: 32,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  if (isPlaying) {
                    _tts.pause();
                  } else {
                    _tts.resume();
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.stop_circle_outlined,
                    color: Colors.white.withValues(alpha: 0.9), size: 26),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _tts.stop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReader() {
    final book = _tts.nowPlayingBook;
    if (book == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          book: book,
          restoreTtsCharIndex: _tts.nowPlayingCharIndex,
          restoreTtsText: _tts.nowPlayingText,
        ),
      ),
    );
  }
}
