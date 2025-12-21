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
  final List<double> _data = [];
  final List<int> _bpmValues = [];
  double _bpm = 0.0;

  // Algorithm parameters
  static const int _windowSize = 50; 
  static const int _smoothingWindow = 5; 
  static const int _minFingerBrightness = 30; // Min brightness to detect finger presence (adjust as needed)
  static const int _maxFingerBrightness = 250; // Avoid fully white saturation which might be ambient light
  
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
    
    // Calculate average brightness for PPG (still needed for heart rate)
    // We only calculate this if finger is valid to save CPU
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
             // Extract brightness from BGRA
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

    if (_data.length >= _windowSize) {
      _data.removeAt(0);
    }
    _data.add(avgBrightness);

    _calculateBPM();

    _isProcessing = false;
    if (mounted) setState(() {});
  }

  bool _detectFinger(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        // YUV420: Y=Luminance, V=Chroma(Red), U=Chroma(Blue)
        // Finger on flash -> High Y (Bright), High V (Red), Low U (Blue)
        
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];
        
        int centerX = image.width ~/ 2;
        int centerY = image.height ~/ 2;
        
        // Sample center pixel (approx) for speed
        // YUV structure is complex, but let's grab a central point.
        // Y is full res, U/V are usually half res (subsampled).
        // Let's just check the center Y value.
        int yIndex = centerY * yPlane.bytesPerRow + centerX;
        int yValue = yPlane.bytes[yIndex];
        
        // V plane (Red chroma). V > 128 usually means reddish.
        // U/V are sub-sampled 2x2 usually.
        int uvIndex = (centerY ~/ 2) * vPlane.bytesPerRow + (centerX ~/ 2) * vPlane.bytesPerPixel!;
        int vValue = vPlane.bytes[uvIndex];

        // Thumb on flash: Y is moderate-high, V is high (red), U is low/mid (not blue)
        // Red color in YUV: Y ~ middle/high, U < 128 (green/yellow axis), V > 128 (read axis)
        
        // Thresholds (Tuned for typical finger-on-flash)
        bool brightEnough = yValue > _minFingerBrightness && yValue < _maxFingerBrightness;
        bool isRed = vValue > 140; // V > 128 is red component
        
        return brightEnough && isRed;

      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        final bytes = image.planes[0].bytes;
        int centerX = image.width ~/ 2;
        int centerY = image.height ~/ 2;
        int index = (centerY * image.width + centerX) * 4;
        
        int b = bytes[index];
        int g = bytes[index + 1];
        int r = bytes[index + 2];
        
        // Red dominance check
        bool brightEnough = r > _minFingerBrightness && r < _maxFingerBrightness;
        bool isRed = r > g + 20 && r > b + 20; // Significantly more red than green/blue
        
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
          // Calculate luminosity: 0.299 R + 0.587 G + 0.114 B
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
    if (_data.length < _windowSize) return;

    // Moving Average Filter to smooth noise
    List<double> smoothed = [];
    for (int i = 0; i < _data.length - _smoothingWindow; i++) {
        double sum = 0;
        for (int j = 0; j < _smoothingWindow; j++) {
            sum += _data[i+j];
        }
        smoothed.add(sum / _smoothingWindow);
    }

    if (smoothed.isEmpty) return;

    // Min/Max for dynamic range check
    double min = smoothed.reduce(math.min);
    double max = smoothed.reduce(math.max);
    double range = max - min;
    
    // If signal is flat (no heartbeat), range will be small noise.
    // We need a minimum peak-to-peak amplitude to consider it a pulse.
    // This threshold depends on sensor/device, usually > 1-2 units of 8-bit color.
    if (range < 3.0) return; // Signal too flat, probably just holding still without pulse or invalid.

    // Dynamic Threshold for peak detection
    double threshold = min + (range * 0.6); // Look for peaks in lower 40% (inverted) or higher?
    // Pulse = blood rush = more absorption = DARKER image (lower Red/Brightness).
    // So a pulse is a local MINIMUM in the brightness graph.
    // Let's look for local minima below threshold.
    
    // Actually, let's reverse threshold logic to match previous logic (peaks).
    // Previous logic: if(val < threshold) -> local minimum. Correct.
    
    List<int> peakIndices = [];
    for (int i = 1; i < smoothed.length - 1; i++) {
        bool isLocalMinimum = smoothed[i] < smoothed[i-1] && smoothed[i] < smoothed[i+1];
        if (isLocalMinimum && smoothed[i] < threshold) {
            peakIndices.add(i);
        }
    }

    if (peakIndices.length > 1) {
        // Calculate BPM based on the most recent interval
        // But better: use average interval of founded peaks in this window
        
        // We need 'time' per frame. Since we don't have exact timestamps per frame in simple list,
        // we approximate 30fps.
        double fps = 30.0; 
        
        // Calculate intervals
        double avgInterval = 0;
        for (int i = 0; i < peakIndices.length - 1; i++) {
            avgInterval += (peakIndices[i+1] - peakIndices[i]);
        }
        avgInterval /= (peakIndices.length - 1);

        double instantBpm = (60.0 * fps) / avgInterval;

        // Validation
        if (instantBpm > 40 && instantBpm < 200) {
            // Smooth the Displayed BPM
            if (_bpmValues.length >= 5) _bpmValues.removeAt(0);
            _bpmValues.add(instantBpm.round());
            
            double sumBpm = _bpmValues.reduce((a, b) => a + b) / _bpmValues.length;
            _bpm = sumBpm;
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
  final List<double> data;
  
  ChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    // Auto-scale
    double min = data.reduce(math.min);
    double max = data.reduce(math.max);
    double range = max - min;
    if (range == 0) range = 1;

    double stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
        double normalizedH = (data[i] - min) / range;
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
