class AppConstants {
  static const String appName = '吧啦吧啦';
  static const String appVersion = '1.0.0';

  // 存储键
  static const String prefFirstLaunch = 'first_launch';
  static const String prefDarkMode = 'dark_mode';
  static const String prefLastReadBookId = 'last_read_book_id';

  // 默认值
  static const double defaultFontSize = 18.0;
  static const double minFontSize = 12.0;
  static const double maxFontSize = 36.0;
  static const double defaultLineHeight = 1.8;

  // 自动加入书架
  static const int autoBookshelfChapterCount = 3;

  // 缓存
  static const int maxCacheSizeMB = 500;

  // 动画
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);
  static const Duration pageTransitionDuration = Duration(milliseconds: 350);

  // 图标URL（免费可商用图标）
  static const String appIconUrl = 'https://img.icons8.com/fluency/96/book.png';
  static const String defaultCoverUrl = 'https://img.icons8.com/fluency/96/book.png';

  // 免费音色配置（系统TTS预设）
  static const List<Map<String, dynamic>> defaultVoices = [
    {'name': '标准女声', 'pitch': 1.2, 'speed': 1.0},
    {'name': '标准男声', 'pitch': 0.8, 'speed': 1.0},
    {'name': '温柔女声', 'pitch': 1.3, 'speed': 0.9},
    {'name': '深沉男声', 'pitch': 0.7, 'speed': 0.8},
    {'name': '童声', 'pitch': 1.5, 'speed': 1.1},
  ];
}
