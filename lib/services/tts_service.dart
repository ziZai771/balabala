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

  TtsState get state => _state;
  Stream<TtsState> get stateStream => _stateController.stream;
  Stream<double> get progressStream => _progressController.stream;
  Stream<void> get pageCompleteStream => _pageCompleteController.stream;
  VoiceProfile? get currentVoice => _currentVoice;
  Book? get currentBook => _currentBook;
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
      _state = TtsState.stopped;
      _stateController.add(TtsState.stopped);
      _pageCompleteController.add(null);
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
        _state = TtsState.stopped;
        _stateController.add(TtsState.stopped);
        _pageCompleteController.add(null);
      }
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

    if (_currentVoice?.type == VoiceType.ai && _currentVoice!.aiApiKey.isNotEmpty) {
      await _speakWithAi(text);
    } else if (_currentVoice?.type == VoiceType.custom && _currentVoice!.customVoicePath.isNotEmpty) {
      await _speakWithCustom(text);
    } else {
      await _speakWithSystem(text);
    }
  }

  /// 播放自定义音色音频文件
  Future<void> _speakWithCustom(String text) async {
    final path = _currentVoice!.customVoicePath;
    debugPrint('[TTS] _speakWithCustom called, path=$path, type=${_currentVoice!.type}');
    try {
      await _audioPlayer.stop();
      debugPrint('[TTS] setFilePath start: $path');
      // 强制重新加载 source：先清除再设置，避免相同路径被 just_audio 跳过
      // （stop 后再次播放相同文件时，setFilePath 会因 source 相同而跳过，导致 play 无效果）
      try {
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse('')));
      } catch (_) {}
      await _audioPlayer.setFilePath(path);
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

  Future<void> _speakWithAi(String text) async {
    if (_currentVoice == null) return;

    try {
      final provider = _currentVoice!.aiModelProvider;
      String? apiResult;

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

      if (apiResult != null) {
        await _speakWithSystem(text);
      }
    } catch (e) {
      await _speakWithSystem(text);
    }
  }

  Future<String?> _callOpenAitts(String text) async {
    if (_currentVoice == null) return null;

    final endpoint = _currentVoice!.aiEndpoint.isNotEmpty
        ? _currentVoice!.aiEndpoint
        : 'https://api.openai.com/v1/audio/speech';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer ${_currentVoice!.aiApiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _currentVoice!.aiModelName.isNotEmpty ? _currentVoice!.aiModelName : 'tts-1',
          'input': text,
          'voice': _currentVoice!.systemVoiceId.isNotEmpty ? _currentVoice!.systemVoiceId : 'alloy',
          'response_format': 'mp3',
          'speed': _currentVoice!.speed,
        }),
      );

      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final file = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
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
    if (_currentVoice?.type == VoiceType.custom && _currentVoice!.customVoicePath.isNotEmpty) {
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
    if (_currentVoice?.type == VoiceType.custom && _currentVoice!.customVoicePath.isNotEmpty) {
      _audioPlayer.play();
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
    await _audioPlayer.stop();
    final result = await _flutterTts.stop();
    if (result == 1) {
      _state = TtsState.stopped;
      _stateController.add(TtsState.stopped);
    }
  }

  /// 设置速度并实时生效
  Future<void> setSpeed(double userSpeed) async {
    // 更新当前音色的速度
    if (_currentVoice != null) {
      _currentVoice!.speed = userSpeed;
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
