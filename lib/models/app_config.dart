class AppConfig {
  bool darkMode;
  String locale;
  bool autoDetectEncoding;
  bool ttsAutoRead;
  bool ttsReadOnOpen;
  int ttsReadDelayMs;
  double ttsDefaultSpeed;
  bool wifiOnlyDownload;
  int maxCacheSize;
  bool showOnboarding;
  String lastExportPath;
  String lastImportPath;

  AppConfig({
    this.darkMode = false,
    this.locale = 'zh',
    this.autoDetectEncoding = true,
    this.ttsAutoRead = false,
    this.ttsReadOnOpen = false,
    this.ttsReadDelayMs = 500,
    this.ttsDefaultSpeed = 1.0,
    this.wifiOnlyDownload = true,
    this.maxCacheSize = 500,
    this.showOnboarding = true,
    this.lastExportPath = '',
    this.lastImportPath = '',
  });

  Map<String, dynamic> toMap() => {
    'darkMode': darkMode, 'locale': locale,
    'autoDetectEncoding': autoDetectEncoding,
    'ttsAutoRead': ttsAutoRead, 'ttsReadOnOpen': ttsReadOnOpen,
    'ttsReadDelayMs': ttsReadDelayMs,
    'ttsDefaultSpeed': ttsDefaultSpeed,
    'wifiOnlyDownload': wifiOnlyDownload,
    'maxCacheSize': maxCacheSize, 'showOnboarding': showOnboarding,
    'lastExportPath': lastExportPath, 'lastImportPath': lastImportPath,
  };

  factory AppConfig.fromMap(Map<String, dynamic> map) => AppConfig(
    darkMode: map['darkMode'] ?? false,
    locale: map['locale'] ?? 'zh',
    autoDetectEncoding: map['autoDetectEncoding'] ?? true,
    ttsAutoRead: map['ttsAutoRead'] ?? false,
    ttsReadOnOpen: map['ttsReadOnOpen'] ?? false,
    ttsReadDelayMs: map['ttsReadDelayMs'] ?? 500,
    ttsDefaultSpeed: (map['ttsDefaultSpeed'] ?? 1.0).toDouble(),
    wifiOnlyDownload: map['wifiOnlyDownload'] ?? true,
    maxCacheSize: map['maxCacheSize'] ?? 500,
    showOnboarding: map['showOnboarding'] ?? true,
    lastExportPath: map['lastExportPath'] ?? '',
    lastImportPath: map['lastImportPath'] ?? '',
  );
}
