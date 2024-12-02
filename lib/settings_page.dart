import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SharedPreferences _prefs;
  late List<int> _timePresets;
  late List<int> _selectedMinutes;
  late List<int> _selectedSeconds;
  late List<String> _soundPresets;
  late List<bool> _isPlayingList;
  final _audioPlayer = AudioPlayer();
  final List<String> _availableSounds = [
    'alarm1',
    'alarm2',
    'alarm3',
    'alarm4'
  ];
  Future<bool>? _initializationFuture;

  @override
  void initState() {
    super.initState();
    _isPlayingList = List.filled(4, false);
    _initializationFuture = _initializeSettings();
  }

  Future<bool> _initializeSettings() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final savedTimePresets = _prefs.getStringList('timePresets');
      final savedSoundPresets = _prefs.getStringList('soundPresets');

      print('Loading saved values:');
      print('Time presets: $savedTimePresets');
      print('Sound presets: $savedSoundPresets');

      // Initialize time presets
      if (savedTimePresets != null) {
        try {
          _timePresets = savedTimePresets.map(int.parse).toList();
        } catch (e) {
          print('Error parsing time presets: $e');
          _timePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
        }
      } else {
        _timePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
      }

      // Initialize minutes and seconds
      _selectedMinutes = List.filled(4, 0);
      _selectedSeconds = List.filled(4, 0);
      for (int i = 0; i < _timePresets.length; i++) {
        _selectedMinutes[i] = _timePresets[i] ~/ 60;
        _selectedSeconds[i] = _timePresets[i] % 60;
      }

      // Initialize sound presets
      _soundPresets = savedSoundPresets ?? List.filled(4, 'alarm1');

      print('Initialized values:');
      print('Time presets: $_timePresets');
      print('Minutes: $_selectedMinutes');
      print('Seconds: $_selectedSeconds');
      print('Sound presets: $_soundPresets');

      await _initAudioPlayer();
      return true;
    } catch (e) {
      print('Error during initialization: $e');
      return false;
    }
  }

  Future<void> _initAudioPlayer() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _resetToDefaults() async {
    // Stop any playing audio
    await _audioPlayer.stop();

    final defaultTimePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
    final defaultSoundPresets = List.filled(4, 'alarm1');

    setState(() {
      _timePresets = defaultTimePresets;
      _soundPresets = defaultSoundPresets;
      _isPlayingList = List.filled(4, false);

      for (int i = 0; i < _timePresets.length; i++) {
        _selectedMinutes[i] = _timePresets[i] ~/ 60;
        _selectedSeconds[i] = _timePresets[i] % 60;
      }
    });

    // Save default values to SharedPreferences
    await _prefs.setStringList(
        'timePresets', defaultTimePresets.map((e) => e.toString()).toList());
    await _prefs.setStringList('soundPresets', defaultSoundPresets);

    if (mounted) {
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Center(
            child: Text(
              'Settings have been reset to defaults',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );

      // Pop back to main page with refresh flag
      Navigator.pop(context, true);
    }
  }

  Future<void> _savePresets() async {
    try {
      // 현재 선택된 시간을 초로 변환하여 저장
      List<String> timePresetStrings = [];
      for (int i = 0; i < 4; i++) {
        int totalSeconds = _selectedMinutes[i] * 60 + _selectedSeconds[i];
        timePresetStrings.add(totalSeconds.toString());
      }

      print('Saving timePresets: $timePresetStrings');
      print('Saving soundPresets: $_soundPresets');

      // SharedPreferences에 저장
      final timeResult =
          await _prefs.setStringList('timePresets', timePresetStrings);
      final soundResult =
          await _prefs.setStringList('soundPresets', _soundPresets);

      print('Save results - Time: $timeResult, Sound: $soundResult');

      if (!mounted) return;

      // 저장 성공 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Center(
            child: Text(
              'Saved successfully',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );

      // 설정 페이지를 닫고 결과 반환
      Navigator.pop(context, {
        'timePresets': _timePresets,
        'soundPresets': _soundPresets,
      });
    } catch (e) {
      print('Error saving presets: $e');
      if (!mounted) return;

      // 에러 발생 시 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(
            child: Text(
              '저장 중 오류가 발생했습니다: $e',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playSound(String sound, int index) async {
    try {
      for (int i = 0; i < _isPlayingList.length; i++) {
        if (_isPlayingList[i] && i != index) {
          await _audioPlayer.stop();
          setState(() {
            _isPlayingList[i] = false;
          });
        }
      }

      if (_isPlayingList[index]) {
        await _audioPlayer.stop();
        setState(() {
          _isPlayingList[index] = false;
        });
      } else {
        await _audioPlayer.play(AssetSource('sounds/$sound.mp3'));
        setState(() {
          _isPlayingList[index] = true;
        });
      }
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  Widget _buildTimeSelector(int index) {
    print('Building selector for index $index:');
    print(
        'Minutes: ${_selectedMinutes[index]}, Seconds: ${_selectedSeconds[index]}');
    print('Sound: ${_soundPresets[index]}');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 분 선택기
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 120,
            child: Platform.isIOS
                ? CupertinoPicker(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    itemExtent: 32.0,
                    scrollController: FixedExtentScrollController(
                      initialItem: _selectedMinutes[index],
                    ),
                    onSelectedItemChanged: (int value) {
                      setState(() {
                        _selectedMinutes[index] = value;
                        _timePresets[index] =
                            value * 60 + _selectedSeconds[index];
                      });
                    },
                    children: List<Widget>.generate(60, (int i) {
                      return Center(
                        child: Text(
                          '$i',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                      );
                    }),
                  )
                : DropdownButtonFormField<int>(
                    key: ValueKey('minutes_$index'),
                    decoration: InputDecoration(
                      labelText: '분',
                      labelStyle: const TextStyle(color: Colors.blue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.blue.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    style: const TextStyle(color: Colors.white),
                    dropdownColor: const Color(0xFF2A2A2A),
                    value: _selectedMinutes[index],
                    items: List<DropdownMenuItem<int>>.generate(
                      60,
                      (i) => DropdownMenuItem<int>(
                        value: i,
                        child: Text(
                          i.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedMinutes[index] = value;
                          _timePresets[index] =
                              value * 60 + _selectedSeconds[index];
                        });
                      }
                    },
                  ),
          ),
        ),

        const Text('분', style: TextStyle(color: Colors.white)),
        const SizedBox(width: 10),

        // 초 선택기
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 120,
            child: Platform.isIOS
                ? CupertinoPicker(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    itemExtent: 32.0,
                    scrollController: FixedExtentScrollController(
                      initialItem: _selectedSeconds[index],
                    ),
                    onSelectedItemChanged: (int value) {
                      setState(() {
                        _selectedSeconds[index] = value;
                        _timePresets[index] =
                            _selectedMinutes[index] * 60 + value;
                      });
                    },
                    children: List<Widget>.generate(60, (int i) {
                      return Center(
                        child: Text(
                          '$i',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                      );
                    }),
                  )
                : DropdownButtonFormField<int>(
                    key: ValueKey('seconds_$index'),
                    decoration: InputDecoration(
                      labelText: '초',
                      labelStyle: const TextStyle(color: Colors.blue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.blue.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    style: const TextStyle(color: Colors.white),
                    dropdownColor: const Color(0xFF2A2A2A),
                    value: _selectedSeconds[index],
                    items: List<DropdownMenuItem<int>>.generate(
                      60,
                      (i) => DropdownMenuItem<int>(
                        value: i,
                        child: Text(
                          i.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedSeconds[index] = value;
                          _timePresets[index] =
                              _selectedMinutes[index] * 60 + value;
                        });
                      }
                    },
                  ),
          ),
        ),

        const Text('초', style: TextStyle(color: Colors.white)),
        const SizedBox(width: 10),

        // 알람 소리 선택기
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 120,
            child: Platform.isIOS
                ? CupertinoPicker(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    itemExtent: 32.0,
                    scrollController: FixedExtentScrollController(
                      initialItem:
                          _availableSounds.indexOf(_soundPresets[index]),
                    ),
                    onSelectedItemChanged: (int value) {
                      setState(() {
                        _soundPresets[index] = _availableSounds[value];
                      });
                    },
                    children: _availableSounds.map((sound) {
                      return Center(
                        child: Text(
                          sound,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                      );
                    }).toList(),
                  )
                : DropdownButtonFormField<String>(
                    key: ValueKey('sound_$index'),
                    decoration: InputDecoration(
                      labelText: '알람음',
                      labelStyle: const TextStyle(color: Colors.blue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.blue.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    style: const TextStyle(color: Colors.white),
                    dropdownColor: const Color(0xFF2A2A2A),
                    value: _soundPresets[index],
                    items: _availableSounds
                        .map((sound) => DropdownMenuItem<String>(
                              value: sound,
                              child: Text(
                                sound,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _soundPresets[index] = value;
                        });
                      }
                    },
                  ),
          ),
        ),

        // 재생 버튼
        IconButton(
          icon: Icon(
            _isPlayingList[index] ? Icons.stop : Icons.play_arrow,
            color: Colors.white,
          ),
          onPressed: () => _playSound(_soundPresets[index], index),
        ),
      ],
    );
  }

  Widget _buildPresetRow(int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      color: const Color(0xFF2A2A2A),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Preset ${index + 1}',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTimeSelector(index),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == false) {
          return Scaffold(
            body: Center(
              child: Text('Error initializing settings: ${snapshot.error}'),
            ),
          );
        }

        final screenHeight = MediaQuery.of(context).size.height;

        return Scaffold(
          backgroundColor: const Color(0xFF1E1E1E),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blue),
                onPressed: () {
                  _resetToDefaults();
                },
                tooltip: '초기화',
              ),
            ],
          ),
          body: SafeArea(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1E1E1E),
                    Colors.blue.withOpacity(0.1),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 프리셋 목록
                      Column(
                        children: List.generate(
                          4,
                          (index) => Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: _buildPresetRow(index),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Save 버튼
                      ElevatedButton(
                        onPressed: _savePresets,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          'Save Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
