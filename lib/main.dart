import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  // ✅ Khởi tạo notification plugin
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notificationsPlugin.initialize(initSettings);

  // ✅ Xin quyền thông báo và exact alarm (Android 13+)
  final androidImpl = notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
  await androidImpl?.requestExactAlarmsPermission();

  runApp(const ReminderApp());
}

class ReminderApp extends StatelessWidget {
  const ReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reminder App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const ReminderPage(),
    );
  }
}

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});
  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final TextEditingController _titleController = TextEditingController();
  DateTime? _selectedTime;
  List<Map<String, dynamic>> _reminders = [];

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('reminders') ?? [];
    setState(() {
      _reminders = data
          .map((e) => Map<String, dynamic>.from(jsonDecode(e)))
          .toList();
    });
  }

  Future<void> _saveReminder(String title, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    final reminder = {'title': title, 'time': time.toIso8601String()};
    final list = prefs.getStringList('reminders') ?? [];
    list.add(jsonEncode(reminder));
    await prefs.setStringList('reminders', list);
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _selectedTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _scheduleNotification() async {
    if (_titleController.text.isEmpty || _selectedTime == null) return;

    final title = _titleController.text;
    final time = _selectedTime!;
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await notificationsPlugin.zonedSchedule(
      id,
      'Reminder',
      title,
      tz.TZDateTime.from(time, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Reminders',
          channelDescription: 'Channel for reminder notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
      payload: title,
    );

    await _saveReminder(title, time);
    await _loadReminders();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏰ Reminder scheduled!')),
      );
    }

    _titleController.clear();
    setState(() => _selectedTime = null);
  }

  Future<void> _showNow() async {
    await notificationsPlugin.show(
      9999,
      'Test Notification',
      'This is a test message 🎉',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Tests',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _clearReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reminders');
    setState(() => _reminders.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearReminders,
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Reminder Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTime == null
                        ? 'No time selected'
                        : 'Selected: ${_selectedTime!.toString().substring(0, 16)}',
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _pickDateTime(context),
                  child: const Text('Pick Time'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text('Set Reminder'),
              onPressed: _scheduleNotification,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.alarm_on),
              label: const Text('Test Now'),
              onPressed: _showNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 25),
            const Divider(),
            Expanded(
              child: _reminders.isEmpty
                  ? const Center(child: Text('No reminders yet.'))
                  : ListView.builder(
                      itemCount: _reminders.length,
                      itemBuilder: (context, index) {
                        final item = _reminders[index];
                        final t = DateTime.parse(item['time']);
                        return ListTile(
                          leading: const Icon(Icons.alarm),
                          title: Text(item['title']),
                          subtitle: Text(
                              '${t.day}/${t.month}/${t.year} ${t.hour}:${t.minute.toString().padLeft(2, '0')}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
