import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p; // Import path package for basename
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:dio/dio.dart';
import 'package:media_store_plus/media_store_plus.dart';

List<CameraDescription> _availableCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _availableCameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finger Camera Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  bool _recording = false;
  int _secondsLeft = 20;
  Timer? _countdownTimer;
  bool _isFingerOn = false;

  @override
  void dispose() {
    _controller?.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<bool> _requestPermission(Permission permission) async {
    if (await permission.isGranted) {
      return true;
    } else {
      var result = await permission.request();
      if (result == PermissionStatus.granted) {
        return true;
      }
    }
    return false;
  }

  Future<void> downloadVideo(String videoUrl) async {
    final downloadDirPath = await getDownloadDirectoryPath();
    if (downloadDirPath == null) {
      print("Could not get download directory path.");
      return;
    }

    // Ensure the directory exists
    final downloadDir = Directory(downloadDirPath);
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final fileName = videoUrl.split('/').last; // Extract filename from URL
    final filePath = '$downloadDirPath/$fileName';

    try {
      Dio dio = Dio();
      await dio.download(
        videoUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            print("${(received / total * 100).toStringAsFixed(0)}%");
          }
        },
      );
      print("Video downloaded successfully to: $filePath");
    } catch (e) {
      print("Error downloading video: $e");
    }
  }

  Future<String?> getDownloadDirectoryPath() async {
    if (Platform.isAndroid) {
      // For Android, directly construct the common Downloads path
      return "/storage/emulated/0/Download/";
    }
    return null; // Handle other platforms if needed
  }

  Future<void> _initCamera() async {
    WakelockPlus.enable();

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      debugPrint("❌ Camera permission not granted");
      return;
    }

    final backCamera = _availableCameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _availableCameras.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await _controller!.initialize();
    await _controller!.setFlashMode(FlashMode.torch);

    setState(() {});
  }

  void _processCameraImage(CameraImage image) {
    try {
      if (image.format.group != ImageFormatGroup.yuv420) return;

      final bytes = image.planes[0].bytes; // luminance
      final avg = bytes.fold<int>(0, (p, e) => p + e) ~/ bytes.length;

      final isRed = avg < 80;

      if (isRed && !_isFingerOn) {
        _isFingerOn = true;
        _startRecording();
      } else if (!isRed && _isFingerOn) {
        _isFingerOn = false;
      }
    } catch (e) {
      debugPrint("❌ Error processing frame: $e");
    }
  }

  Future<void> _startRecording() async {
    if (_recording) return;

    await _controller!.startVideoRecording();

    setState(() {
      _recording = true;
      _secondsLeft = 20;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        t.cancel();
        await _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    final XFile videoFile = await _controller!.stopVideoRecording();
    _countdownTimer?.cancel();

    setState(() => _recording = false);

    // ✅ Save to Downloads
    final ms = MediaStore();
    final saved = await ms.saveFile(
      tempFilePath: videoFile.path,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: FilePath.root,
    );

    final ok = saved?.isSuccessful ?? false;
    final name = saved?.name ?? 'video.mp4';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Saved to Downloads/$name'
              : 'Saved duplicate as Downloads/$name',
        ),
      ),
    );
  } // <-- THIS closing brace was missing before!

  Widget _buildCameraView() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: Text("Press Start to open camera"));
    }

    final double previewSize = MediaQuery.of(context).size.shortestSide * 0.8;
    final double ringSize = previewSize + 30;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_recording)
            SizedBox(
              width: ringSize,
              height: ringSize,
              child: CircularProgressIndicator(
                value: (20 - _secondsLeft) / 20,
                strokeWidth: 10,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
          ClipOval(
            child: SizedBox(
              width: previewSize,
              height: previewSize,
              child: CameraPreview(_controller!),
            ),
          ),
          if (_recording)
            Text(
              '$_secondsLeft s',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCameraView()),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _initCamera,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Start Camera"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
