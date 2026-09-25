import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'product_model.dart';

class NotificationService {
  static const _trackedItemsKey = 'expiry_notification_item_ids';
  static const _channelId = 'pantry_expiry_alerts';
  static const weeklyReminderId = 2147483000;
  static const _weeklyDayKey = 'weekly_pantry_check_day';
  static const _weeklyHourKey = 'weekly_pantry_check_hour';
  static const _weeklyMinuteKey = 'weekly_pantry_check_minute';
  static const _weeklyEnabledKey = 'weekly_pantry_check_enabled';
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _openedFromWeeklyReminder = false;
  static Future<void> Function()? onWeeklyReminderOpened;
  static Future<void> Function()? onWeeklyReminderClosed;

  static bool get openedFromWeeklyReminder => _openedFromWeeklyReminder;

  static const _alerts = <({int index, int days, String message})>[
    (index: 0, days: 30, message: 'expires in 1 month.'),
    (index: 1, days: 15, message: 'expires in 15 days.'),
    (index: 2, days: 7, message: 'expires in 1 week.'),
    (index: 3, days: 3, message: 'expires in 3 days.'),
    (index: 4, days: 1, message: 'expires tomorrow.'),
    (index: 5, days: 0, message: 'expires today.'),
    (index: 6, days: -1, message: 'expired yesterday. Please check your pantry.'),
  ];

  static Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        if (response.id == weeklyReminderId) {
          onWeeklyReminderOpened?.call();
        }
      },
    );
    final launchDetails = await _notifications.getNotificationAppLaunchDetails();
    _openedFromWeeklyReminder =
        launchDetails?.didNotificationLaunchApp == true &&
        launchDetails?.notificationResponse?.id == weeklyReminderId;
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await scheduleWeeklyPantryReminder();

    _initialized = true;
  }

  static Future<void> scheduleWeeklyPantryReminder() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_weeklyEnabledKey) ?? true)) {
      await _notifications.cancel(weeklyReminderId);
      return;
    }
    final weekday = prefs.getInt(_weeklyDayKey) ?? DateTime.monday;
    final hour = prefs.getInt(_weeklyHourKey) ?? 9;
    final minute = prefs.getInt(_weeklyMinuteKey) ?? 0;
    final now = tz.TZDateTime.now(tz.local);
    var nextSunday = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    while (nextSunday.weekday != weekday || !nextSunday.isAfter(now)) {
      nextSunday = nextSunday.add(const Duration(days: 1));
    }

    await _notifications.cancel(weeklyReminderId);
    await _notifications.zonedSchedule(
      weeklyReminderId,
      'Pantry Pulse Weekly Check',
      'Review your pantry and upcoming expiry dates.',
      nextSunday,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Pantry expiry alerts',
          channelDescription: 'Alerts for pantry items nearing expiry',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static Future<void> saveWeeklySchedule({
    required int weekday,
    required int hour,
    required int minute,
    bool enabled = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_weeklyEnabledKey, enabled);
    await prefs.setInt(_weeklyDayKey, weekday);
    await prefs.setInt(_weeklyHourKey, hour);
    await prefs.setInt(_weeklyMinuteKey, minute);
    await scheduleWeeklyPantryReminder();
  }

  static Future<({int weekday, int hour, int minute, bool enabled})>
      getWeeklySchedule() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      weekday: prefs.getInt(_weeklyDayKey) ?? DateTime.monday,
      hour: prefs.getInt(_weeklyHourKey) ?? 9,
      minute: prefs.getInt(_weeklyMinuteKey) ?? 0,
      enabled: prefs.getBool(_weeklyEnabledKey) ?? true,
    );
  }

  static Future<void> syncProducts(List<Product> products) async {
    if (!_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final previousIds = prefs.getStringList(_trackedItemsKey) ?? <String>[];
    final currentIds = products.map((product) => product.id).toSet();

    for (final removedId in previousIds.where((id) => !currentIds.contains(id))) {
      await cancelProductNotifications(removedId);
    }

    for (final product in products) {
      await scheduleProductNotifications(product);
    }

    await prefs.setStringList(_trackedItemsKey, currentIds.toList());
  }

  static Future<void> scheduleProductNotifications(Product product) async {
    await cancelProductNotifications(product.id);
    final expiry = _parseDate(product.exp);
    if (expiry == null) return;

    final expiryDate = tz.TZDateTime(tz.local, expiry.year, expiry.month, expiry.day);
    final now = tz.TZDateTime.now(tz.local);

    final today = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    if (expiryDate.isBefore(today)) {
      await _notifications.zonedSchedule(
        _notificationId(product.id, 6),
        'Pantry Expiry Alert',
        '${product.name.trim().isEmpty ? 'Your pantry item' : product.name} expired. Please check your pantry.',
        now.add(const Duration(seconds: 1)),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Pantry expiry alerts',
            channelDescription: 'Alerts for pantry items nearing expiry',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return;
    }

    for (final alert in _alerts) {
      final alertDate = tz.TZDateTime(
        tz.local,
        expiryDate.year,
        expiryDate.month,
        expiryDate.day,
        9,
      ).add(Duration(days: -alert.days));

      final isToday = alertDate.year == now.year &&
          alertDate.month == now.month &&
          alertDate.day == now.day;
      if (!alertDate.isAfter(now)) {
        if (isToday && alert.days >= 0) {
          await _scheduleImmediate(product, alert.index, alert.message);
        }
        continue;
      }

      await _notifications.zonedSchedule(
        _notificationId(product.id, alert.index),
        'Pantry Expiry Alert',
        '${product.name.trim().isEmpty ? 'Your pantry item' : product.name} ${alert.message}',
        alertDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Pantry expiry alerts',
            channelDescription: 'Alerts for pantry items nearing expiry',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static Future<void> _scheduleImmediate(
    Product product,
    int alertIndex,
    String message,
  ) async {
    await _notifications.zonedSchedule(
      _notificationId(product.id, alertIndex),
      'Pantry Expiry Alert',
      '${product.name.trim().isEmpty ? 'Your pantry item' : product.name} $message',
      tz.TZDateTime.now(tz.local).add(const Duration(seconds: 1)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Pantry expiry alerts',
          channelDescription: 'Alerts for pantry items nearing expiry',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelProductNotifications(String productId) async {
    for (var index = 0; index < _alerts.length; index++) {
      await _notifications.cancel(_notificationId(productId, index));
    }
  }

  static int _notificationId(String productId, int alertIndex) {
    var hash = 2166136261;
    for (final codeUnit in productId.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    return (hash % 200000000) * 10 + alertIndex;
  }

  static DateTime? _parseDate(String value) {
    final input = value.trim();
    if (input.isEmpty || input.toLowerCase() == 'not detected') return null;

    final match = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(input);
    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;

    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }
}