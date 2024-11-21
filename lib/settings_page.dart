import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<int> _timePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
  List<String> _soundPresets = ['alarm1', 'alarm1', 'alarm1', 'alarm1'];
  List<TextEditingController> _minuteControllers = [];
  List<TextEditingController> _secondControllers = [];
  late SharedPreferences _prefs;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<bool> _isPlayingList = List.filled(4, false);

  final List<String> _availableSounds = [
    'alarm1',
    'alarm2',
    'alarm3',
    'alarm4',
  ];

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _minuteControllers = List.generate(4, (index) => TextEditingController());
    _secondControllers = List.generate(4, (index) => TextEditingController());
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void dispose() {
    for (var controller in _minuteControllers) {
      controller.dispose();
    }
    for (var controller in _secondControllers) {
      controller.dispose();
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPresets();
  }

  void _loadPresets() {
    setState(() {
      _timePresets = _prefs.getStringList('timePresets')?.map(int.parse).toList() ?? 
          [15 * 60, 30 * 60, 45 * 60, 60 * 60];
      _soundPresets = _prefs.getStringList('soundPresets') ?? List.filled(4, 'alarm1');
      
      for (int i = 0; i < _soundPresets.length; i++) {
        if (!_availableSounds.contains(_soundPresets[i])) {
          _soundPresets[i] = 'alarm1';
        }
      }
      
      for (int i = 0; i < _timePresets.length; i++) {
        int totalSeconds = _timePresets[i];
        int minutes = totalSeconds ~/ 60;
        int seconds = totalSeconds % 60;
        _minuteControllers[i].text = minutes.toString();
        _secondControllers[i].text = seconds.toString();
      }
    });
  }

  void _resetToDefaults() {
    setState(() {
      _timePresets = [5, 10, 15, 20];
      _soundPresets = List.filled(4, 'alarm1');

      for (int i = 0; i < _timePresets.length; i++) {
        _minuteControllers[i].text = '0';
        _secondControllers[i].text = _timePresets[i].toString();
      }
    });
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

  Future<void> _savePresets() async {
    bool isValid = true;
    List<int> newPresets = [];

    for (int i = 0; i < 4; i++) {
      int? minutes = int.tryParse(_minuteControllers[i].text);
      int? seconds = int.tryParse(_secondControllers[i].text);
      
      if (minutes == null || seconds == null || seconds >= 60 || minutes < 0 || seconds < 0) {
        isValid = false;
        break;
      }
      
      newPresets.add(minutes * 60 + seconds);
    }

    if (isValid) {
      setState(() {
        _timePresets = newPresets;
      });
      List<String> timePresets = _timePresets.map((e) => e.toString()).toList();
      await _prefs.setStringList('timePresets', timePresets);
      await _prefs.setStringList('soundPresets', _soundPresets);
      
      if (mounted) {
        Navigator.pop(context, {
          'timePresets': _timePresets,
          'soundPresets': _soundPresets,
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid numbers (seconds should be less than 60)'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: _resetToDefaults,
            tooltip: '초기화',
          ),
        ],
      ),
      body: Container(
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Timer Presets',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: 4,
                  itemBuilder: (context, index) => _buildPresetRow(index),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton(
                  onPressed: _savePresets,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
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
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetRow(int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: const Color(0xFF2A2A2A),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preset ${index + 1}',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _minuteControllers[index],
                    'Minutes',
                    index,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    _secondControllers[index],
                    'Seconds',
                    index,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: DropdownButton<String>(
                      value: _soundPresets[index],
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2E2E2E),
                      style: const TextStyle(color: Colors.white),
                      underline: Container(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _soundPresets[index] = newValue;
                          });
                        }
                      },
                      items: _availableSounds.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    _isPlayingList[index] ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                    color: Colors.blue,
                    size: 32,
                  ),
                  onPressed: () => _playSound(_soundPresets[index], index),
                  tooltip: _isPlayingList[index] ? '중지' : '미리 듣기',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF353535),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[400]),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: InputBorder.none,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
      ),
    );
  }
}