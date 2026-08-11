import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/voice_profile.dart';
import '../services/storage_service.dart';

class VoiceProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final _uuid = const Uuid();

  List<VoiceProfile> _voices = [];
  List<VoiceProfile> get voices => _voices;

  VoiceProfile? _currentVoice;
  VoiceProfile? get currentVoice => _currentVoice;

  final bool _isLoading = false;
  bool get isLoading => _isLoading;

  VoiceProvider() {
    loadVoices();
  }

  void loadVoices() {
    _voices = _storage.getAllVoices();
    _currentVoice = _storage.getDefaultVoice();
    notifyListeners();
  }

  Future<void> addVoice(VoiceProfile voice) async {
    await _storage.addVoice(voice);
    _voices.add(voice);
    notifyListeners();
  }

  Future<void> updateVoice(VoiceProfile voice) async {
    await _storage.updateVoice(voice);
    notifyListeners();
  }

  Future<void> deleteVoice(String id) async {
    await _storage.deleteVoice(id);
    _voices.removeWhere((v) => v.id == id);
    if (_currentVoice?.id == id) {
      _currentVoice = null;
    }
    notifyListeners();
  }

  Future<void> setCurrentVoice(String id) async {
    await _storage.setDefaultVoice(id);
    // 同步更新内存中 voices 的 isDefault 标记，确保选择卡片正确高亮当前音色
    for (var voice in _voices) {
      voice.isDefault = voice.id == id;
    }
    _currentVoice = _storage.getVoice(id);
    notifyListeners();
  }

  /// 添加系统默认音色
  Future<void> addDefaultVoices() async {
    if (_voices.isEmpty) {
      final defaultVoices = [
        VoiceProfile(
          id: _uuid.v4(),
          name: '标准女声',
          type: VoiceType.system,
          language: 'zh-CN',
          speed: 1.0,
          pitch: 1.2,
          isDefault: true,
        ),
        VoiceProfile(
          id: _uuid.v4(),
          name: '标准男声',
          type: VoiceType.system,
          language: 'zh-CN',
          speed: 1.0,
          pitch: 0.8,
        ),
        VoiceProfile(
          id: _uuid.v4(),
          name: '温柔女声',
          type: VoiceType.system,
          language: 'zh-CN',
          speed: 0.9,
          pitch: 1.3,
        ),
        VoiceProfile(
          id: _uuid.v4(),
          name: '深沉男声',
          type: VoiceType.system,
          language: 'zh-CN',
          speed: 0.8,
          pitch: 0.7,
        ),
        VoiceProfile(
          id: _uuid.v4(),
          name: '童声',
          type: VoiceType.system,
          language: 'zh-CN',
          speed: 1.1,
          pitch: 1.5,
        ),
        VoiceProfile(
          id: _uuid.v4(),
          name: '英文标准',
          type: VoiceType.system,
          language: 'en-US',
          speed: 1.0,
          pitch: 1.0,
        ),
      ];

      for (final voice in defaultVoices) {
        await _storage.addVoice(voice);
        _voices.add(voice);
      }
      
      _currentVoice = _voices.first;
      notifyListeners();
    }
  }

  /// 添加AI音色配置
  Future<void> addAiVoice({
    required String name,
    required String provider,
    required String apiKey,
    String modelName = '',
    String endpoint = '',
    bool enableEmotion = false,
  }) async {
    final voice = VoiceProfile(
      id: _uuid.v4(),
      name: name,
      type: VoiceType.ai,
      aiModelProvider: provider,
      aiApiKey: apiKey,
      aiModelName: modelName,
      aiEndpoint: endpoint,
      enableEmotion: enableEmotion,
    );
    await addVoice(voice);
  }

  /// 添加自定义音色（上传语音样本）
  Future<void> addCustomVoice({
    required String name,
    required String voicePath,
  }) async {
    final voice = VoiceProfile(
      id: _uuid.v4(),
      name: name,
      type: VoiceType.custom,
      customVoicePath: voicePath,
    );
    await addVoice(voice);
  }
}
