import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_utils;
import '../models/employee.dart';
import '../services/database_service.dart';
import '../services/ml_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final MLService _mlService = MLService.instance;
  final DatabaseService _dbService = DatabaseService.instance;

  // Form Fields Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _joiningDateController = TextEditingController();
  String _gender = 'Male';

  // Camera fields
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCameraLoading = true;
  bool _isProcessingFace = false;

  // Captured Face Data
  String? _capturedImagePath;
  List<double>? _faceEmbedding;
  String? _faceStatusMessage;
  bool _faceCaptureSuccess = false;

  @override
  void initState() {
    super.initState();
    _initializeMLAndCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _nameController.dispose();
    _fatherNameController.dispose();
    _dobController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _joiningDateController.dispose();
    super.dispose();
  }

  Future<void> _initializeMLAndCamera() async {
    print('RegisterScreen: _initializeMLAndCamera - MLService isInitialized: ${_mlService.isInitialized}');
    if (!_mlService.isInitialized) {
      setState(() {
        _isCameraLoading = true;
        _faceStatusMessage = 'Loading ML models...';
      });
      await _mlService.init();
      print('RegisterScreen: _initializeMLAndCamera - MLService init completed. isInitialized: ${_mlService.isInitialized}');
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        // Find front camera
        CameraDescription? frontCamera;
        for (var camera in _cameras) {
          if (camera.lensDirection == CameraLensDirection.front) {
            frontCamera = camera;
            break;
          }
        }
        
        // Fallback to first camera if front not found
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
          _faceStatusMessage = 'No cameras available on this device';
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _isCameraLoading = false;
        _faceStatusMessage = 'Camera initialization failed: $e';
      });
    }
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // default 18 years ago
      firstDate: DateTime(1950),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              onSurface: Colors.indigo,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _captureFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('RegisterScreen: _captureFace - Camera is not initialized.');
      return;
    }
    if (_isProcessingFace) {
      print('RegisterScreen: _captureFace - Face processing is already in progress.');
      return;
    }

    setState(() {
      _isProcessingFace = true;
      _faceStatusMessage = 'Scanning face...';
      _faceCaptureSuccess = false;
    });

    print('RegisterScreen: _captureFace - Starting capture...');
    try {
      // 1. Take picture
      final XFile file = await _cameraController!.takePicture();
      final File imageFile = File(file.path);
      print('RegisterScreen: _captureFace - Image captured: ${imageFile.path}');

      // 2. Detect face
      print('RegisterScreen: _captureFace - Initiating face detection...');
      List<Face> faces = [];
      try {
        faces = await _mlService.detectFaces(imageFile);
      } catch (e) {
        print('RegisterScreen: _captureFace - Face detection error: $e');
      }
      print('RegisterScreen: _captureFace - Face detection result count: ${faces.length}');

      if (faces.isEmpty) {
        print('RegisterScreen: _captureFace - No faces detected. Aborting.');
        setState(() {
          _faceStatusMessage = 'No face detected. Please face the camera directly in a well-lit area.';
          _isProcessingFace = false;
        });
        await imageFile.delete();
        return;
      }

      if (faces.length > 1) {
        print('RegisterScreen: _captureFace - Multiple faces detected. Aborting.');
        setState(() {
          _faceStatusMessage = 'Multiple faces detected. Ensure only one person is in the frame.';
          _isProcessingFace = false;
        });
        await imageFile.delete();
        return;
      }

      final Face faceToProcess = faces.first;
      print('RegisterScreen: _captureFace - 1 Face detected. BoundingBox: ${faceToProcess.boundingBox}');

      // 3. Extract face embedding
      print('RegisterScreen: _captureFace - Requesting embedding from MLService...');
      final List<double>? embedding = await _mlService.getEmbedding(imageFile, faceToProcess);

      if (embedding == null) {
        print('RegisterScreen: _captureFace - Face embedding extraction returned null.');
        setState(() {
          _faceStatusMessage = 'Could not process facial features. Try again.';
          _isProcessingFace = false;
        });
        await imageFile.delete();
        return;
      }

      print('RegisterScreen: _captureFace - Embedding generated successfully. Length: ${embedding.length}');

      // Save the captured image to permanent app directory
      final appDir = await getApplicationDocumentsDirectory();
      final String fileName = 'face_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String savedPath = path_utils.join(appDir.path, fileName);
      await imageFile.copy(savedPath);
      print('RegisterScreen: _captureFace - Saved image permanently to: $savedPath');

      // Delete temporary camera file
      await imageFile.delete();

      setState(() {
        _capturedImagePath = savedPath;
        _faceEmbedding = embedding;
        _faceCaptureSuccess = true;
        _faceStatusMessage = 'Face biometric registration successful!';
        _isProcessingFace = false;
      });
      print('RegisterScreen: _captureFace - Capture flow completed successfully.');
    } catch (e) {
      print('RegisterScreen: _captureFace - Error: $e');
      setState(() {
        _faceStatusMessage = 'Error scanning face: $e';
        _isProcessingFace = false;
      });
    }
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_faceCaptureSuccess || _capturedImagePath == null || _faceEmbedding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture your face biometric before saving'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newEmployee = Employee(
      id: id,
      name: _nameController.text.trim(),
      fatherName: _fatherNameController.text.trim(),
      dob: _dobController.text.trim(),
      gender: _gender,
      designation: _designationController.text.trim(),
      department: _departmentController.text.trim(),
      joiningDate: _joiningDateController.text.trim(),
      imagePath: _capturedImagePath!,
      embedding: _faceEmbedding!,
    );

    try {
      await _dbService.saveEmployee(newEmployee);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employee registered successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true); // Return success to reload HomeScreen list
    } catch (e) {
      print('Error saving employee: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to register employee: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          'Register New Employee',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Biometric Capture Card
              _buildBiometricCaptureCard(),
              const SizedBox(height: 16),
              
              // 2. Form Fields Card
              _buildFormCard(),
              const SizedBox(height: 24),
              
              // 3. Save Button
              ElevatedButton(
                onPressed: _saveEmployee,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: const Text(
                  'Save Registry',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricCaptureCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Face Biometric Registration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Container(
              height: 240,
              width: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _faceCaptureSuccess ? Colors.green : Colors.indigo.shade200,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: _faceCaptureSuccess && _capturedImagePath != null
                    ? Image.file(
                        File(_capturedImagePath!),
                        fit: BoxFit.cover,
                      )
                    : _isCameraInitialized
                        ? AspectRatio(
                            aspectRatio: _cameraController!.value.aspectRatio,
                            child: CameraPreview(_cameraController!),
                          )
                        : Center(
                            child: _isCameraLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Icon(Icons.videocam_off, color: Colors.white, size: 48),
                          ),
              ),
            ),
            const SizedBox(height: 16),
            if (_faceStatusMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _faceCaptureSuccess ? Colors.green[50] : Colors.amber[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _faceCaptureSuccess ? Colors.green.shade200 : Colors.amber.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _faceCaptureSuccess ? Icons.check_circle : Icons.info_outline,
                      color: _faceCaptureSuccess ? Colors.green[700] : Colors.amber[800],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _faceStatusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _faceCaptureSuccess ? Colors.green[700] : Colors.amber[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_faceCaptureSuccess)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _faceCaptureSuccess = false;
                        _capturedImagePath = null;
                        _faceEmbedding = null;
                        _faceStatusMessage = 'Retake face scan';
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake Scan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _isProcessingFace || !_isCameraInitialized ? null : _captureFace,
                    icon: _isProcessingFace
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt, color: Colors.white),
                    label: Text(
                      _isProcessingFace ? 'Scanning...' : 'Capture Face',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personal & Work Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              
              // Name
              TextFormField(
                controller: _nameController,
                decoration: _buildInputDecoration('Full Name', Icons.person_outline),
                validator: (value) => value == null || value.isEmpty ? 'Please enter name' : null,
              ),
              const SizedBox(height: 16),
              
              // Father Name
              TextFormField(
                controller: _fatherNameController,
                decoration: _buildInputDecoration("Father's Name", Icons.person),
                validator: (value) => value == null || value.isEmpty ? 'Please enter father\'s name' : null,
              ),
              const SizedBox(height: 16),
              
              // DOB & Gender Row
              Row(
                children: [
                  // DOB
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: () => _selectDate(context, _dobController),
                      decoration: _buildInputDecoration('Date of Birth', Icons.calendar_today),
                      validator: (value) => value == null || value.isEmpty ? 'Select DOB' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Gender
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _gender,
                      decoration: _buildInputDecoration('Gender', Icons.wc),
                      items: ['Male', 'Female', 'Other']
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _gender = val!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Designation
              TextFormField(
                controller: _designationController,
                decoration: _buildInputDecoration('Designation', Icons.badge_outlined),
                validator: (value) => value == null || value.isEmpty ? 'Please enter designation' : null,
              ),
              const SizedBox(height: 16),
              
              // Department
              TextFormField(
                controller: _departmentController,
                decoration: _buildInputDecoration('Department', Icons.business_outlined),
                validator: (value) => value == null || value.isEmpty ? 'Please enter department' : null,
              ),
              const SizedBox(height: 16),
              
              // Joining Date
              TextFormField(
                controller: _joiningDateController,
                readOnly: true,
                onTap: () => _selectDate(context, _joiningDateController),
                decoration: _buildInputDecoration('Joining Date', Icons.date_range_outlined),
                validator: (value) => value == null || value.isEmpty ? 'Select Joining Date' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String labelText, IconData icon) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(icon, color: Colors.indigo.shade300, size: 20),
      labelStyle: const TextStyle(fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.indigo, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }
}
