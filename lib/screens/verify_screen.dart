import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/employee.dart';
import '../services/ml_service.dart';

class VerifyScreen extends StatefulWidget {
  final Employee employee;
  const VerifyScreen({super.key, required this.employee});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> with SingleTickerProviderStateMixin {
  final MLService _mlService = MLService.instance;

  // Camera fields
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCameraLoading = true;
  bool _isProcessing = false;

  // Scanning animation
  late AnimationController _animationController;
  late Animation<double> _scanAnimation;

  // Status & Verification Result
  String _statusMessage = 'Align your face in the frame and scan';
  bool? _isMatched; // null = scanning/waiting, true = match, false = mismatch
  String? _verifiedImagePath;

  @override
  void initState() {
    super.initState();
    _initializeMLAndCamera();

    // Set up scanner animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeMLAndCamera() async {
    print('VerifyScreen: _initializeMLAndCamera - MLService isInitialized: ${_mlService.isInitialized}');
    if (!_mlService.isInitialized) {
      setState(() {
        _isCameraLoading = true;
        _statusMessage = 'Loading ML models...';
      });
      await _mlService.init();
      print('VerifyScreen: _initializeMLAndCamera - MLService init completed. isInitialized: ${_mlService.isInitialized}');
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        CameraDescription? frontCamera;
        for (var camera in _cameras) {
          if (camera.lensDirection == CameraLensDirection.front) {
            frontCamera = camera;
            break;
          }
        }
        final selectedCamera = frontCamera ?? _cameras.first;

        _cameraController = CameraController(
          selectedCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        setState(() {
          _isCameraInitialized = true;
          _isCameraLoading = false;
        });
      } else {
        setState(() {
          _isCameraLoading = false;
          _statusMessage = 'No cameras available';
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _isCameraLoading = false;
        _statusMessage = 'Camera error: $e';
      });
    }
  }

  Future<void> _verifyFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('VerifyScreen: _verifyFace - Camera is not initialized.');
      return;
    }
    if (_isProcessing) {
      print('VerifyScreen: _verifyFace - Verification already in progress.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Verifying face...';
      _isMatched = null;
    });

    print('VerifyScreen: _verifyFace - Starting capture...');
    try {
      // 1. Take picture
      final XFile file = await _cameraController!.takePicture();
      final File imageFile = File(file.path);
      print('VerifyScreen: _verifyFace - Image captured: ${imageFile.path}');

      // 2. Detect face
      print('VerifyScreen: _verifyFace - Initiating face detection...');
      List<Face> faces = [];
      try {
        faces = await _mlService.detectFaces(imageFile);
      } catch (e) {
        print('VerifyScreen: _verifyFace - Face detection error: $e');
      }
      print('VerifyScreen: _verifyFace - Face detection result count: ${faces.length}');

      if (faces.isEmpty) {
        print('VerifyScreen: _verifyFace - No faces detected. Aborting.');
        setState(() {
          _statusMessage = 'No face detected! Make sure your face is visible and well-lit.';
          _isMatched = false;
          _isProcessing = false;
        });
        await imageFile.delete();
        return;
      }

      if (faces.length > 1) {
        print('VerifyScreen: _verifyFace - Multiple faces detected. Aborting.');
        setState(() {
          _statusMessage = 'Multiple faces detected! Verify one person at a time.';
          _isMatched = false;
          _isProcessing = false;
        });
        await imageFile.delete();
        return;
      }

      final Face faceToProcess = faces.first;
      print('VerifyScreen: _verifyFace - 1 Face detected. BoundingBox: ${faceToProcess.boundingBox}');

      // 3. Extract face embedding
      print('VerifyScreen: _verifyFace - Requesting embedding from MLService...');
      final List<double>? liveEmbedding = await _mlService.getEmbedding(imageFile, faceToProcess);

      if (liveEmbedding == null) {
        print('VerifyScreen: _verifyFace - Face embedding extraction returned null.');
        setState(() {
          _statusMessage = 'Verification failed. Facial data could not be computed.';
          _isMatched = false;
          _isProcessing = false;
        });
        await imageFile.delete();
        return;
      }

      print('VerifyScreen: _verifyFace - Live embedding generated successfully. Length: ${liveEmbedding.length}');

      // 4. Compare with stored embedding
      print('VerifyScreen: _verifyFace - Comparing live embedding against registered employee embedding...');
      final double distance = _mlService.compareFaces(widget.employee.embedding, liveEmbedding);
      print('VerifyScreen: _verifyFace - Match Euclidean distance: $distance');

      // The standard threshold for MobileFaceNet is ~0.85 for high security.
      // If the distance is less than 0.85, it is a match.
      const double threshold = 0.85; 
      final bool isMatch = distance < threshold;
      print('VerifyScreen: _verifyFace - Distance: $distance vs Threshold: $threshold. Is Match? $isMatch');

      if (isMatch) {
        setState(() {
          _statusMessage = 'Face matched successfully!';
          _isMatched = true;
          _verifiedImagePath = imageFile.path; // Keep file path for display
          _isProcessing = false;
        });
        print('VerifyScreen: _verifyFace - Verification successful.');
      } else {
        setState(() {
          _statusMessage = 'Face not matched! Verification failed.';
          _isMatched = false;
          _isProcessing = false;
        });
        await imageFile.delete(); // Delete mismatched photo
        print('VerifyScreen: _verifyFace - Verification failed (mismatch).');
      }
    } catch (e) {
      print('VerifyScreen: _verifyFace - Error: $e');
      setState(() {
        _statusMessage = 'Error during scanning: $e';
        _isMatched = false;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F222A),
      appBar: AppBar(
        title: const Text(
          'Biometric Verification',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isMatched == true ? _buildProfileDetailsView() : _buildScannerView(),
    );
  }

  Widget _buildScannerView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Target Employee Identity Title
            Text(
              'Verifying Identity For:',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.employee.name,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              '${widget.employee.designation} - ${widget.employee.department}',
              style: TextStyle(color: Colors.indigo[200], fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const Spacer(),

            // Scanner Circular Container
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isMatched == false
                            ? Colors.redAccent
                            : _isProcessing
                                ? Colors.amber
                                : Colors.indigoAccent,
                        width: 4,
                      ),
                    ),
                    child: ClipOval(
                      child: _isCameraInitialized
                          ? AspectRatio(
                              aspectRatio: _cameraController!.value.aspectRatio,
                              child: CameraPreview(_cameraController!),
                            )
                          : Center(
                              child: _isCameraLoading
                                  ? const CircularProgressIndicator(color: Colors.indigoAccent)
                                  : const Icon(Icons.videocam_off, color: Colors.white, size: 50),
                            ),
                    ),
                  ),
                  
                  // Scanning Line Overlay (Only when camera works and not showing error)
                  if (_isCameraInitialized && _isMatched != false && !_isProcessing)
                    AnimatedBuilder(
                      animation: _scanAnimation,
                      builder: (context, child) {
                        return Positioned(
                          top: 40 + (_scanAnimation.value * 200),
                          left: 20,
                          right: 20,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.indigoAccent,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.indigoAccent.withOpacity(0.8),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const Spacer(),

            // Verification status banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _isMatched == false
                    ? Colors.red[900]!.withOpacity(0.3)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isMatched == false
                      ? Colors.redAccent.withOpacity(0.5)
                      : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isMatched == false
                            ? Icons.error_outline
                            : _isProcessing
                                ? Icons.sync
                                : Icons.face,
                        color: _isMatched == false
                            ? Colors.redAccent
                            : _isProcessing
                                ? Colors.amber
                                : Colors.indigoAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: TextStyle(
                            color: _isMatched == false ? Colors.redAccent[100] : Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                  if (_isMatched == false) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'FACE NOT MATCH',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Scan Action Button
            ElevatedButton(
              onPressed: _isProcessing || !_isCameraInitialized ? null : _verifyFace,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMatched == false ? Colors.redAccent : Colors.indigoAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _isProcessing
                    ? 'Verifying...'
                    : _isMatched == false
                        ? 'Retry Scan'
                        : 'Scan & Unlock Details',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDetailsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Match Celebration Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.green[900]!.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: const Column(
              children: [
                Icon(Icons.verified, color: Colors.green, size: 48),
                SizedBox(height: 8),
                Text(
                  'Identity Verified Successfully',
                  style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Face Comparison Side-by-Side Card
          Card(
            color: const Color(0xFF2E323D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    'Biometric Verification Log',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Registered Face
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              height: 110,
                              width: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.indigoAccent, width: 2),
                                image: DecorationImage(
                                  image: FileImage(File(widget.employee.imagePath)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Registered Photo',
                              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      // Match Symbol
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[800],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sync_alt, color: Colors.white, size: 20),
                      ),
                      // Live Scanned Face
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              height: 110,
                              width: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.green, width: 2),
                                image: _verifiedImagePath != null
                                    ? DecorationImage(
                                        image: FileImage(File(_verifiedImagePath!)),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Live Verified Photo',
                              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Employee Details Card
          Card(
            color: const Color(0xFF2E323D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Employee Profile Registry',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  
                  _buildDetailRow('Full Name', widget.employee.name),
                  _buildDetailRow("Father's Name", widget.employee.fatherName),
                  _buildDetailRow('Date of Birth', widget.employee.dob),
                  _buildDetailRow('Gender', widget.employee.gender),
                  _buildDetailRow('Designation', widget.employee.designation),
                  _buildDetailRow('Department', widget.employee.department),
                  _buildDetailRow('Joining Date', widget.employee.joiningDate),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Close button
          ElevatedButton(
            onPressed: () {
              // Clean up verification photo
              try {
                if (_verifiedImagePath != null) {
                  final file = File(_verifiedImagePath!);
                  if (file.existsSync()) {
                    file.deleteSync();
                  }
                }
              } catch (e) {
                print('Error cleanup verified file: $e');
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigoAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'Back to Directory',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
