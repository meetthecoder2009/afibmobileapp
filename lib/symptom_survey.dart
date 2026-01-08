import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fitness_survey.dart';

class SymptomSurveyScreen extends StatefulWidget {
  const SymptomSurveyScreen({super.key});

  @override
  State<SymptomSurveyScreen> createState() => _SymptomSurveyScreenState();
}

class _SymptomSurveyScreenState extends State<SymptomSurveyScreen> {
  // Symptom List
  final Map<String, bool> _symptoms = {
    "Palpitations (Fast/Fluttering Heart)": false,
    "Dizziness / Lightheadedness": false,
    "Shortness of Breath": false,
    "Chest Pain or Discomfort": false,
    "Fainting (Syncope)": false,
    "Unexplained Fatigue": false,
  };

  Future<void> _submitSymptoms() async {
    // Check if any symptom is selected
    bool hasSymptoms = _symptoms.values.any((selected) => selected);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_symptoms', hasSymptoms);

    if (mounted) {
      // Navigate to Fitness Survey
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const FitnessSurveyScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        title: const Text('Symptom Check'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Do you have any symptoms?",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Select any symptoms you have experienced recently or are experiencing now.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),

                    ..._symptoms.keys.map((key) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _symptoms[key]!
                                  ? Colors.redAccent
                                  : Colors.transparent,
                            ),
                          ),
                          child: CheckboxListTile(
                            title: Text(
                              key,
                              style: const TextStyle(color: Colors.white),
                            ),
                            value: _symptoms[key],
                            activeColor: Colors.redAccent,
                            checkColor: Colors.white,
                            onChanged: (bool? value) {
                              setState(() {
                                _symptoms[key] = value ?? false;
                              });
                            },
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),
                    // "None of the above" option logic could be explicit,
                    // but for now unchecking all implies "None".
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitSymptoms,
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
            ),
          ],
        ),
      ),
    );
  }
}
