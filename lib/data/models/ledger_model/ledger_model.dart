import 'package:cloud_firestore/cloud_firestore.dart';

class LedgerEntry {
  final String id;          // UNCOMMENTED: Needed for Delete/Edit
  final String type;        // 'income' or 'expenditure'
  final DateTime date;
  final String? voucher;
  final double cash;
  final double bankSbi;
  final double bankHdfc;
  
  // NEW FIELD: Used for sorting entries with the same date
  final int? sheetRowId; 

  LedgerEntry({
    required this.id,       // UNCOMMENTED
    required this.type,
    required this.date,
    this.voucher,
    required this.cash,
    required this.bankSbi,
    required this.bankHdfc,
    this.sheetRowId, 
  });

  // Helper to get total amount
  double get total => cash + bankSbi + bankHdfc;

  factory LedgerEntry.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    
    // Robust Date Parsing
    DateTime parsedDate;
    if (data['date'] is Timestamp) {
      parsedDate = (data['date'] as Timestamp).toDate();
    } else if (data['date'] is String) {
      parsedDate = DateTime.tryParse(data['date']) ?? DateTime(1970, 1, 1);
    } else {
      parsedDate = DateTime.now();
    }

    return LedgerEntry(
      id: doc.id,           // UNCOMMENTED: Stores the Firestore Document ID (e.g. "Ab3X9...")
      type: data['type'] ?? 'expenditure',
      date: parsedDate,
      voucher: data['voucher'],
      cash: (data['cash'] ?? 0).toDouble(),
      bankSbi: (data['bankSbi'] ?? 0).toDouble(),
      bankHdfc: (data['bankHdfc'] ?? 0).toDouble(),
      sheetRowId: data['sheetRowId'], 
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'date': Timestamp.fromDate(date),
      'voucher': voucher,
      'cash': cash,
      'bankSbi': bankSbi,
      'bankHdfc': bankHdfc,
      'sheetRowId': sheetRowId, 
      // Note: We NEVER save 'id' inside 'toMap' because Firestore creates the ID for us automatically.
    };
  }
}