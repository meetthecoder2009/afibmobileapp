import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Rate Monitor',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF101010),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HeartRateMonitor(),
    );
  }
}

class HeartRateMonitor extends StatefulWidget {
  const HeartRateMonitor({super.key});

  @override
  State<HeartRateMonitor> createState() => _HeartRateMonitorState();
}

class _HeartRateMonitorState extends State<HeartRateMonitor> {
  CameraController? _controller;
  bool _isProcessing = false;
  // Data buffer storing value and timestamp
  final List<SensorValue> _data = [];
  final List<int> _bpmValues = [];
  double _bpm = 0.0;
  
  // Algorithm parameters
  static const int _windowSize = 150; // Increased window size for better analysis (~5 seconds at 30fps)
  static const int _smoothingWindow = 5; 
  static const int _minFingerBrightness = 30; 
  static const int _maxFingerBrightness = 250; 
  
  // State for peak detection
  bool _isFingerPresent = false;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
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

    // Finger Validation
    bool validFinger = _detectFinger(image);
    
    double avgBrightness = 0;

    if (validFinger) {
        try {
          if (image.format.group == ImageFormatGroup.yuv420) {
            avgBrightness = _calculateAverageBrightness(
              image.planes[0].bytes, 
              image.planes[0].bytesPerRow, 
              image.width, 
              image.height
            );
          } else if (image.format.group == ImageFormatGroup.bgra8888) {
             avgBrightness = _calculateAverageBrightnessBGRA(
              image.planes[0].bytes, 
              image.width, 
              image.height
            );
          }
        } catch (e) {
            debugPrint("Error calculating brightness: $e");
            validFinger = false; 
        }
    }

    if (!validFinger) {
      _isFingerPresent = false;
      _data.clear();
      _bpmValues.clear();
      _bpm = 0.0;
      if (mounted) setState(() {});
      _isProcessing = false;
      return;
    }
    
    _isFingerPresent = true;
    
    // Add new data point with timestamp
    final now = DateTime.now();
    _data.add(SensorValue(value: avgBrightness, time: now));
    
    // Maintain window size
    if (_data.length > _windowSize) {
      _data.removeAt(0);
    }

    _calculateBPM();

    _isProcessing = false;
    if (mounted) setState(() {});
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
        
        int uvIndex = (centerY ~/ 2) * vPlane.bytesPerRow + (centerX ~/ 2) * vPlane.bytesPerPixel!;
        int vValue = vPlane.bytes[uvIndex];

        bool brightEnough = yValue > _minFingerBrightness && yValue < _maxFingerBrightness;
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
        
        bool brightEnough = r > _minFingerBrightness && r < _maxFingerBrightness;
        bool isRed = r > g + 20 && r > b + 20; 
        
        return brightEnough && isRed;
      }
    } catch (e) {
      debugPrint("Error detecting finger: $e");
    }
    return false;
  }

  double _calculateAverageBrightness(List<int> bytes, int bytesPerRow, int width, int height) {
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

  double _calculateAverageBrightnessBGRA(List<int> bytes, int width, int height) {
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
          sum += (0.299*r + 0.587*g + 0.114*b).toInt();
          count++;
        }
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  void _calculateBPM() {
    // Only analyze if we have enough data (at least 3 seconds worth ~ 90 frames)
    // But let's start earlier for responsiveness
    if (_data.length < 30) return;

    List<SensorValue> smoothData = [];
    
    // 1. Moving Average Smoothing
    for (int i = 0; i < _data.length - _smoothingWindow; i++) {
        double sum = 0;
        for (int j = 0; j < _smoothingWindow; j++) {
            sum += _data[i+j].value;
        }
        smoothData.add(SensorValue(
            value: sum / _smoothingWindow, 
            time: _data[i + _smoothingWindow ~/ 2].time
        ));
    }
    
    if (smoothData.isEmpty) return;
    
    // 2. High Pass Filter (Approximate)
    // Subtract global mean of current window to center signal around 0
    double globalMean = smoothData.map((e) => e.value).reduce((a, b) => a + b) / smoothData.length;
    List<SensorValue> normalizedData = smoothData.map((e) => SensorValue(
        value: e.value - globalMean, 
        time: e.time
    )).toList();

    // 3. Peak Detection
    // We look for local minima if measuring brightness (blood surge = darker)
    // So looking for dips.
    
    // Find min/max for thresholds
    double minVal = normalizedData.map((e) => e.value).reduce(math.min);
    
    // Threshold is somewhat arbitrary but dynamic
    // Let's say a 'peak' (dip) must be in the bottom 50% of the signal range
    double threshold = minVal * 0.6; // assuming minVal is negative (centered at 0)
    
    List<SensorValue> peaks = [];
    
    for (int i = 1; i < normalizedData.length - 1; i++) {
        // Local minimum check
        if (normalizedData[i].value < normalizedData[i-1].value && 
            normalizedData[i].value < normalizedData[i+1].value) {
            
            // Amplitude threshold check
            if (normalizedData[i].value < threshold) {
                 // Refractory period check: discard peaks too close to last peak (< 300ms = >200bpm)
                 if (peaks.isNotEmpty) {
                    int diffMs = normalizedData[i].time.difference(peaks.last.time).inMilliseconds;
                    if (diffMs < 300) continue; 
                 }
                 peaks.add(normalizedData[i]);
            }
        }
    }
    
    // 4. BPM Calculation from Timestamps
    if (peaks.length > 2) { // Need at least 2 intervals
         List<double> intervals = [];
         
         for (int i = 0; i < peaks.length - 1; i++) {
             int diffMs = peaks[i+1].time.difference(peaks[i].time).inMilliseconds;
             intervals.add(diffMs.toDouble());
         }
         
         // Calculate Instant BPM
         double avgIntervalMs = intervals.reduce((a, b) => a + b) / intervals.length;
         double instantBpm = 60000 / avgIntervalMs;
         
         // 5. Outlier Rejection & Smoothing
         if (instantBpm > 40 && instantBpm < 180) {
              _bpmValues.add(instantBpm.round());
              if (_bpmValues.length > 10) _bpmValues.removeAt(0);
              
              // Sort to find median to ignore random spikes
              List<int> sorted = List.from(_bpmValues)..sort();
              // Use median or trimmed average
              // Trimmed average: ignore top/bottom 1 if enough samples
              
              double finalBpm;
              if (sorted.length >= 5) {
                 // Remove min and max
                 int sum = 0;
                 for (int i = 1; i < sorted.length - 1; i++) {
                     sum += sorted[i];
                 }
                 finalBpm = sum / (sorted.length - 2);
              } else {
                 finalBpm = sorted.reduce((a, b) => a + b) / sorted.length;
              }
              
              _bpm = finalBpm;
         }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart Rate Monitor'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Camera Preview (Small circular window)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isFingerPresent ? Colors.redAccent : Colors.grey, 
                  width: 3
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isFingerPresent ? Colors.redAccent : Colors.grey).withOpacity(0.3),
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
                _isFingerPresent 
                    ? "Detecting Pulse..." 
                    : "Place your finger gently covering the camera and flash",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isFingerPresent ? Colors.white : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
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
    
    // Extract values for plotting
    // To handle timestamp based plotting is complex for a simple sparkline, 
    // for now we just plot indices as the window is sliding.
    // Ideally we plot X based on time, but uniform spacing is enough for visualization here.
    
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
