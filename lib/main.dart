import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/book_provider.dart';
import 'providers/voice_provider.dart';
import 'providers/reading_provider.dart';
import 'providers/app_provider.dart';
import 'services/storage_service.dart';
import 'services/tts_service.dart';
import 'services/tts_notification.dart';
import 'screens/home_screen.dart';
import 'screens/reader_screen.dart';

/// 全局导航 key：通知点按后跳转到指定书籍的阅读页
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 通知点按/冷启动：解析 payload 回到书中朗读位置
void _openBookFromNotification(String payload) {
  if (payload.isEmpty) return;
  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final bookId = data['id'] as String?;
    if (bookId == null) return;
    final book = StorageService().getBook(bookId);
    if (book == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      // App 尚未构建完成：等首帧后再跳
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openBookFromNotification(payload);
      });
      return;
    }
    nav.push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          book: book,
          restoreTtsCharIndex: data['char'] as int?,
          restoreTtsText: data['text'] as String?,
        ),
      ),
    );
  } catch (_) {
    // payload 解析失败则忽略（只打开 App 默认页）
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  await StorageService().init();
  await TtsService().init();
  await TtsNotification.init();
  await TtsNotification.requestPermission();
  TtsNotification.onTap = _openBookFromNotification;

  // 处理 App 被通知冷启动的场景
  final launchDetails = await FlutterLocalNotificationsPlugin()
      .getNotificationAppLaunchDetails();
  final launchPayload = launchDetails?.notificationResponse?.payload ?? '';

  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const BalabalaApp());

  if (launchPayload.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openBookFromNotification(launchPayload);
    });
  }
}

class BalabalaApp extends StatelessWidget {
  const BalabalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BookProvider()),
        ChangeNotifierProvider(create: (_) {
          final provider = VoiceProvider();
          provider.addDefaultVoices();
          return provider;
        }),
        ChangeNotifierProvider(create: (_) => ReadingProvider()),
        ChangeNotifierProvider(create: (_) => AppProvider()),
      ],
      child: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          return MaterialApp(
            title: '吧啦吧啦',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
