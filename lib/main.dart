import 'dart:async';
import 'dart:ui';
import 'settings_page.dart';  // 이 줄을 추가
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:logging/logging.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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
      isForegroundMode: false,  // 포그라운드 모드 비활성화
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
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
      if (notificationResponse.notificationResponseType ==
              NotificationResponseType.selectedNotificationAction &&
          notificationResponse.actionId == 'stop_alarm') {
        // 알림음 중지
        await AlarmPlayer().stopAlarm();
        // 알림 제거
        await flutterLocalNotificationsPlugin.cancel(0);
      }
    },
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();

  // 서비스가 포그라운드로 전환되는 부분 제거
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    // 백그라운드에서 타이머 로직 구현
    // 필요에 따라 알림을 설정할 수 있습니다.
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

class AlarmPlayer {
  static final AlarmPlayer _instance = AlarmPlayer._internal();
  factory AlarmPlayer() => _instance;
  AlarmPlayer._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAlarmPlaying = false;

  Future<void> initialize() async {
    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.setSource(AssetSource('alarm/alarm.mp3'));
  }

  Future<void> playAlarm() async {
    if (!_isAlarmPlaying) {
      await _audioPlayer.resume();
      _isAlarmPlaying = true;
    }
  }

  Future<void> stopAlarm() async {
    if (_isAlarmPlaying) {
      await _audioPlayer.stop();
      _isAlarmPlaying = false;
    }
  }

  bool get isAlarmPlaying => _isAlarmPlaying;
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
    _setupNotificationChannel(); // 추가
    AlarmPlayer().initialize(); // AlarmPlayer 초기화 호출
  }

  @override
  void dispose() {
    // AlarmPlayer 정리 추가
    AlarmPlayer().stopAlarm();
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
            _showNotification('타이머 종료', '타이머가 완료되었습니다.');
          }
        });
      });
    }
  }

  void _stopTimer() async {
    setState(() {
      _timer?.cancel();
      _isRunning = false;
      _saveState();
    });
    // 알림음 중지
    await AlarmPlayer().stopAlarm();
    // 알림 제거
    await flutterLocalNotificationsPlugin.cancel(0);
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
    try {
      await AlarmPlayer().playAlarm();

      // 알림 클릭 시 알림음 중지를 위한 액션 추가
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'timer_notification',
        'Timer Notifications',
        channelDescription: 'Notification channel for timer',
        importance: Importance.max,
        priority: Priority.high,
        sound: null, // 시스템 알림음 비활성화
        playSound: false,  // 시스템 알림음 비활성화
        enableVibration: true,
        ongoing: true,  // 알림을 지속적으로 표시
        autoCancel: false,  // 자동으로 알림이 사라지지 않도록 설정
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'stop_alarm',
            '알림음 중지',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        platformChannelSpecifics,
        payload: 'timer_completed',
      );
    } catch (e, stackTrace) {
      final logger = Logger('TimerNotification');
      logger.severe('Error playing audio: $e', e, stackTrace);
    }
  }

  // 새로운 메서드 추가
  Future<void> _setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'timer_notification',
      'Timer Notifications',
      description: 'Notification channel for timer',
      importance: Importance.max,
      playSound: false, // 시스템 알림음 비활성화
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
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
