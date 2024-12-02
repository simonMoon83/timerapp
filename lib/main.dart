import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:math';
import 'settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart' hide AudioContext;
import 'package:logging/logging.dart';
import 'package:audio_session/audio_session.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  await initializeNotifications();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  try {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'timer_service',
        initialNotificationTitle: '타이머',
        initialNotificationContent: '준비',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    service.startService();
  } catch (e) {
    debugPrint('Error initializing background service: $e');
  }
}

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) {
      // 알림 탭 했을 때의 동작
    },
  );

  // Android 13 이상에서 알림 권한 요청
  if (Platform.isAndroid) {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }
}

Future<void> showBackgroundNotification(String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'timer_notification',
    'Timer Notifications',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
  );

  const DarwinNotificationDetails iOSPlatformChannelSpecifics =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iOSPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    platformChannelSpecifics,
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    final prefs = await SharedPreferences.getInstance();
    final player = AlarmPlayer();
    await player.initialize();

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        if (service is AndroidServiceInstance) {
          int timeInSeconds = prefs.getInt('timeInSeconds') ?? 0;
          bool isRunning = prefs.getBool('isRunning') ?? false;

          if (isRunning && timeInSeconds > 0) {
            timeInSeconds--;
            await prefs.setInt('timeInSeconds', timeInSeconds);

            // 알림 업데이트
            service.setForegroundNotificationInfo(
              title: '타이머 실행 중',
              content: '남은 시간: ${_formatTime(timeInSeconds)}',
            );

            // 타이머 종료시 알림
            if (timeInSeconds == 0) {
              await showBackgroundNotification(
                '타이머 종료',
                '타이머가 완료되었습니다.',
              );
              await player
                  .playAlarm(prefs.getString('currentSound') ?? 'alarm1');
              await prefs.setBool('isRunning', false);
              timer.cancel();
            }
          }
        }
      } catch (e) {
        debugPrint('Timer error: $e');
      }
    });
  } catch (e) {
    debugPrint('Background service error: $e');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

String _formatTime(int timeInSeconds) {
  int minutes = timeInSeconds ~/ 60;
  int seconds = timeInSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

  AudioPlayer? _audioPlayer;
  bool _isAlarmPlaying = false;
  String _currentSound = 'alarm1';

  Future<void> initialize() async {
    try {
      _audioPlayer?.dispose();
      _audioPlayer = AudioPlayer();
      await _audioPlayer?.setVolume(1.0);
      await _audioPlayer?.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer?.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (e) {
      print('Error initializing audio: $e');
    }
  }

  Future<void> playAlarm([String? sound]) async {
    try {
      if (!_isAlarmPlaying) {
        if (sound != null) {
          _currentSound = sound;
        }

        await initialize();
        await _audioPlayer?.play(
          AssetSource('sounds/$_currentSound.mp3'),
          mode: PlayerMode.mediaPlayer,
        );
        _isAlarmPlaying = true;
      }
    } catch (e) {
      print('Error playing alarm: $e');
      // 오류 발생시 재시도
      await Future.delayed(Duration(milliseconds: 500));
      await initialize();
      try {
        await _audioPlayer?.play(
          AssetSource('sounds/$_currentSound.mp3'),
          mode: PlayerMode.mediaPlayer,
        );
        _isAlarmPlaying = true;
      } catch (e) {
        print('Error on retry: $e');
      }
    }
  }

  Future<void> stopAlarm() async {
    try {
      if (_isAlarmPlaying) {
        await _audioPlayer?.stop();
        await _audioPlayer?.dispose();
        _audioPlayer = null;
        _isAlarmPlaying = false;
      }
    } catch (e) {
      print('Error stopping alarm: $e');
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
  late SharedPreferences _prefs;
  int _timeInSeconds = 15 * 60;
  int _selectedTime = 15 * 60;
  bool _isRunning = false;
  int _currentPresetIndex = 0;
  List<int> _timePresets = [];
  List<String> _soundPresets = List.filled(4, 'alarm1');
  AlarmPlayer _alarmPlayer = AlarmPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alarmPlayer.initialize();
    _setupNotificationChannel();
    _initPrefs().then((_) {
      _loadSavedValues();
    });
  }

  @override
  void dispose() {
    _alarmPlayer.stopAlarm();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  void _loadTimePresets() {
    setState(() {
      _timePresets =
          _prefs.getStringList('timePresets')?.map(int.parse).toList() ??
              [15, 30, 45, 60];
      _soundPresets =
          _prefs.getStringList('soundPresets') ?? List.filled(4, 'alarm1');
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

  Future<void> _loadSavedValues() async {
    final savedTimePresets = _prefs.getStringList('timePresets');
    final savedSoundPresets = _prefs.getStringList('soundPresets');
    final savedCurrentIndex = _prefs.getInt('currentPresetIndex') ?? 0;

    setState(() {
      if (savedTimePresets != null) {
        try {
          _timePresets = savedTimePresets.map(int.parse).toList();
        } catch (e) {
          print('Error parsing time presets: $e');
          _timePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
        }
      }

      if (savedSoundPresets != null) {
        _soundPresets = savedSoundPresets;
        if (_soundPresets.isNotEmpty) {
          _alarmPlayer.setSound(_soundPresets[0]);
        }
      }

      // 현재 선택된 프리셋 인덱스 업데이트
      _currentPresetIndex = savedCurrentIndex.clamp(0, _timePresets.length - 1);

      // 타이머가 실행중이 아닐 때만 선택된 시간 업데이트
      if (!_isRunning) {
        _selectedTime = _timePresets[_currentPresetIndex];
        _timeInSeconds = _selectedTime;
      }
    });
  }

  Future<void> _openSettings() async {
    // 현재 타이머 상태 저장
    final wasRunning = _isRunning;
    if (_isRunning) {
      _stopTimer();
    }

    // 설정 페이지로 이동
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );

    // 설정 페이지에서 돌아온 후 상태 업데이트
    await _loadSavedValues();

    // 타이머가 실행 중이었다면 재시작
    if (wasRunning) {
      _startTimer();
    }
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
            _alarmPlayer.playAlarm(_soundPresets[_currentPresetIndex]);
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('타이머 종료'),
                  content: const Text('타이머가 완료되었습니다.'),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('확인'),
                      onPressed: () {
                        _alarmPlayer.stopAlarm();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
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
    await _alarmPlayer.stopAlarm();
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
        _selectedTime = _timeInSeconds; // 시간이 추가될 때 selectedTime도 업데이트
      }
      _saveState();
    });
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      String selectedSound = _soundPresets[_currentPresetIndex];
      await _alarmPlayer.playAlarm(selectedSound);

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
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  String _formatTime(int timeInSeconds) {
    int minutes = timeInSeconds ~/ 60;
    int seconds = timeInSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
            onPressed: _openSettings,
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
                  children: _timePresets
                      .map((minutes) => _buildTimeButton(minutes))
                      .toList(),
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
}
