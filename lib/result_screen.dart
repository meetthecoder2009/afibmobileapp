import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  final int averageBpm;
  final int minBpm;
  final int maxBpm;
  final double rmssd;
  final double sdnn;
  final int durationSeconds;
  final String quality; // 'High', 'Medium', 'Low'
  final String rhythmStatus; // 'Regular Rhythm Detected', etc.

  const ResultScreen({
    super.key,
    required this.averageBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.rmssd,
    required this.sdnn,
    required this.durationSeconds,
    required this.quality,
    required this.rhythmStatus,
  });

  Color _getStatusColor() {
    // Red for Bradycardia or Tachycardia (explicit conditions)
    if (rhythmStatus.contains("Bradycardia") ||
        rhythmStatus.contains("Tachycardia")) {
      return Colors.redAccent;
    }
    // Yellow (OrangeAccent for visibility) for Irregularity
    if (rhythmStatus.contains("Irregular") ||
        rhythmStatus.contains("Elevated")) {
      return Colors.orangeAccent;
    }
    // Asymptomatic low/high warnings -> Yellow/Orange
    if (rhythmStatus.contains("Asymptomatic")) {
      return Colors.orangeAccent;
    }

    // Default / Normal -> Green
    if (rhythmStatus.contains("Unreliable")) return Colors.grey;
    return Colors.greenAccent;
  }

  String _getInterpretation() {
    if (quality == 'Low') {
      return "The signal quality was poor. Please try again, ensuring your finger gently covers the camera and flash completely without moving.";
    }
    if (rhythmStatus.contains("Irregular")) {
      return "This measurement detected uneven spacing between heartbeats. This can sometimes occur due to stress, caffeine, or movement. If this happens often or you experience symptoms, consider speaking with a healthcare professional.";
    }
    if (rhythmStatus.contains("Elevated")) {
      return "Your heartbeat showed some variation. This is often normal but can be influenced by stress or fatigue.";
    }
    return "Your heart rhythm appears regular. Consistent spacing between beats is a sign of a healthy heart rhythm.";
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        title: const Text('Measurement Result'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Summary Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: statusColor.withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Column(
                children: [
                  Text(
                    "Heart Rhythm Summary",
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    rhythmStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Based on a $durationSeconds-second measurement",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. Heart Rate Overview
            _buildSectionHeader("Heart Rate Overview"),
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    title: "Average",
                    value: "$averageBpm",
                    unit: "BPM",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    title: "Range",
                    value: "$minBpm-$maxBpm",
                    unit: "BPM",
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3. Regularity Analysis
            _buildSectionHeader("Regularity Analysis"),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Variability (RMSSD)",
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        "${rmssd.toStringAsFixed(1)} ms",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (rmssd / 200).clamp(0.0, 1.0), // Example scale
                      backgroundColor: Colors.grey[800],
                      color: statusColor,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rmssd > 50
                        ? "Higher variability detected."
                        : "Stable beat-to-beat intervals.",
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 4. Measurement Quality
            _buildSectionHeader("Measurement Quality"),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    quality == 'High' ? Icons.check_circle : Icons.warning,
                    color: quality == 'High' ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$quality Quality Signal",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        quality == 'High'
                            ? "Results are reliable"
                            : "Minor interference detected",
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 5. Interpretation & Guidance
            _buildSectionHeader("Interpretation"),
            Text(
              _getInterpretation(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),

            if (rhythmStatus.contains("Bradycardia"))
              _buildConditionDetails(
                title: "Bradycardia (Slow Heartbeat)",
                definition: "A resting heart rate below 60 BPM.",
                concern:
                    "If the heart isn't pumping enough blood, causing symptoms like:",
                symptoms: [
                  "Dizziness, lightheadedness, fainting",
                  "Shortness of breath",
                  "Chest pain",
                  "Fatigue, confusion, memory problems"
                ],
              ),

            if (rhythmStatus.contains("Tachycardia"))
              _buildConditionDetails(
                title: "Tachycardia (Fast Heartbeat)",
                definition: "A resting heart rate over 100 BPM.",
                concern:
                    "Symptoms often arise when the heart can't pump effectively, including:",
                symptoms: [
                  "Palpitations (feeling your heart pound or race)",
                  "Dizziness, lightheadedness",
                  "Shortness of breath, chest pain",
                  "Fainting"
                ],
              ),

            const SizedBox(height: 32),

            // 6. User Actions
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Measure Again",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {}, // Placeholder
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Export Report"),
            ),

            const SizedBox(height: 24),

            // 7. Disclaimer
            Center(
              child: Text(
                "This app is not a medical device and cannot diagnose heart conditions. Consult a doctor for any concerns.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      {required String title, required String value, required String unit}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionDetails({
    required String title,
    required String definition,
    required String concern,
    required List<String> symptoms,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Definition:",
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            definition,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Text(
            "When it's a concern:",
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            concern,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          ...symptoms.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("• ", style: TextStyle(color: Colors.redAccent)),
                    Expanded(
                        child: Text(s,
                            style: const TextStyle(color: Colors.white70))),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.medical_services, color: Colors.redAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Consult a doctor if you experience any of these symptoms.",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
