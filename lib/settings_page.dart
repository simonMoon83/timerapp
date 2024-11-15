import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<int> _timePresets = [15, 30, 45, 60];
  List<TextEditingController> _controllers = [];
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _controllers = List.generate(4, (index) => TextEditingController());
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTimePresets();
  }

  void _loadTimePresets() {
    setState(() {
      _timePresets = _prefs.getStringList('timePresets')?.map(int.parse).toList() ?? [15, 30, 45, 60];
      for (int i = 0; i < _controllers.length; i++) {
        _controllers[i].text = _timePresets[i].toString();
      }
    });
  }

  Future<void> _saveTimePresets() async {
    List<String> presets = _timePresets.map((e) => e.toString()).toList();
    await _prefs.setStringList('timePresets', presets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Timer Presets (minutes)',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(4, (index) => _buildTimePresetInput(index)),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                onPressed: () async {
                  // 입력값 검증 및 저장
                  bool isValid = true;
                  List<int> newPresets = [];
                  
                  for (var controller in _controllers) {
                    int? value = int.tryParse(controller.text);
                    if (value == null || value <= 0) {
                      isValid = false;
                      break;
                    }
                    newPresets.add(value);
                  }

                  if (isValid) {
                    setState(() {
                      _timePresets = newPresets;
                    });
                    await _saveTimePresets();
                    Navigator.pop(context, _timePresets);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter valid numbers greater than 0'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePresetInput(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: _controllers[index],
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Preset ${index + 1}',
          labelStyle: TextStyle(color: Colors.grey[400]),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[800]!),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue),
          ),
        ),
      ),
    );
  }

  
}