class Employee {
  final String id;
  final String name;
  final String fatherName;
  final String dob;
  final String gender;
  final String designation;
  final String department;
  final String joiningDate;
  final String imagePath;
  final List<double> embedding;

  Employee({
    required this.id,
    required this.name,
    required this.fatherName,
    required this.dob,
    required this.gender,
    required this.designation,
    required this.department,
    required this.joiningDate,
    required this.imagePath,
    required this.embedding,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'fatherName': fatherName,
      'dob': dob,
      'gender': gender,
      'designation': designation,
      'department': department,
      'joiningDate': joiningDate,
      'imagePath': imagePath,
      'embedding': embedding,
    };
  }

  factory Employee.fromMap(Map<dynamic, dynamic> map) {
    return Employee(
      id: map['id'] as String,
      name: map['name'] as String,
      fatherName: map['fatherName'] as String,
      dob: map['dob'] as String,
      gender: map['gender'] as String,
      designation: map['designation'] as String,
      department: map['department'] as String,
      joiningDate: map['joiningDate'] as String,
      imagePath: map['imagePath'] as String,
      embedding: (map['embedding'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
    );
  }
}
