import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'result_screen.dart';
import 'symptom_survey.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VHHS AFib Monitor',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF101010),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const SymptomSurveyScreen(),
    );
  }
}

class HeartRateMonitor extends StatefulWidget {
  const HeartRateMonitor({super.key});

  @override
  State<HeartRateMonitor> createState() => _HeartRateMonitorState();
}

class _HeartRateMonitorState extends State<HeartRateMonitor>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isProcessing = false;
  // Data buffer storing value and timestamp
  final List<SensorValue> _data = [];
  final List<int> _bpmValues = [];
  double _bpm = 0.0;

  // Algorithm parameters
  int _windowSize = 150; // Dynamic window size based on FPS
  static const int _smoothingWindow = 5;
  static const double _targetMonitoringSeconds = 6.0;

  // FPS Calculation
  DateTime? _lastFrameTime;
  double _currentFps = 30.0;

  // Analysis Result
  bool _isAfibPossible = false;
  String _healthStatus = "Analyzing...";
  Color _statusColor = Colors.grey;

  // User Profile
  bool _isFit = false;
  bool _hasSymptoms = false;

  // Measurement State
  bool _isMeasuring = false;
  DateTime? _measurementStartTime;
  double _progress = 0.0;
  final int _measurementDurationSeconds = 30;

  // Accumulated Data for Final Report
  final List<int> _sessionBpmValues = [];
  final List<double> _sessionIntervals = []; // ms
  final List<SensorValue> _sessionRawData = [];

  static const int _minFingerBrightness = 30;
  static const int _maxFingerBrightness = 250;

  // State for peak detection
  bool _isFingerPresent = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _initializeCamera();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFit = prefs.getBool('is_fit') ?? false;
      _hasSymptoms = prefs.getBool('has_symptoms') ?? false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    await Permission.camera.request();
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
    await _controller!.setFlashMode(FlashMode.torch);
    _controller!.startImageStream(_processImage);

    if (mounted) {
      setState(() {});
    }
  }

  void _processImage(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;

    // 1. Calculate FPS
    final nowTime = DateTime.now();
    if (_lastFrameTime != null) {
      final difference = nowTime.difference(_lastFrameTime!).inMilliseconds;
      if (difference > 0) {
        final instantFps = 1000 / difference;
        // Simple smoothing for FPS
        _currentFps = 0.9 * _currentFps + 0.1 * instantFps;
      }
    }
    _lastFrameTime = nowTime;

    // 2. Adjust Window Size
    // Dynamically adjust window to store approx _targetMonitoringSeconds of data
    int targetWindowSize = (_targetMonitoringSeconds * _currentFps).ceil();
    // Sanity clamp: minimum 3 seconds, max 10 seconds (to avoid memory issues if FPS bugs out)
    if (targetWindowSize < _currentFps * 3) {
      targetWindowSize = (_currentFps * 3).ceil();
    }
    if (targetWindowSize > _currentFps * 10) {
      targetWindowSize = (_currentFps * 10).ceil();
    }
    _windowSize = targetWindowSize;

    // Finger Validation
    bool validFinger = _detectFinger(image);

    double avgBrightness = 0;

    if (validFinger) {
      try {
        if (image.format.group == ImageFormatGroup.yuv420) {
          avgBrightness = _calculateAverageBrightness(image.planes[0].bytes,
              image.planes[0].bytesPerRow, image.width, image.height);
        } else if (image.format.group == ImageFormatGroup.bgra8888) {
          avgBrightness = _calculateAverageBrightnessBGRA(
              image.planes[0].bytes, image.width, image.height);
        }
      } catch (e) {
        debugPrint("Error calculating brightness: $e");
        validFinger = false;
      }
    }

    if (!validFinger) {
      _isFingerPresent = false;
      _statusMessage = "Place your finger on the camera";
      _statusColor = Colors.grey;

      // If measurement was active, cancel it or pause?
      // User request implies strict quality, so let's cancel/reset if finger lifted for too long.
      if (_isMeasuring) {
        _stopMeasurement(cancelled: true);
      }

      _data.clear();
      _bpmValues.clear();
      _bpm = 0.0;
      if (mounted) setState(() {});
      _isProcessing = false;
      return;
    }

    _isFingerPresent = true;
    _statusMessage = "Detecting Heartbeat...";

    // Auto-start measurement if finger is present and not measuring
    if (!_isMeasuring) {
      _startMeasurement();
    }

    // Add new data point with timestamp
    final now = DateTime.now();
    _data.add(SensorValue(value: avgBrightness, time: now));

    // Maintain window size
    while (_data.length > _windowSize) {
      _data.removeAt(0);
    }

    _analyzeHeartRate();

    _isProcessing = false;
    if (mounted) setState(() {});
  }

  String _statusMessage = "Place finger on camera";

  void _startMeasurement() {
    setState(() {
      _isMeasuring = true;
      _measurementStartTime = DateTime.now();
      _progress = 0.0;
      _sessionBpmValues.clear();
      _sessionIntervals.clear();
      _sessionRawData.clear();
      _statusMessage = "Measuring... Hold still";
    });
  }

  void _stopMeasurement({bool cancelled = false}) {
    if (cancelled) {
      setState(() {
        _isMeasuring = false;
        _progress = 0.0;
        _statusMessage = "Measurement interrupted. Please hold still for 30s.";
      });
      return;
    }

    setState(() {
      _isMeasuring = false;
      _progress = 1.0;
    });

    _calculateAndShowResults();
  }

  void _calculateAndShowResults() {
    if (_sessionBpmValues.isEmpty) {
      _stopMeasurement(cancelled: true);
      return;
    }

    // 1. Calculate HR Metrics
    int avgBpm =
        (_sessionBpmValues.reduce((a, b) => a + b) / _sessionBpmValues.length)
            .round();
    int minBpm = _sessionBpmValues.reduce(math.min);
    int maxBpm = _sessionBpmValues.reduce(math.max);

    // 2. Calculate Regularity Metrics (RMSSD, SDNN)
    double rmssd = 0;
    double sdnn = 0;

    if (_sessionIntervals.length > 1) {
      // RMSSD
      double sumSquaredDiffs = 0;
      for (int i = 0; i < _sessionIntervals.length - 1; i++) {
        double diff = _sessionIntervals[i + 1] - _sessionIntervals[i];
        sumSquaredDiffs += diff * diff;
      }
      rmssd = math.sqrt(sumSquaredDiffs / (_sessionIntervals.length - 1));

      // SDNN
      double meanInterval =
          _sessionIntervals.reduce((a, b) => a + b) / _sessionIntervals.length;
      double sumSquaredDeviations = 0;
      for (var interval in _sessionIntervals) {
        sumSquaredDeviations += math.pow(interval - meanInterval, 2);
      }
      sdnn = math.sqrt(sumSquaredDeviations / (_sessionIntervals.length - 1));
    }

    // 3. Assess Quality
    String quality = 'High';
    if (_sessionIntervals.length < 15) {
      quality = 'Low';
    } else if (rmssd > 200) {
      quality = 'Medium';
    }

    // 4. Interpretation Logic
    String rhythmStatus = "Regular Rhythm Detected";
    if (quality == 'Low') {
      rhythmStatus = "Measurement Unreliable";
    } else {
      if (rmssd > 100 || sdnn > 100) {
        rhythmStatus = _hasSymptoms
            ? "Possible Irregular Rhythm (Symptomatic)"
            : "Possible Irregular Rhythm";
      } else if (rmssd > 50) {
        rhythmStatus = "Elevated Variability Detected";
      }
    }

    // Override logic for Brady/Tachy in Result Screen text
    if (avgBpm < 60 && !_isFit) {
      rhythmStatus = _hasSymptoms
          ? "Bradycardia Detected"
          : "Low Heart Rate (Asymptomatic)";
    } else if (avgBpm > 100) {
      rhythmStatus = _hasSymptoms
          ? "Tachycardia Detected"
          : "High Heart Rate (Asymptomatic)";
    }

    // Navigate to Result Screen
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ResultScreen(
        averageBpm: avgBpm,
        minBpm: minBpm,
        maxBpm: maxBpm,
        rmssd: rmssd,
        sdnn: sdnn,
        durationSeconds: _measurementDurationSeconds,
        quality: quality,
        rhythmStatus: rhythmStatus,
      ),
    ));
  }

  bool _detectFinger(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        final yPlane = image.planes[0];
        final vPlane = image.planes[2];

        int centerX = image.width ~/ 2;
        int centerY = image.height ~/ 2;

        int yIndex = centerY * yPlane.bytesPerRow + centerX;
        int yValue = yPlane.bytes[yIndex];

        int uvIndex = (centerY ~/ 2) * vPlane.bytesPerRow +
            (centerX ~/ 2) * vPlane.bytesPerPixel!;
        int vValue = vPlane.bytes[uvIndex];

        bool brightEnough =
            yValue > _minFingerBrightness && yValue < _maxFingerBrightness;
        bool isRed = vValue > 140;

        return brightEnough && isRed;
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        final bytes = image.planes[0].bytes;
        int centerX = image.width ~/ 2;
        int centerY = image.height ~/ 2;
        int index = (centerY * image.width + centerX) * 4;

        int b = bytes[index];
        int g = bytes[index + 1];
        int r = bytes[index + 2];

        bool brightEnough =
            r > _minFingerBrightness && r < _maxFingerBrightness;
        bool isRed = r > g + 20 && r > b + 20;

        return brightEnough && isRed;
      }
    } catch (e) {
      debugPrint("Error detecting finger: $e");
    }
    return false;
  }

  double _calculateAverageBrightness(
      List<int> bytes, int bytesPerRow, int width, int height) {
    int sum = 0;
    int count = 0;
    int centerX = width ~/ 2;
    int centerY = height ~/ 2;
    int halfSize = 25;

    for (int y = centerY - halfSize; y < centerY + halfSize; y++) {
      for (int x = centerX - halfSize; x < centerX + halfSize; x++) {
        if (y >= 0 && y < height && x >= 0 && x < width) {
          sum += bytes[y * bytesPerRow + x];
          count++;
        }
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  double _calculateAverageBrightnessBGRA(
      List<int> bytes, int width, int height) {
    int sum = 0;
    int count = 0;
    int centerX = width ~/ 2;
    int centerY = height ~/ 2;
    int halfSize = 25;

    for (int y = centerY - halfSize; y < centerY + halfSize; y++) {
      for (int x = centerX - halfSize; x < centerX + halfSize; x++) {
        int index = (y * width + x) * 4;
        if (index + 2 < bytes.length) {
          int r = bytes[index + 2];
          int g = bytes[index + 1];
          int b = bytes[index];
          sum += (0.299 * r + 0.587 * g + 0.114 * b).toInt();
          count++;
        }
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  void _analyzeHeartRate() {
    // Only analyze if we have enough data (at least 3 seconds worth)
    if (_data.length < (_currentFps * 3).toInt()) return;

    List<SensorValue> smoothData = [];

    // 1. Moving Average Smoothing
    for (int i = 0; i < _data.length - _smoothingWindow; i++) {
      double sum = 0;
      for (int j = 0; j < _smoothingWindow; j++) {
        sum += _data[i + j].value;
      }
      smoothData.add(SensorValue(
          value: sum / _smoothingWindow,
          time: _data[i + _smoothingWindow ~/ 2].time));
    }

    if (smoothData.isEmpty) return;

    // 2. High Pass Filter (Approximate)
    // Subtract global mean of current window to center signal around 0
    double globalMean = smoothData.map((e) => e.value).reduce((a, b) => a + b) /
        smoothData.length;
    List<SensorValue> normalizedData = smoothData
        .map((e) => SensorValue(value: e.value - globalMean, time: e.time))
        .toList();

    // 3. Peak Detection
    // We look for local minima if measuring brightness (blood surge = darker)
    // So looking for dips.

    // Find min/max for thresholds
    double minVal = normalizedData.map((e) => e.value).reduce(math.min);

    // Threshold is somewhat arbitrary but dynamic
    // Let's say a 'peak' (dip) must be in the bottom 50% of the signal range
    double threshold =
        minVal * 0.6; // assuming minVal is negative (centered at 0)

    List<SensorValue> peaks = [];

    for (int i = 1; i < normalizedData.length - 1; i++) {
      // Local minimum check
      if (normalizedData[i].value < normalizedData[i - 1].value &&
          normalizedData[i].value < normalizedData[i + 1].value) {
        // Amplitude threshold check
        if (normalizedData[i].value < threshold) {
          // Refractory period check: discard peaks too close to last peak (< 300ms = >200bpm)
          if (peaks.isNotEmpty) {
            int diffMs = normalizedData[i]
                .time
                .difference(peaks.last.time)
                .inMilliseconds;
            if (diffMs < 300) continue;
          }
          peaks.add(normalizedData[i]);
        }
      }
    }

    // 4. BPM Calculation from Timestamps
    if (peaks.length > 2) {
      // Need at least 2 intervals
      List<double> intervals = [];

      for (int i = 0; i < peaks.length - 1; i++) {
        int diffMs = peaks[i + 1].time.difference(peaks[i].time).inMilliseconds;
        intervals.add(diffMs.toDouble());
      }

      // Calculate Instant BPM
      double avgIntervalMs =
          intervals.reduce((a, b) => a + b) / intervals.length;
      double instantBpm = 60000 / avgIntervalMs;

      // Calculate avg interval in Seconds for RR analysis
      double avgIntervalSec = avgIntervalMs / 1000.0;

      // 5. Outlier Rejection & Smoothing
      if (instantBpm > 40 && instantBpm < 180) {
        _bpmValues.add(instantBpm.round());
        // Increase buffer to ~2 seconds worth of frames (assume 30fps -> 60 frames)
        // Previous 10 was too short (~0.3s), causing rapid fluctuations.
        if (_bpmValues.length > 50) _bpmValues.removeAt(0);

        // Sort to find median to ignore random spikes
        List<int> sorted = List.from(_bpmValues)..sort();

        double currentCalculatedBpm;
        if (sorted.length >= 5) {
          // Remove min and max outliers (bottom 10% and top 10%)
          int removeCount = (sorted.length * 0.1).ceil();
          int sum = 0;
          int count = 0;
          for (int i = removeCount; i < sorted.length - removeCount; i++) {
            sum += sorted[i];
            count++;
          }
          currentCalculatedBpm = (count == 0)
              ? sorted[sorted.length ~/ 2].toDouble()
              : sum / count;
        } else {
          currentCalculatedBpm = sorted.reduce((a, b) => a + b) / sorted.length;
        }

        // Apply Exponential Moving Average (EMA) for display stability
        // _bpm = alpha * new + (1-alpha) * old
        // Lower alpha = smoother but more lag. 0.1 is usually good for display.
        if (_bpm == 0.0) {
          _bpm = currentCalculatedBpm;
        } else {
          _bpm = _bpm * 0.9 + currentCalculatedBpm * 0.1;
        }

        // Use the smoothed _bpm for 'finalBpm' in logic below
        double finalBpm = _bpm;

        // 6. AFib & Bradycardia/Tachycardia Detection Logic
        // "RR interval of 0.6-1.2 seconds is considered normal"
        // < 0.6s -> Tachycardia
        // > 1.2s -> Bradycardia

        bool isBradycardia = finalBpm < 60 && avgIntervalSec > 1.2;
        bool isTachycardia = finalBpm > 100 && avgIntervalSec < 0.6;

        // Update Session Data if Measuring
        if (_isMeasuring) {
          // Accumulate BPM
          _sessionBpmValues.add(finalBpm.round());

          // Accumulate Intervals (last one calculated)
          if (intervals.isNotEmpty) {
            _sessionIntervals.add(intervals.last);
          }

          // Update Progress
          final elapsed = DateTime.now().difference(_measurementStartTime!);
          if (mounted) {
            // Ensure mounted before setState
            setState(() {
              _progress =
                  elapsed.inMilliseconds / (_measurementDurationSeconds * 1000);
              if (_progress >= 1.0) {
                _progress = 1.0;
              }
            });

            if (_progress >= 1.0) {
              _stopMeasurement();
            }
          }
        }

        // Logic Refinement for Symptoms
        if (isBradycardia) {
          if (_isFit) {
            _healthStatus = "Low Resting HR (Normal for Athletes)";
            _statusColor = Colors.green;
            _isAfibPossible = false;
          } else {
            if (_hasSymptoms) {
              _healthStatus = "Bradycardia Detected (Symptomatic)";
              _statusColor = Colors.redAccent; // Serious
              _isAfibPossible = true;
            } else {
              _healthStatus = "Low Heart Rate (Asymptomatic)";
              _statusColor = Colors.orangeAccent; // Warning/Yellow-ish
              _isAfibPossible =
                  false; // Not flagging as full "Bradycardia" condition without symptoms per request
            }
          }
        } else if (isTachycardia) {
          if (_hasSymptoms) {
            _healthStatus = "Tachycardia Detected (Symptomatic)";
            _statusColor = Colors.redAccent;
            _isAfibPossible = true;
          } else {
            _healthStatus = "High Heart Rate (Asymptomatic)";
            _statusColor = Colors.orangeAccent; // Warning/Yellow-ish
            _isAfibPossible = false;
          }
        } else {
          // Normal Range Logic
          // AFib Detection (RMSSD)
          double sumSquaredDiffs = 0;
          for (int i = 0; i < intervals.length - 1; i++) {
            double diff = intervals[i + 1] - intervals[i];
            sumSquaredDiffs += diff * diff;
          }
          if (intervals.length > 1) {
            double rmssd = math.sqrt(sumSquaredDiffs / (intervals.length - 1));

            if (rmssd > 100) {
              // High irregularity
              if (_hasSymptoms) {
                _healthStatus = "Irregular Rhythm Detected (Symptomatic)";
                _statusColor =
                    Colors.orangeAccent; // User requested Yellow for Irregular
                _isAfibPossible = true;
              } else {
                _healthStatus = "Possible Irregularity (Consult Doctor)";
                _statusColor = Colors.orangeAccent; // User requested Yellow
                _isAfibPossible = true;
              }
            } else {
              _isAfibPossible = false;
              _healthStatus = "Normal Sinus Rhythm";
              _statusColor = Colors.greenAccent;
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VHHS AFib Monitor'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () {
              if (_controller != null) {
                _controller!.setFlashMode(FlashMode.torch);
              } else {
                _initializeCamera();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeCamera,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Camera Preview
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _isFingerPresent ? Colors.redAccent : Colors.grey,
                    width: 3),
                boxShadow: [
                  BoxShadow(
                    color: (_isFingerPresent ? Colors.redAccent : Colors.grey)
                        .withValues(alpha: 0.3),
                    spreadRadius: 5,
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: _controller != null && _controller!.value.isInitialized
                    ? CameraPreview(_controller!)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isFingerPresent ? Colors.white : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (_isMeasuring)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[800],
                  color: Colors.redAccent,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const Spacer(),
            // BPM Display
            Text(
              (_isFingerPresent && _bpm > 0) ? _bpm.toStringAsFixed(0) : "--",
              style: const TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              _isFingerPresent ? "BPM" : "",
              style: const TextStyle(
                fontSize: 20,
                color: Colors.redAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_isFingerPresent && _bpm > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    Text(
                      _healthStatus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            // Chart
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CustomPaint(
                painter: ChartPainter(_data),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  final List<SensorValue> data;

  ChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();

    List<double> values = data.map((e) => e.value).toList();

    // Auto-scale
    double min = values.reduce(math.min);
    double max = values.reduce(math.max);
    double range = max - min;
    if (range == 0) range = 1;

    double stepX = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      double normalizedH = (values[i] - min) / range;
      double y = size.height - (normalizedH * size.height);
      double x = i * stepX;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) {
    return true;
  }
}

class SensorValue {
  final double value;
  final DateTime time;

  SensorValue({required this.value, required this.time});
}
