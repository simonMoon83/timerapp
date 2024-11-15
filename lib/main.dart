import 'dart:async';
import 'dart:ui';
import 'settings_page.dart';  // 이 줄을 추가
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  await initializeNotifications();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'timer_channel',
      initialNotificationTitle: 'Timer App',
      initialNotificationContent: 'Running in background',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  await service.startService();
}

Future<void> initializeNotifications() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "Timer App",
          content: "Timer is running",
        );
      }
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timer App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const TimerPage(),
    );
  }
}

class TimerPage extends StatefulWidget {
  const TimerPage({Key? key}) : super(key: key);

  @override
  _TimerPageState createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {
  Timer? _timer;
  int _timeInSeconds = 0;
  int _selectedTime = 15 * 60;
  bool _isRunning = false;
  late SharedPreferences _prefs;
  List<int> _timePresets = [15, 30, 45, 60];  // 추가

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrefs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedState();
    _loadTimePresets();  // 추가
  }

  // 새로운 메서드 추가
  void _loadTimePresets() {
    setState(() {
      _timePresets = _prefs.getStringList('timePresets')?.map(int.parse).toList() ?? [15, 30, 45, 60];
    });
  }  

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveState();
    } else if (state == AppLifecycleState.resumed) {
      _loadSavedState();
    }
  }

  Future<void> _saveState() async {
    await _prefs.setInt('timeInSeconds', _timeInSeconds);
    await _prefs.setInt('selectedTime', _selectedTime);
    await _prefs.setBool('isRunning', _isRunning);
  }

  void _loadSavedState() {
    setState(() {
      _timeInSeconds = _prefs.getInt('timeInSeconds') ?? _selectedTime;
      _selectedTime = _prefs.getInt('selectedTime') ?? 15 * 60;
      _isRunning = _prefs.getBool('isRunning') ?? false;
      if (_isRunning) {
        _startTimer();
      }
    });
  }

  void _startTimer() {
    if (!_isRunning) {
      _timeInSeconds = _timeInSeconds > 0 ? _timeInSeconds : _selectedTime;
      _isRunning = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_timeInSeconds > 0) {
            _timeInSeconds--;
            _saveState();
          } else {
            _stopTimer();
            _showNotification('Timer Finished', 'Your timer has completed.');
          }
        });
      });
    }
  }

  void _stopTimer() {
    setState(() {
      _timer?.cancel();
      _isRunning = false;
      _saveState();
    });
  }

  void _resetTimer() {
    setState(() {
      _timer?.cancel();
      _timeInSeconds = _selectedTime;
      _isRunning = false;
      _saveState();
    });
  }

  void _addTime(int minutes) {
    setState(() {
      if (_isRunning) {
        _timeInSeconds += minutes * 60;
      } else {
        _selectedTime = minutes * 60;
        _timeInSeconds = _selectedTime;
      }
      _saveState();
    });
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'timer_notification',
      'Timer Notifications',
      channelDescription: 'Notification channel for timer',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await FlutterLocalNotificationsPlugin().show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  String _formatTime(int timeInSeconds) {
    int minutes = timeInSeconds ~/ 60;
    int seconds = timeInSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Timer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
              if (result != null) {
                setState(() {
                  _timePresets = result;
                });
              }
            },
          ),
        ],        
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 300), // 애니메이션 지속 시간
                      curve: Curves.easeInOut, // 부드러운 애니메이션 커브
                      tween: Tween<double>(
                        begin: (_timeInSeconds + 1) / (_selectedTime == 0 ? 1 : _selectedTime),
                        end: _timeInSeconds / (_selectedTime == 0 ? 1 : _selectedTime),
                      ),
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey[800],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isRunning ? Colors.blue : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(_timeInSeconds),
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_isRunning)
                        Text(
                          'Remaining',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[400],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _timePresets.map((minutes) => _buildTimeButton(minutes)).toList(),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: Icons.refresh,
                      onPressed: _resetTimer,
                      label: 'Reset',
                    ),
                    _buildMainButton(),
                    _buildControlButton(
                      icon: Icons.stop,
                      onPressed: _stopTimer,
                      label: 'Stop',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          onPressed: onPressed,
          iconSize: 32,
          color: Colors.white,
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildMainButton() {
    return GestureDetector(
      onTap: _isRunning ? _stopTimer : _startTimer,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRunning ? Colors.red : Colors.green,
        ),
        child: Icon(
          _isRunning ? Icons.pause : Icons.play_arrow,
          size: 40,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTimeButton(int minutes) {
    final bool isSelected = _selectedTime == minutes * 60;
    return ElevatedButton(
      onPressed: () => _addTime(minutes),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: Text(
        '$minutes min',
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}