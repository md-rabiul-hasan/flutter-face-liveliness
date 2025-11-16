import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        minFaceSize: 0.3,
        performanceMode: FaceDetectorMode.fast),
  );

  late CameraController cameraController;
  bool isCameraInitialized = false;
  bool isDetecting = false;
  bool isFrontCamera = true;

  // Fixed order: 1. Left Move, 2. Right Move, 3. Smile, 4. Eye Blink
  List<String> challengeActions = ['lookLeft', 'lookRight', 'smile', 'blink'];
  int currentActionIndex = 0;
  bool waitingForNeutral = false;
  bool verificationComplete = false;
  bool isCaptured = false;
  Uint8List? capturedImage;

  double? smilingProbability;
  double? leftEyeOpenProbability;
  double? rightEyeOpenProbability;
  double? headEulerAngleY;

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  // Initialize the camera controller
  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front);
    cameraController = CameraController(frontCamera, ResolutionPreset.high,
        enableAudio: false);
    await cameraController.initialize();
    if (mounted) {
      setState(() {
        isCameraInitialized = true;
      });
      startFaceDetection();
    }
  }

  // Start face detection on the camera image stream
  void startFaceDetection() {
    if (isCameraInitialized) {
      cameraController.startImageStream((CameraImage image) {
        if (!isDetecting) {
          isDetecting = true;
          detectFaces(image).then((_) {
            isDetecting = false;
          });
        }
      });
    }
  }

  // Detect faces in the camera image
  Future<void> detectFaces(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation270deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isNotEmpty) {
        final face = faces.first;
        setState(() {
          smilingProbability = face.smilingProbability;
          leftEyeOpenProbability = face.leftEyeOpenProbability;
          rightEyeOpenProbability = face.rightEyeOpenProbability;
          headEulerAngleY = face.headEulerAngleY;
        });

        if (!verificationComplete) {
          checkChallenge(face);
        } else if (!isCaptured) {
          // After verification, check if face is straight and capture
          if (isFaceStraight(face)) {
            await captureImage();
          }
        }
      }
    } catch (e) {
      debugPrint('Error in face detection: $e');
    }
  }

  // Check if the face is performing the current challenge action
  void checkChallenge(Face face) async {
    if (waitingForNeutral) {
      if (isNeutralPosition(face)) {
        waitingForNeutral = false;
      } else {
        return;
      }
    }

    String currentAction = challengeActions[currentActionIndex];
    bool actionCompleted = false;

    switch (currentAction) {
      case 'smile':
        actionCompleted =
            face.smilingProbability != null && face.smilingProbability! > 0.5;
        break;
      case 'blink':
        actionCompleted = (face.leftEyeOpenProbability != null &&
            face.leftEyeOpenProbability! < 0.3) &&
            (face.rightEyeOpenProbability != null &&
                face.rightEyeOpenProbability! < 0.3);
        break;
      case 'lookRight':
        actionCompleted =
            face.headEulerAngleY != null && face.headEulerAngleY! < -10;
        break;
      case 'lookLeft':
        actionCompleted =
            face.headEulerAngleY != null && face.headEulerAngleY! > 10;
        break;
    }

    if (actionCompleted) {
      currentActionIndex++;
      if (currentActionIndex >= challengeActions.length) {
        // All challenges completed, now wait for straight face
        setState(() {
          verificationComplete = true;
        });
      } else {
        waitingForNeutral = true;
      }
    }
  }

  // Check if face is straight (neutral position)
  bool isFaceStraight(Face face) {
    return (face.headEulerAngleY == null ||
        (face.headEulerAngleY! > -5 && face.headEulerAngleY! < 5)) &&
        (face.smilingProbability == null || face.smilingProbability! < 0.3) &&
        (face.leftEyeOpenProbability == null ||
            face.leftEyeOpenProbability! > 0.7) &&
        (face.rightEyeOpenProbability == null ||
            face.rightEyeOpenProbability! > 0.7);
  }

  // Check if the face is in a neutral position
  bool isNeutralPosition(Face face) {
    return (face.smilingProbability == null ||
        face.smilingProbability! < 0.1) &&
        (face.leftEyeOpenProbability == null ||
            face.leftEyeOpenProbability! > 0.7) &&
        (face.rightEyeOpenProbability == null ||
            face.rightEyeOpenProbability! > 0.7) &&
        (face.headEulerAngleY == null ||
            (face.headEulerAngleY! > -5 && face.headEulerAngleY! < 5));
  }

  // Capture image when face is straight after verification
  Future<void> captureImage() async {
    try {
      // Stop the camera stream first
      cameraController.stopImageStream();

      // Take the picture
      final XFile file = await cameraController.takePicture();

      // Read the image file as bytes
      final Uint8List imageBytes = await file.readAsBytes();

      if (mounted) {
        setState(() {
          isCaptured = true;
          capturedImage = imageBytes;
        });
      }
    } catch (e) {
      debugPrint('Error capturing image: $e');
      // If capture fails, navigate back
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  void proceedToNext() {
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    if (!isCaptured) {
      cameraController.stopImageStream();
    }
    faceDetector.close();
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.amberAccent,
        toolbarHeight: 70,
        centerTitle: true,
        title: const Text("Verify Your Identity"),
      ),
      body: isCameraInitialized
          ? isCaptured
          ? _buildCapturedImage()
          : _buildCameraView()
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        // Full camera preview
        Positioned.fill(
          child: CameraPreview(cameraController),
        ),
        // White overlay with circular cutout
        CustomPaint(
          painter: HeadMaskPainter(),
          child: Container(),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (!verificationComplete) ...[
                  Text(
                    'Please ${getActionDescription(challengeActions[currentActionIndex])}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${currentActionIndex + 1} of ${challengeActions.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  const Text(
                    'Verification Complete!',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please look straight at the camera',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Auto capturing...',
                    style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCapturedImage() {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.white,
            child: Center(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.amberAccent,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: capturedImage != null
                      ? Image.memory(
                    capturedImage!,
                    fit: BoxFit.cover,
                    width: 300,
                    height: 300,
                  )
                      : Container(
                    color: Colors.grey[300],
                    child: const Icon(
                      Icons.person,
                      size: 100,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: Column(
            children: [
              const Text(
                'Identity Verified Successfully!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your photo has been captured and verified.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: proceedToNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Get the description of the current challenge action
  String getActionDescription(String action) {
    switch (action) {
      case 'smile':
        return 'smile';
      case 'blink':
        return 'blink your eyes';
      case 'lookRight':
        return 'turn your head to the right';
      case 'lookLeft':
        return 'turn your head to the left';
      default:
        return '';
    }
  }
}

// Custom painter for head mask with white background outside circle
class HeadMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    // Create a path for the white overlay (outside the circle)
    final path = Path()
    // Start with the circle (this will be the cutout)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
    // Then add the entire rectangle around it
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..fillType = PathFillType.evenOdd;

    // Draw white overlay outside the circle
    final overlayPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, overlayPaint);

    // Border around the circle
    final borderPaint = Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(center, radius, borderPaint);

    // Add instructional text in the white area
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Position your face within the circle',
        style: TextStyle(
          color: Colors.black54,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height * 0.15,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}