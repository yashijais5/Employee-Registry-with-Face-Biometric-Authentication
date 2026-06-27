import 'package:hive_flutter/hive_flutter.dart';
import '../models/employee.dart';

class DatabaseService {
  static const String _boxName = 'employees';

  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  Box get _box => Hive.box(_boxName);

  List<Employee> getEmployees() {
    return _box.values.map((item) {
      // Cast the dynamic value to Map
      final Map<dynamic, dynamic> map = Map<dynamic, dynamic>.from(item as Map);
      return Employee.fromMap(map);
    }).toList();
  }

  Future<void> saveEmployee(Employee employee) async {
    await _box.put(employee.id, employee.toMap());
  }

  Future<void> deleteEmployee(String id) async {
    await _box.delete(id);
  }
  
  Future<void> clearAll() async {
    await _box.clear();
  }
}
