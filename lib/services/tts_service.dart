import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../models/voice_profile.dart';
import '../models/book.dart';
import 'tts_notification.dart';

enum TtsState { stopped, playing, paused }

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _state = TtsState.stopped;
  VoiceProfile? _currentVoice;
  Book? _currentBook;
  int _currentPosition = 0;
  String _currentText = '';
  final StreamController<TtsState> _stateController = StreamController<TtsState>.broadcast();
  final StreamController<double> _progressController = StreamController<double>.broadcast();
  final StreamController<void> _pageCompleteController = StreamController<void>.broadcast();
  Timer? _speedDebounce;
  DateTime? _lastPageCompleteAt;
  bool _suppressComplete = false;
  // 停止代次：stop() 自增。合成耗时较长，合成完成时若代次已变（用户已停止），
  // 丢弃结果不再播放，防止"点停止后上一句合成完又响起来"。
  int _stopGen = 0;
  // 当前朗读上下文（供悬浮窗/通知跳转回书定位使用）
  Book? _nowPlayingBook;
  String? _nowPlayingText;
  int _nowPlayingCharIndex = 0;
  final StreamController<void> _nowPlayingController =
      StreamController<void>.broadcast();

  /// 触发一次"段播放完成"（去重防抖：stop/setAudioSource 会引发重复 completed，
  /// 若不去重，双 completed 会连跳两行造成跳段）
  void _emitPageComplete() {
    // 播放切换期间（_speakWithAi 设置新源时）旧源会重放 completed，
    // 合成耗时可能超过 500ms 防抖窗口，用开关直接屏蔽
    if (_suppressComplete) return;
    final now = DateTime.now();
    if (_lastPageCompleteAt != null &&
        now.difference(_lastPageCompleteAt!).inMilliseconds < 500) {
      return;
    }
    _lastPageCompleteAt = now;
    // 注意：不要在这里把 state 置为 stopped——段与段之间（尤其合成空档期）
    // 朗读会话仍在进行，置 stopped 会让悬浮窗/通知闪烁消失，也会被
    // _startTts 误判为"AI 未播放"回退系统音色
    _pageCompleteController.add(null);
  }

  TtsState get state => _state;
  Stream<TtsState> get stateStream => _stateController.stream;
  Stream<double> get progressStream => _progressController.stream;
  Stream<void> get pageCompleteStream => _pageCompleteController.stream;
  VoiceProfile? get currentVoice => _currentVoice;
  Book? get currentBook => _currentBook;
  Stream<void> get nowPlayingStream => _nowPlayingController.stream;
  Book? get nowPlayingBook => _nowPlayingBook;
  String? get nowPlayingText => _nowPlayingText;
  int get nowPlayingCharIndex => _nowPlayingCharIndex;

  /// 音频是否处于"忙"状态：实际在播，或正在加载/缓冲新源。
  /// 段播完后 just_audio 会先后发 completed+playing=true 与
  /// completed+playing=false 两个状态（前者是播完瞬态），若只看 playing
  /// 会把"已播完"误判为"在播"。processingState=completed 时一律视为
  /// 播完（busy=false），悬浮窗跳回时据此续播下一段。
  bool get audioBusy =>
      _audioPlayer.processingState != ProcessingState.completed &&
      (_audioPlayer.playing ||
          _audioPlayer.processingState == ProcessingState.loading ||
          _audioPlayer.processingState == ProcessingState.buffering);

  /// 更新当前朗读位置（阅读器每读一段时调用），供悬浮窗跳转定位
  void updateNowPlaying(Book book, int charIndex, String text) {
    _nowPlayingBook = book;
    _nowPlayingCharIndex = charIndex;
    _nowPlayingText = text;
    _nowPlayingController.add(null);
    // 同步通知栏：书名为正文，点击回书定位用 payload
    TtsNotification.show(
      bookTitle: book.title,
      playing: _state == TtsState.playing,
      payload: jsonEncode({
        'id': book.id,
        'char': charIndex,
        'text': text,
      }),
    );
  }

  /// 朗读停止时清除悬浮窗上下文
  void clearNowPlaying() {
    _nowPlayingBook = null;
    _nowPlayingText = null;
    _nowPlayingController.add(null);
    TtsNotification.hide();
  }
  int get currentPosition => _currentPosition;

  Future<void> init() async {
    await _flutterTts.setLanguage('zh-CN');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    _flutterTts.setStartHandler(() {
      _state = TtsState.playing;
      _stateController.add(TtsState.playing);
    });

    _flutterTts.setCompletionHandler(() {
      _emitPageComplete();
    });

    _flutterTts.setCancelHandler(() {
      _state = TtsState.stopped;
      _stateController.add(TtsState.stopped);
    });

    _flutterTts.setErrorHandler((msg) {
      _state = TtsState.stopped;
      _stateController.add(TtsState.stopped);
    });

    // 自定义音色播放完成时触发翻页
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _emitPageComplete();
      }
    });

    // 状态变化同步通知栏（暂停/恢复切换标题）
    _stateController.stream.listen((s) {
      final book = _nowPlayingBook;
      if (book == null || s == TtsState.stopped) return;
      TtsNotification.show(
        bookTitle: book.title,
        playing: s == TtsState.playing,
        payload: jsonEncode({
          'id': book.id,
          'char': _nowPlayingCharIndex,
          'text': _nowPlayingText ?? '',
        }),
      );
    });
  }

  Future<void> setVoice(VoiceProfile voice) async {
    _currentVoice = voice;
    await _applyVoiceSettings();
  }

  /// 重新应用当前音色设置（用于实时切换音色/速度）
  Future<void> applyCurrentVoice() async {
    if (_currentVoice != null) {
      await _applyVoiceSettings();
      if (_state == TtsState.playing || _state == TtsState.paused) {
        await _restartCurrentSpeech();
      }
    }
  }

  Future<void> _restartCurrentSpeech() async {
    final text = _currentText;
    if (text.isEmpty) return;
    await _flutterTts.stop();
    await _audioPlayer.stop();
    await Future.delayed(const Duration(milliseconds: 150));
    await speak(text, startPosition: _currentPosition);
  }

  Future<void> _applyVoiceSettings() async {
    if (_currentVoice == null) return;
    await _flutterTts.setSpeechRate(_mapSpeedToTtsRate(_currentVoice!.speed));
    await _flutterTts.setPitch(_currentVoice!.pitch);
    await _flutterTts.setVolume(_currentVoice!.volume);
    await _flutterTts.setLanguage(_currentVoice!.language);
  }

  /// 将用户速度（0.5-5.0）映射到 flutter_tts setSpeechRate
  /// Android TTS 的 setSpeechRate 范围约为 0.5-2.0，1.0 为正常语速
  /// 用户速度 1.0 对应正常语速，5.0 对应 Android 支持的最大语速 2.0
  /// 使用平方根曲线：低速区间变化更明显，避免 1x-2x 之间几乎无感
  double _mapSpeedToTtsRate(double userSpeed) {
    if (userSpeed <= 1.0) {
      // 0.5 -> 0.5, 1.0 -> 1.0（慢速区间线性映射）
      return userSpeed.clamp(0.5, 1.0);
    } else {
      // 1.0 -> 1.0, 5.0 -> 2.0（快速区间用平方根曲线，让 1x-2x 加速更明显）
      final t = (userSpeed - 1.0) / (5.0 - 1.0); // 0..1
      return 1.0 + _sqrt(t) * 1.0;
    }
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    return math.sqrt(x); // 平方根曲线：低速区间变化更陡峭，1x-2x 加速明显
  }

  Future<void> speak(String text, {int startPosition = 0}) async {
    _currentText = text;
    _currentPosition = startPosition;
    final gen = _stopGen;

    if (_currentVoice?.type == VoiceType.ai && _currentVoice!.aiApiKey.isNotEmpty) {
      await _speakWithAi(text, stopGen: gen);
    } else if (_currentVoice?.type == VoiceType.custom && _currentVoice!.customVoicePath.isNotEmpty) {
      await _speakWithCustom(text);
    } else {
      await _speakWithSystem(text);
    }
  }

  final Map<String, String> _prefetchCache = {};
  final Set<String> _prefetchPending = {};
  static const int _prefetchMax = 6;
  Future<void>? _prefetchChain;

  /// 预合成：串行执行（GPT-SoVITS 后端单 GPU 推理，并发会排队反而更慢），
  /// 播放 n 段时批量预取 n+1 ~ n+5，消除段落间合成等待。
  /// 缓存按文本去重，容量超限时淘汰最旧的。
  Future<void> prefetch(String text) async {
    if (text.isEmpty || text == _currentText) return;
    if (_currentVoice?.type != VoiceType.ai) return;
    if (_currentVoice!.aiApiKey.isEmpty) return;
    if (_prefetchCache.containsKey(text)) return;
    if (_prefetchPending.contains(text)) return; // 已在队列中，避免重复排队
    _prefetchPending.add(text);
    // 串行队列：上一次预合成完成后再合成本次，避免并发请求在服务端排队
    final prev = _prefetchChain;
    final completer = Completer<void>();
    _prefetchChain = completer.future;
    await prev;
    try {
      // 排队期间该文本可能已被朗读消耗或由更早的排队项合成完成，执行前再查一次
      if (_prefetchCache.containsKey(text) || text == _currentText) return;
      final path = await _callOpenAitts(text);
      if (path != null) {
        _prefetchCache[text] = path;
      }
      while (_prefetchCache.length > _prefetchMax) {
        _prefetchCache.remove(_prefetchCache.keys.first);
      }
      debugPrint('[TTS] prefetch done (cache=${_prefetchCache.length}): ${text.length > 20 ? text.substring(0, 20) : text}');
    } catch (e) {
      debugPrint('[TTS] prefetch ERROR: $e');
    } finally {
      _prefetchPending.remove(text);
      completer.complete();
    }
  }

  /// 播放自定义音色音频文件
  Future<void> _speakWithCustom(String text) async {
    final path = _currentVoice!.customVoicePath;
    debugPrint('[TTS] _speakWithCustom called, path=$path, type=${_currentVoice!.type}');
    try {
      await _audioPlayer.stop();
      debugPrint('[TTS] setFilePath start: $path');
      await _audioPlayer.setAudioSource(AudioSource.file(path));
      debugPrint('[TTS] setFilePath ok');
      await _audioPlayer.setSpeed(_mapSpeedToTtsRate(_currentVoice!.speed));
      await _audioPlayer.setVolume(_currentVoice!.volume);
      _audioPlayer.play();
      debugPrint('[TTS] play() called');
      _state = TtsState.playing;
      _stateController.add(TtsState.playing);
    } catch (e) {
      debugPrint('[TTS] _speakWithCustom ERROR: $e');
      // 音频文件无法播放时回退到系统 TTS
      await _speakWithSystem(text);
    }
  }

  Future<void> _speakWithSystem(String text) async {
    final result = await _flutterTts.speak(text);
    if (result == 1) {
      _state = TtsState.playing;
      _stateController.add(TtsState.playing);
    }
  }

  Future<void> _speakWithAi(String text, {required int stopGen}) async {
    if (_currentVoice == null) return;

    try {
      final provider = _currentVoice!.aiModelProvider;
      String? apiResult;

      // 优先使用预合成结果，避免段落间等待
      final cacheHit = _prefetchCache.containsKey(text);
      debugPrint('[TTS] speak cacheHit=$cacheHit text="${text.length > 12 ? text.substring(0, 12) : text}"');
      if (cacheHit) {
        apiResult = _prefetchCache.remove(text);
      } else {
        switch (provider) {
          case 'openai':
            apiResult = await _callOpenAitts(text);
            break;
          case 'volcengine':
            apiResult = await _callVolcEngineTts(text);
            break;
          default:
            apiResult = await _callCustomAiTts(text);
        }
      }

      // 合成期间用户可能已停止：代次变了就丢弃，不再播放
      if (stopGen != _stopGen) {
        debugPrint('[TTS] speak aborted after stop (gen $stopGen != $_stopGen)');
        return;
      }

      if (apiResult != null) {
        // 用音频播放器播放 AI 返回的音频文件（每次新建 source，避免空 URI 导致播放器错误状态）
        await _flutterTts.stop();
        await _audioPlayer.stop();
        // 屏蔽旧源在切换期间重放的 completed（防止"真完成 + 切换假完成"跳段）
        _suppressComplete = true;
        try {
          debugPrint('[TTS] AI play file: ${apiResult.length > 60 ? apiResult.substring(0, 60) : apiResult}');
          await _audioPlayer.setAudioSource(AudioSource.file(apiResult));
          await _audioPlayer.setSpeed(_mapSpeedToTtsRate(_currentVoice!.speed));
          await _audioPlayer.setVolume(_currentVoice!.volume);
          // 新源已就绪，之后的 completed 都是新源的真完成，解除屏蔽
          _suppressComplete = false;
          _state = TtsState.playing;
          _stateController.add(TtsState.playing);
          // play() 的 Future 要等播放结束才 resolve，不能 await（否则 speak 挂起，
          // 且播完的 completed 会先于 finally 到达被屏蔽，朗读卡住）
          unawaited(_audioPlayer.play().catchError((e) {
            debugPrint('[TTS] AI play async ERROR: $e');
            _emitPageComplete();
          }));
        } catch (e) {
          _suppressComplete = false;
          debugPrint('[TTS] _speakWithAi PLAY ERROR: $e');
          // 播放失败：跳过该行继续下一行，避免朗读卡死
          _emitPageComplete();
        }
      } else {
        debugPrint('[TTS] AI synth failed (apiResult null), skip line');
        // 合成失败：跳过该行继续下一行，避免朗读卡死
        _emitPageComplete();
      }
    } catch (e) {
      debugPrint('[TTS] _speakWithAi ERROR: $e');
      // 合成/播放失败：跳过该行继续下一行，避免朗读卡死
      _emitPageComplete();
    }
  }

  Future<String?> _callOpenAitts(String text) async {
    if (_currentVoice == null) return null;

    final endpoint = _currentVoice!.aiEndpoint.isNotEmpty
        ? _currentVoice!.aiEndpoint
        : 'https://api.openai.com/v1/audio/speech';

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer ${_currentVoice!.aiApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _currentVoice!.aiModelName.isNotEmpty ? _currentVoice!.aiModelName : 'tts-1',
              'input': text,
              'voice': _currentVoice!.systemVoiceId.isNotEmpty ? _currentVoice!.systemVoiceId : 'alloy',
              'response_format': 'wav',
              'speed': _currentVoice!.speed,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final file = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      // 静默失败
    }
    return null;
  }

  Future<String?> _callVolcEngineTts(String text) async {
    return null;
  }

  Future<String?> _callCustomAiTts(String text) async {
    return null;
  }

  Future<void> pause() async {
    if ((_currentVoice?.type == VoiceType.custom && _currentVoice!.customVoicePath.isNotEmpty) ||
        _currentVoice?.type == VoiceType.ai) {
      // 自定义/AI 音色：音频播放器暂停（AI 音色也走播放器，不能用系统 TTS 控制）
      await _audioPlayer.pause();
      _state = TtsState.paused;
      _stateController.add(TtsState.paused);
      return;
    }
    final result = await _flutterTts.pause();
    if (result == 1) {
      _state = TtsState.paused;
      _stateController.add(TtsState.paused);
    }
  }

  Future<void> resume() async {
    if ((_currentVoice?.type == VoiceType.custom && _currentVoice!.customVoicePath.isNotEmpty) ||
        _currentVoice?.type == VoiceType.ai) {
      // 自定义/AI 音色：继续播放播放器当前文件（AI 音色无需重新合成）
      if (_audioPlayer.processingState == ProcessingState.completed) {
        // 当前音频已播完（如恢复前恰好播完）：推进下一段，避免朗读卡死
        _emitPageComplete();
        return;
      }
      // play() 的 Future 要等播放结束才 resolve，不能 await（与 _speakWithAi 同理）
      unawaited(_audioPlayer.play().catchError((e) {
        debugPrint('[TTS] resume play ERROR: $e');
        _emitPageComplete();
      }));
      _state = TtsState.playing;
      _stateController.add(TtsState.playing);
      return;
    }
    final result = await _flutterTts.speak(_currentText);
    if (result == 1) {
      _state = TtsState.playing;
      _stateController.add(TtsState.playing);
    }
  }

  Future<void> stop() async {
    // 先递增停止代次并置状态，让在途合成/播放立即失效
    _stopGen++;
    _state = TtsState.stopped;
    _stateController.add(TtsState.stopped);
    clearNowPlaying();
    await _audioPlayer.stop();
    await _flutterTts.stop();
  }

  /// 设置速度并实时生效
  Future<void> setSpeed(double userSpeed) async {
    // 更新当前音色的速度
    if (_currentVoice != null) {
      _currentVoice!.speed = userSpeed;
    }
    // AI/自定义音色：播放器变速即时生效，无需重新合成（避免等待与卡顿重复）
    if (_currentVoice?.type == VoiceType.ai || _currentVoice?.type == VoiceType.custom) {
      if (_state == TtsState.playing || _state == TtsState.paused) {
        await _audioPlayer.setSpeed(_mapSpeedToTtsRate(userSpeed));
      }
      return;
    }
    await _flutterTts.setSpeechRate(_mapSpeedToTtsRate(userSpeed));
    // 防抖：拖动滑块时避免频繁重启朗读，停止拖动 300ms 后再应用
    _speedDebounce?.cancel();
    if (_state == TtsState.playing || _state == TtsState.paused) {
      _speedDebounce = Timer(const Duration(milliseconds: 300), () {
        _restartCurrentSpeech();
      });
    }
  }

  Future<void> setPitch(double pitch) async {
    await _flutterTts.setPitch(pitch);
  }

  Future<List<dynamic>> getAvailableVoices() async {
    return await _flutterTts.getVoices;
  }

  void dispose() {
    _speedDebounce?.cancel();
    _audioPlayer.dispose();
    _flutterTts.stop();
    _stateController.close();
    _progressController.close();
    _pageCompleteController.close();
  }
}
