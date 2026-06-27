import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img_lib;

class MLService {
  static final MLService instance = MLService._internal();
  MLService._internal();

  Interpreter? _interpreter;
  FaceDetector? _faceDetector;

  bool get isInitialized => _interpreter != null && _faceDetector != null;

  Future<void> init() async {
    try {
      // 1. Initialize TFLite Interpreter
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      print('MLService: TFLite Interpreter loaded successfully.');
    } catch (e) {
      print('MLService: Error initializing TFLite Interpreter: $e');
    }

    try {
      // 2. Initialize Face Detector (ML Kit)
      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableClassification: false,
      );
      _faceDetector = FaceDetector(options: options);
      print('MLService: ML Kit Face Detector loaded successfully.');
    } catch (e) {
      print('MLService: Error initializing ML Kit Face Detector: $e');
    }
  }

  // Detect faces in an image file
  Future<List<Face>> detectFaces(File imageFile) async {
    print('MLService: detectFaces - Input image path: ${imageFile.path}');
    if (_faceDetector == null) {
      print('MLService: detectFaces - Face detector is null.');
      return [];
    }
    try {
      final inputImage = InputImage.fromFile(imageFile);
      print('MLService: detectFaces - Calling ML Kit face detector...');
      final faces = await _faceDetector!.processImage(inputImage);
      print('MLService: detectFaces - Successfully detected ${faces.length} face(s)');
      return faces;
    } catch (e) {
      print('MLService: detectFaces - Error in face detection: $e');
      return [];
    }
  }

  // Crop face and get its embedding (192 values)
  Future<List<double>?> getEmbedding(File imageFile, Face face) async {
    print('MLService: getEmbedding - Generating embedding...');
    if (_interpreter == null) {
      print('MLService: getEmbedding - TFLite Interpreter is null. Trying to reload...');
      try {
        _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      } catch (e) {
        print('MLService: getEmbedding - TFLite Interpreter reload failed: $e');
        return null;
      }
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final img_lib.Image? originalImage = img_lib.decodeImage(bytes);
      if (originalImage == null) {
        print('MLService: getEmbedding - Failed to decode image.');
        return null;
      }

      // Get bounding box coordinates from ML Kit face
      final rect = face.boundingBox;
      int x = rect.left.toInt().clamp(0, originalImage.width);
      int y = rect.top.toInt().clamp(0, originalImage.height);
      int w = rect.width.toInt().clamp(0, originalImage.width - x);
      int h = rect.height.toInt().clamp(0, originalImage.height - y);
      print('MLService: getEmbedding - Using ML Kit bounding box: x=$x, y=$y, w=$w, h=$h');

      if (w <= 0 || h <= 0) {
        print('MLService: getEmbedding - Crop dimensions invalid (width/height <= 0).');
        return null;
      }

      // Crop face
      final img_lib.Image croppedFace = img_lib.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: w,
        height: h,
      );

      // Resize to 112x112 (model input size)
      final img_lib.Image resizedFace = img_lib.copyResize(
        croppedFace,
        width: 112,
        height: 112,
      );

      // Preprocess image bytes to Float32List of [1, 112, 112, 3]
      var input = List.generate(
        1,
        (index) => List.generate(
          112,
          (y) => List.generate(
            112,
            (x) {
              final pixel = resizedFace.getPixel(x, y);
              // In image v4, pixel channels are r, g, b
              // Map to range [-1.0, 1.0]
              return [
                (pixel.r - 127.5) / 127.5,
                (pixel.g - 127.5) / 127.5,
                (pixel.b - 127.5) / 127.5,
              ];
            },
          ),
        ),
      );

      // Output shape is [1, 192]
      var output = List.filled(192, 0.0).reshape([1, 192]);

      // Run model
      _interpreter!.run(input, output);

      // Extract embedding
      final List<double> embedding = List<double>.from(output[0]);
      
      // Normalize embedding (L2 normalization)
      double sum = 0.0;
      for (var val in embedding) {
        sum += val * val;
      }
      double norm = sqrt(sum);
      if (norm > 0) {
        for (int i = 0; i < embedding.length; i++) {
          embedding[i] = embedding[i] / norm;
        }
      }

      print('MLService: getEmbedding - Successfully generated face embedding.');
      return embedding;
    } catch (e) {
      print('MLService: getEmbedding - Error generating embedding: $e');
      return null;
    }
  }

  // Compare two face embeddings using Euclidean distance
  double compareFaces(List<double> e1, List<double> e2) {
    double sum = 0.0;
    for (int i = 0; i < e1.length; i++) {
      sum += pow(e1[i] - e2[i], 2);
    }
    return sqrt(sum);
  }

  void dispose() {
    _interpreter?.close();
    _faceDetector?.close();
  }
}
