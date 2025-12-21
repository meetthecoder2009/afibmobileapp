import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:gallery_saver/gallery_saver.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? controller;
  bool recording = false;
  int secondsLeft = 20;
  Timer? timer;

  @override
  void dispose() {
    controller?.dispose();
    timer?.cancel();
    super.dispose();
  }

  Future<void> startCamera() async {
    await Permission.camera.request();
    await Permission.microphone.request();

    WakelockPlus.enable();

    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    controller = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await controller!.initialize();
    await controller!.setFlashMode(FlashMode.torch);

    setState(() {});
  }

  Future<void> startRecording() async {
    if (recording) return;

    await controller!.startVideoRecording();
    recording = true;
    secondsLeft = 20;

    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (secondsLeft == 0) {
        t.cancel();
        await stopRecording();
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  Future<void> stopRecording() async {
    if (!recording) return;

    final file = await controller!.stopVideoRecording();
    recording = false;

    await GallerySaver.saveVideo(file.path);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to Photos')),
    );

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: controller == null
                  ? const Center(child: Text("Press Start"))
                  : CameraPreview(controller!),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () async {
                  if (controller == null) {
                    await startCamera();
                  } else if (!recording) {
                    await startRecording();
                  }
                },
                child: Text(recording ? '$secondsLeft s' : 'Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}