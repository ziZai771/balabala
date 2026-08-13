import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 朗读通知栏：朗读中显示"正在朗读"，暂停显示"已暂停"。
/// 点按通知回到书中朗读位置（通过 payload 携带书 ID + 位置）。
class TtsNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _id = 9901;
  static const String _channelId = 'tts_playing';

  /// 通知点按回调（由 main.dart 注入，payload 为 JSON）
  static void Function(String payload)? onTap;

  static Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        onTap?.call(response.payload ?? '');
      },
    );
  }

  static Future<void> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  static Future<void> show({
    required String bookTitle,
    required bool playing,
    required String payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        '朗读',
        channelDescription: 'AI 朗读进行中',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
        onlyAlertOnce: true,
      ),
    );
    await _plugin.show(
      _id,
      playing ? '正在朗读' : '已暂停',
      bookTitle,
      details,
      payload: payload,
    );
  }

  static Future<void> hide() async {
    await _plugin.cancel(_id);
  }
}
