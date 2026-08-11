class VoiceProfile {
  final String id;
  String name;
  VoiceType type;
  String language;
  double speed;
  double pitch;
  double volume;
  String systemVoiceId;
  String customVoicePath;
  String aiModelProvider;
  String aiApiKey;
  String aiModelName;
  String aiEndpoint;
  bool enableEmotion;
  bool isDefault;
  DateTime createdAt;

  VoiceProfile({
    required this.id,
    this.name = '',
    this.type = VoiceType.system,
    this.language = 'zh-CN',
    this.speed = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.systemVoiceId = '',
    this.customVoicePath = '',
    this.aiModelProvider = '',
    this.aiApiKey = '',
    this.aiModelName = '',
    this.aiEndpoint = '',
    this.enableEmotion = false,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'type': type.index,
    'language': language, 'speed': speed, 'pitch': pitch,
    'volume': volume, 'systemVoiceId': systemVoiceId,
    'customVoicePath': customVoicePath,
    'aiModelProvider': aiModelProvider, 'aiApiKey': aiApiKey,
    'aiModelName': aiModelName, 'aiEndpoint': aiEndpoint,
    'enableEmotion': enableEmotion, 'isDefault': isDefault,
    'createdAt': createdAt.toIso8601String(),
  };

  factory VoiceProfile.fromMap(Map<String, dynamic> map) => VoiceProfile(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    type: VoiceType.values[map['type'] ?? 0],
    language: map['language'] ?? 'zh-CN',
    speed: (map['speed'] ?? 1.0).toDouble(),
    pitch: (map['pitch'] ?? 1.0).toDouble(),
    volume: (map['volume'] ?? 1.0).toDouble(),
    systemVoiceId: map['systemVoiceId'] ?? '',
    customVoicePath: map['customVoicePath'] ?? '',
    aiModelProvider: map['aiModelProvider'] ?? '',
    aiApiKey: map['aiApiKey'] ?? '',
    aiModelName: map['aiModelName'] ?? '',
    aiEndpoint: map['aiEndpoint'] ?? '',
    enableEmotion: map['enableEmotion'] ?? false,
    isDefault: map['isDefault'] ?? false,
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
  );
}

enum VoiceType { system, custom, ai }
