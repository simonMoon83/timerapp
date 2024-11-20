import 'dart:async';
import 'dart:ui';
import 'dart:math';  // Add this line
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
  String _currentSound = 'alarm1';  // 기본값

  Future<void> initialize() async {
    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  Future<void> playAlarm([String? sound]) async {
    if (!_isAlarmPlaying) {
      if (sound != null) {
        _currentSound = sound;
      }
      await _audioPlayer.play(AssetSource('sounds/$_currentSound.mp3'));
      _isAlarmPlaying = true;
    }
  }

  Future<void> stopAlarm() async {
    if (_isAlarmPlaying) {
      await _audioPlayer.stop();
      _isAlarmPlaying = false;
    }
  }

  void setSound(String sound) {
    _currentSound = sound;
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
  List<int> _timePresets = [15, 30, 45, 60];
  List<String> _soundPresets = ['alarm1', 'alarm2', 'alarm3', 'alarm4'];
  int _currentPresetIndex = 0;  // 현재 선택된 프리셋 인덱스

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrefs();
    _setupNotificationChannel();
    AlarmPlayer().initialize();
  }

  @override
  void dispose() {
    AlarmPlayer().stopAlarm();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedState();
    _loadTimePresets();
  }

  void _loadTimePresets() {
    setState(() {
      _timePresets = _prefs.getStringList('timePresets')?.map(int.parse).toList() ?? [15, 30, 45, 60];
      _soundPresets = _prefs.getStringList('soundPresets') ?? List.filled(4, 'alarm1');
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
    await _prefs.setInt('currentPresetIndex', _currentPresetIndex);
  }

  void _loadSavedState() {
    setState(() {
      _timeInSeconds = _prefs.getInt('timeInSeconds') ?? _selectedTime;
      _selectedTime = _prefs.getInt('selectedTime') ?? 15 * 60;
      _isRunning = _prefs.getBool('isRunning') ?? false;
      _currentPresetIndex = _prefs.getInt('currentPresetIndex') ?? 0;
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
    await AlarmPlayer().stopAlarm();
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

  void _addTime(int seconds) {
    setState(() {
      if (!_isRunning) {
        _currentPresetIndex = _timePresets.indexOf(seconds);
        _selectedTime = seconds;
        _timeInSeconds = _selectedTime;
      } else {
        _timeInSeconds += seconds;
        _selectedTime = _timeInSeconds;  // 시간이 추가될 때 selectedTime도 업데이트
      }
      _saveState();
    });
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      String selectedSound = _soundPresets[_currentPresetIndex];
      await AlarmPlayer().playAlarm(selectedSound);

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'timer_notification',
        'Timer Notifications',
        channelDescription: 'Notification channel for timer',
        importance: Importance.max,
        priority: Priority.high,
        sound: null,
        playSound: false,
        enableVibration: true,
        ongoing: true,
        autoCancel: false,
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

  Future<void> _setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'timer_notification',
      'Timer Notifications',
      description: 'Notification channel for timer',
      importance: Importance.max,
      playSound: false,
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
                  _timePresets = result['timePresets'];
                  _soundPresets = result['soundPresets'];
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
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(
                        begin: _timeInSeconds / _selectedTime,
                        end: _timeInSeconds / _selectedTime,
                      ),
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value.clamp(0.0, 1.0),
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

  Widget _buildTimeButton(int seconds) {
    final bool isSelected = _selectedTime == seconds;
    String buttonText;
    if (seconds >= 60) {
      buttonText = '${seconds ~/ 60}m ${seconds % 60}s';
    } else {
      buttonText = '${seconds}s';
    }
    
    return ElevatedButton(
      onPressed: () => _addTime(seconds),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: Text(
        buttonText,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}
