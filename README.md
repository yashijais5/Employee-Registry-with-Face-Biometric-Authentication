# Employee Registry with Face Biometric Authentication

## Project Overview

Employee Registry is a Flutter application that registers employees using facial biometrics. Every employee is registered with personal details along with a facial embedding generated using a Machine Learning model.

Whenever an employee wants to access their profile, the application captures their current face and compares it with the registered face. If both faces match, the employee details are displayed; otherwise, access is denied.

---

# Features

- Employee Registration
- Face Detection
- Face Recognition
- Face Verification
- Local Database Storage
- Offline Working
- Employee Search
- Employee Delete
- Secure Employee Verification

---

# Technologies Used

### Flutter

Used for developing the complete mobile application UI.

### Google ML Kit

Used only for Face Detection.

Responsibilities:

- Detect face in image
- Return bounding box
- Ensure only one face is detected

---

### TensorFlow Lite (MobileFaceNet)

Used for Face Recognition.

Responsibilities:

- Crop detected face
- Generate 192-dimensional face embedding
- Convert face into mathematical representation

Model Used:

mobilefacenet.tflite

---

### Hive Database

Used as local NoSQL database.

Stores

- Employee Details
- Registered Image Path
- Face Embedding

Works completely offline.

---

### Camera Package

Used for

- Capture employee image
- Capture verification image

---

# Project Structure

```
lib/
│
├── models/
│      employee.dart
│
├── services/
│      ml_service.dart
│      database_service.dart
│
├── screens/
│      home_screen.dart
│      register_screen.dart
│      verify_screen.dart
│
└── main.dart
```

---

# Application Flow

```
App Start
      │
      ▼
Initialize Hive Database
      │
      ▼
Initialize ML Kit
      │
      ▼
Load MobileFaceNet Model
      │
      ▼
Open Home Screen
```

---

# Employee Registration Flow

```
Register Employee
        │
        ▼
Fill Employee Details
        │
        ▼
Capture Face
        │
        ▼
Detect Face using ML Kit
        │
        ▼
Crop Face
        │
        ▼
Resize Image (112x112)
        │
        ▼
Generate Face Embedding
        │
        ▼
Save Employee Details
        │
        ▼
Store in Hive Database
```

---

# Face Detection

Face Detection is performed using Google ML Kit.

```
Input Image
      │
      ▼
ML Kit Face Detector
      │
      ▼
Face Object
      │
      ▼
Bounding Box
```

Bounding Box Example

```
Left
Top
Width
Height
```

Using these coordinates only the face portion is cropped.

---

# Image Preprocessing

After cropping,

Face Image

↓

Resize

```
112 x 112
```

↓

Normalize Pixel Values

```
(pixel - 127.5) / 127.5
```

Range

```
-1 to +1
```

This format is required by MobileFaceNet.

---

# Face Embedding

After preprocessing,

the image is passed into MobileFaceNet.

```
Interpreter.run(input, output)
```

Output

```
192 Floating Values
```

Example

```
[
0.34,
-0.18,
0.72,
...
]
```

This vector represents the unique facial features.

This is called

**Face Embedding**

---

# Embedding Normalization

L2 Normalization is applied.

```
embedding = embedding / norm
```

Purpose

- Better comparison
- Improved accuracy
- Same vector scale

---

# Employee Object

Each employee stores

```
ID
Name
Father Name
DOB
Gender
Designation
Department
Joining Date
Image Path
Face Embedding
```

---

# Database

Hive stores

```
Employee
│
├── Personal Details
├── Image Path
└── Face Embedding
```

Everything works offline.

---

# Home Screen

When app starts

```
Hive
    │
    ▼
Read Employees
    │
    ▼
Display Employee List
```

Features

- Search Employee
- Delete Employee
- Verify Employee

---

# Verification Flow

```
Select Employee
        │
        ▼
Open Camera
        │
        ▼
Capture Current Face
        │
        ▼
Detect Face
        │
        ▼
Generate Current Embedding
        │
        ▼
Read Stored Embedding
        │
        ▼
Compare Both Embeddings
```

---

# Face Comparison

Comparison is performed using

## Euclidean Distance

Formula

distance = √Σ(x₁ − x₂)²

Where

- x₁ = Registered Face Embedding
- x₂ = Current Face Embedding

---

# Decision

If

```
Distance < Threshold
```

Result

```
Face Matched
```

Employee Details Open.

Otherwise

```
Distance > Threshold
```

Result

```
Verification Failed
```

Access Denied.

---

# Why Face Embedding Instead of Image Comparison?

Images may change because of

- Lighting
- Camera Angle
- Distance
- Background

Embedding contains only facial features.

Therefore comparison becomes much more accurate.

---

# Why Hive?

Advantages

- Lightweight
- Fast
- Offline Storage
- No Internet Required
- Easy CRUD Operations

---

# Why ML Kit?

Advantages

- Fast Face Detection
- Accurate Detection
- Detects Bounding Box
- Optimized for Mobile Devices

---

# Why TensorFlow Lite?

Advantages

- On-device Inference
- No Internet Required
- Fast Prediction
- Lightweight ML Model

---

# Important Classes

## MLService

Responsibilities

- Load ML Model
- Detect Face
- Crop Face
- Generate Embedding
- Compare Faces

---

## DatabaseService

Responsibilities

- Initialize Hive
- Save Employee
- Read Employees
- Delete Employee

---

## Employee Model

Contains

- Employee Information
- Image Path
- Face Embedding

---

## RegisterScreen

Responsibilities

- Capture Face
- Generate Embedding
- Save Employee

---

## HomeScreen

Responsibilities

- Display Employees
- Search Employee
- Delete Employee
- Navigate to Verification

---

## VerifyScreen

Responsibilities

- Capture Current Face
- Generate Embedding
- Compare with Registered Face
- Show Details if Matched

---

# Interview Explanation (2 Minutes)

"This project is a Flutter-based Employee Registry application that uses facial biometrics for employee authentication. During registration, Google ML Kit detects the face, MobileFaceNet generates a 192-dimensional face embedding, and both employee details and embeddings are stored locally using Hive. During verification, a new face embedding is generated from the live camera image and compared with the stored embedding using Euclidean Distance. If the distance is below the predefined threshold, the employee is authenticated and their details are displayed; otherwise, access is denied. Since the entire process runs on-device using TensorFlow Lite and Hive, the application works completely offline."