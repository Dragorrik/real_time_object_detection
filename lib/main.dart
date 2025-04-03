import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

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
    _testObjectDetection(); // Testing with a sample image
  }

  void _initializeCamera() async {
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController.initialize();
    if (!mounted) return;

    print(
      "Camera Initialized: Resolution - ${_cameraController.value.previewSize}",
    );
    setState(() {});
    _startDetection();
  }

  void _initializeDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
    print("Object Detector Initialized Successfully");
  }

  void _startDetection() {
    _cameraController.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;

      try {
        print("Processing image...");
        final inputImage = await _convertCameraImage(image);
        final objects = await _objectDetector.processImage(inputImage);

        if (mounted) {
          setState(() {
            _detectedObjects = objects;
          });
        }

        if (objects.isEmpty) {
          print("No objects detected.");
        } else {
          print("Objects detected: ${objects.length}");
          for (var obj in objects) {
            print(
              "Detected Object: ${obj.labels.isNotEmpty ? obj.labels.first.text : "Unknown"}",
            );
          }
        }
      } catch (e) {
        print("Error detecting objects: $e");
      }

      _isDetecting = false;
    });
  }

  Future<InputImage> _convertCameraImage(CameraImage image) async {
    print(
      "Converting Camera Image - Format: ${image.format.group}, Width: ${image.width}, Height: ${image.height}",
    );

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String tempPath = '${tempDir.path}/frame.jpg';
      final File file = File(tempPath);

      // Convert YUV420 image to JPEG
      final Uint8List bytes = _convertYUV420ToJPEG(image);
      await file.writeAsBytes(bytes);

      print("Image successfully converted to JPEG: $tempPath");

      return InputImage.fromFilePath(tempPath);
    } catch (e) {
      print("Error converting image: $e");
      throw Exception("Failed to convert image");
    }
  }

  Uint8List _convertYUV420ToJPEG(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    // Fix: Use correct Image constructor
    img.Image rgbImage = img.Image(width: width, height: height);

    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);

        final int yp =
            image.planes[0].bytes[y * image.planes[0].bytesPerRow + x];
        final int up = image.planes[1].bytes[uvIndex];
        final int vp = image.planes[2].bytes[uvIndex];

        int r = (yp + 1.370705 * (vp - 128)).toInt();
        int g = (yp - 0.698001 * (vp - 128) - 0.337633 * (up - 128)).toInt();
        int b = (yp + 1.732446 * (up - 128)).toInt();

        // Fix: Add alpha (opacity) value = 255 (fully opaque)
        rgbImage.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    // Convert to JPEG format
    return Uint8List.fromList(img.encodeJpg(rgbImage));
  }

  void _testObjectDetection() async {
    try {
      // Load asset as byte data
      final ByteData data = await rootBundle.load('assets/sample.png');
      final Uint8List bytes = data.buffer.asUint8List();

      // Get temporary directory to store the image
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/sample.png');

      // Write the asset bytes to a file
      await file.writeAsBytes(bytes);

      // Create InputImage from the file
      final inputImage = InputImage.fromFilePath(file.path);
      print("Image loaded successfully: ${file.path}");

      // Run object detection
      final objects = await _objectDetector.processImage(inputImage);

      if (objects.isEmpty) {
        print("No objects detected in sample image.");
      } else {
        print("Objects detected in sample image: ${objects.length}");
        for (var obj in objects) {
          print(
            "Detected Object: ${obj.labels.isNotEmpty ? obj.labels.first.text : "Unknown"}",
          );
        }
      }
    } catch (e) {
      print("Error loading image: $e");
    }
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
