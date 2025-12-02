import 'package:hive/hive.dart';

part 'student.g.dart';

@HiveType(typeId: 0)
class Student extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String name;

  @HiveField(2)
  late double balance;

  @HiveField(3)
  late List<double> faceEmbedding;

  @HiveField(4)
  late DateTime enrolledAt;

  Student({
    required this.id,
    required this.name,
    required this.balance,
    required this.faceEmbedding,
    required this.enrolledAt,
  });
}
