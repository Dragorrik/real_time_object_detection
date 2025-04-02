import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ObjectDetectionScreen(),
    );
  }
}

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({super.key});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> {
  late CameraController _cameraController;
  bool _isDetecting = false;
  List<DetectedObject> _detectedObjects = [];
  late ObjectDetector _objectDetector;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeDetector();
  }

  void _initializeCamera() {
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _startDetection();
    });
  }

  void _initializeDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  void _startDetection() {
    _cameraController.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;

      try {
        final file = await _convertImage(image);
        final inputImage = InputImage.fromFile(file);
        final objects = await _objectDetector.processImage(inputImage);

        if (mounted) {
          setState(() {
            _detectedObjects = objects;
          });
        }
      } catch (e) {
        debugPrint("Error detecting objects: $e");
      }

      _isDetecting = false;
    });
  }

  Future<File> _convertImage(CameraImage image) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/frame.jpg';
    final file = File(filePath);
    await file.writeAsBytes(image.planes[0].bytes);
    return file;
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _objectDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Real-Time Object Detection")),
      body: Stack(
        children: [
          if (_cameraController.value.isInitialized) ...[
            CameraPreview(_cameraController),
            _buildBoundingBoxes(),
          ] else
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildBoundingBoxes() {
    return Positioned.fill(
      child: Stack(
        children:
            _detectedObjects.map((detectedObject) {
              final rect = detectedObject.boundingBox;
              return Positioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Text(
                    detectedObject.labels.isNotEmpty
                        ? detectedObject.labels.first.text
                        : "Unknown",
                    style: const TextStyle(
                      color: Colors.white,
                      backgroundColor: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
