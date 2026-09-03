import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentRecord {
  final String id;
  final double amount;
  final DateTime date;
  final String type;
  final String referenceId;
  final String remarks;
  final String? imageUrl;

  PaymentRecord({
    required this.id,
    required this.amount,
    required this.date,
    required this.type,
    required this.referenceId,
    this.remarks = '',
    this.imageUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'type': type,
      'referenceId': referenceId,
      'remarks': remarks,
      'imageUrl': imageUrl,
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      date: (map['date'] as Timestamp).toDate(),
      type: map['type'] ?? '',
      referenceId: map['referenceId'] ?? '',
      remarks: map['remarks'] ?? '',
      imageUrl: map['imageUrl'],
    );
  }
}

class Contributor {
  final String id;
  final String name;
  final String type;
  final String contactNumber;
  final String address;
  final String? imageUrl;
  final double targetAmount;
  final GeoPoint? location; // <--- NEW FIELD

  final List<PaymentRecord> paymentHistory;
  final Map<String, double> yearlyPayments;

  Contributor({
    required this.id,
    required this.name,
    required this.type,
    required this.contactNumber,
    required this.address,
    this.imageUrl,
    this.targetAmount = 0.0,
    required this.paymentHistory,
    required this.yearlyPayments,
    this.location, // <--- Add to constructor
  });

  factory Contributor.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    var list = data['paymentHistory'] as List<dynamic>? ?? [];
    List<PaymentRecord> history =
        list.map((i) => PaymentRecord.fromMap(i)).toList();
    history.sort((a, b) => b.date.compareTo(a.date));

    Map<String, double> legacyMap = {};
    if (data['yearlyPayments'] != null) {
      (data['yearlyPayments'] as Map<String, dynamic>).forEach((key, value) {
        legacyMap[key] = (value as num).toDouble();
      });
    }

    return Contributor(
      id: (data['id'] != null && data['id'].toString().trim().isNotEmpty)
          ? data['id'].toString().trim()
          : doc.id,
      name: data['name'] ?? '',
      type: data['type'] ?? 'resident',
      contactNumber: data['contactNumber'] ?? 'N/A',
      address: data['address'] ?? 'N/A',
      imageUrl: data['imageUrl'],
      targetAmount: (data['targetAmount'] ?? 0).toDouble(),
      paymentHistory: history,
      yearlyPayments: legacyMap,
      location: data['location'] as GeoPoint?, // <--- Read from Firestore
    );
  }

  double getYearTotal(int year) {
    double historySum = 0;
    for (var p in paymentHistory) {
      if (p.date.year == year) historySum += p.amount;
    }
    // double legacySum = yearlyPayments[year.toString()] ?? 0;
    return historySum;
    // + legacySum;
  }
}
