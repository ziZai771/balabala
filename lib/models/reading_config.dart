class ReadingConfig {
  double fontSize;
  String fontFamily;
  double lineHeight;
  ReadingTheme theme;
  PageAnimation animation;
  bool autoScroll;
  double autoScrollSpeed;
  bool showLineNumber;
  bool nightMode;
  int screenBrightness;
  String voiceProfileId;
  bool scrollMode; // true=上下滚动, false=左右翻页

  ReadingConfig({
    this.fontSize = 18.0,
    this.fontFamily = 'System',
    this.lineHeight = 1.8,
    this.theme = ReadingTheme.classic,
    this.animation = PageAnimation.slide,
    this.autoScroll = false,
    this.autoScrollSpeed = 1.0,
    this.showLineNumber = false,
    this.nightMode = false,
    this.screenBrightness = 80,
    this.voiceProfileId = '',
    this.scrollMode = false,
  });

  Map<String, dynamic> toMap() => {
    'fontSize': fontSize, 'fontFamily': fontFamily,
    'lineHeight': lineHeight, 'theme': theme.index,
    'animation': animation.index, 'autoScroll': autoScroll,
    'autoScrollSpeed': autoScrollSpeed,
    'showLineNumber': showLineNumber, 'nightMode': nightMode,
    'screenBrightness': screenBrightness,
    'voiceProfileId': voiceProfileId,
    'scrollMode': scrollMode,
  };

  factory ReadingConfig.fromMap(Map<String, dynamic> map) => ReadingConfig(
    fontSize: (map['fontSize'] ?? 18.0).toDouble(),
    fontFamily: map['fontFamily'] ?? 'System',
    lineHeight: (map['lineHeight'] ?? 1.8).toDouble(),
    theme: ReadingTheme.values[map['theme'] ?? 0],
    animation: PageAnimation.values[map['animation'] ?? 1],
    autoScroll: map['autoScroll'] ?? false,
    autoScrollSpeed: (map['autoScrollSpeed'] ?? 1.0).toDouble(),
    showLineNumber: map['showLineNumber'] ?? false,
    nightMode: map['nightMode'] ?? false,
    screenBrightness: map['screenBrightness'] ?? 80,
    voiceProfileId: map['voiceProfileId'] ?? '',
    scrollMode: map['scrollMode'] ?? false,
  );
}

enum ReadingTheme { classic, green, dark, gray, paper }
enum PageAnimation { none, slide, curl, fade }
