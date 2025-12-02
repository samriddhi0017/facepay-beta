import 'package:hive/hive.dart';

part 'transaction.g.dart';

@HiveType(typeId: 1)
class Transaction extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String studentId;

  @HiveField(2)
  late double amount;

  @HiveField(3)
  late DateTime timestamp;

  @HiveField(4)
  late String type; // 'payment', 'topup'

  @HiveField(5)
  late String description;

  Transaction({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.timestamp,
    required this.type,
    required this.description,
  });
}
