import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
    
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> showUpdateNotification(String animeTitle, String episodeTitle) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'anime_updates', 
      '追番更新',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      animeTitle.hashCode, 
      '《$animeTitle》更新啦！', 
      '最新剧集: $episodeTitle', 
      details,
    );
  }
}
