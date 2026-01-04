import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

class FitnessSurveyScreen extends StatefulWidget {
  const FitnessSurveyScreen({super.key});

  @override
  State<FitnessSurveyScreen> createState() => _FitnessSurveyScreenState();
}

class _FitnessSurveyScreenState extends State<FitnessSurveyScreen> {
  // Cardio Input
  String _cardioType = 'Moderate'; // 'Moderate' or 'Vigorous'
  double _cardioDays = 3;
  double _cardioMinutes = 30;

  // Strength Input
  double _strengthDays = 1;

  Future<void> _submitSurvey() async {
    // Calculate total weekly minutes
    double totalWeeklyMinutes = _cardioDays * _cardioMinutes;

    bool isAerobicFit = false;
    if (_cardioType == 'Moderate') {
      if (totalWeeklyMinutes >= 150) isAerobicFit = true;
    } else {
      // Vigorous
      if (totalWeeklyMinutes >= 75) isAerobicFit = true;
    }

    bool isStrengthFit = _strengthDays >= 2;

    // "If the user is doing all of this... taken as normal"
    bool isFit = isAerobicFit && isStrengthFit;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('survey_completed', true);
    await prefs.setBool('is_fit', isFit);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HeartRateMonitor()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        title: const Text('Fitness Assessment'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Tell us about your activity level",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "This helps us analyze your resting heart rate accurately.",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),

              // Cardio Section
              const Text(
                "1. Cardio / Aerobic Exercise",
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text("Intensity Level",
                  style: TextStyle(color: Colors.white)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text("Moderate",
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text("Light jog, brisk walk",
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      value: 'Moderate',
                      groupValue: _cardioType,
                      activeColor: Colors.redAccent,
                      onChanged: (val) => setState(() => _cardioType = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text("Vigorous",
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text("Running, Fast cycling",
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      value: 'Vigorous',
                      groupValue: _cardioType,
                      activeColor: Colors.redAccent,
                      onChanged: (val) => setState(() => _cardioType = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text("Frequency: ${_cardioDays.round()} days/week",
                  style: const TextStyle(color: Colors.white)),
              Slider(
                value: _cardioDays,
                min: 0,
                max: 7,
                divisions: 7,
                activeColor: Colors.redAccent,
                onChanged: (val) => setState(() => _cardioDays = val),
              ),
              const SizedBox(height: 16),
              Text("Duration: ${_cardioMinutes.round()} mins/session",
                  style: const TextStyle(color: Colors.white)),
              Slider(
                value: _cardioMinutes,
                min: 0,
                max: 120,
                divisions: 24,
                label: "${_cardioMinutes.round()} mins",
                activeColor: Colors.redAccent,
                onChanged: (val) => setState(() => _cardioMinutes = val),
              ),

              const SizedBox(height: 32),
              // Strength Section
              const Text(
                "2. Strength Training",
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Weights, resistance bands, bodyweight exercises",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text("Frequency: ${_strengthDays.round()} days/week",
                  style: const TextStyle(color: Colors.white)),
              Slider(
                value: _strengthDays,
                min: 0,
                max: 7,
                divisions: 7,
                activeColor: Colors.redAccent,
                onChanged: (val) => setState(() => _strengthDays = val),
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitSurvey,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Continue",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
