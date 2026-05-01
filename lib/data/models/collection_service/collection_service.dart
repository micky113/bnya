import 'package:cloud_firestore/cloud_firestore.dart';

class CollectionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Call this function when an admin enters a new payment amount
  Future<void> recordPayment({
    required String contributorId, // e.g., 'SHOP_001'
    required String contributorName,
    required double amountCollected,
    required String year, // e.g., '2025'
    required String collectedBy,
  }) async {
    
    // References
    final contributorRef = _db.collection('contributors').doc(contributorId);
    final financeRef = _db.collection('finances').doc(); // Auto-ID

    // Run a Transaction to ensure data consistency
    await _db.runTransaction((transaction) async {
      
      // 1. Read the current contributor data
      DocumentSnapshot snapshot = await transaction.get(contributorRef);

      if (!snapshot.exists) {
        throw Exception("Contributor does not exist!");
      }

      // 2. Calculate the new total for that year
      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      Map<String, dynamic> yearlyPayments = data['yearlyPayments'] != null 
          ? Map<String, dynamic>.from(data['yearlyPayments']) 
          : {};

      double currentYearTotal = (yearlyPayments[year] ?? 0).toDouble();
      double newTotal = currentYearTotal + amountCollected;

      // Update the local map
      yearlyPayments[year] = newTotal;

      // 3. Write: Update the Contributor's running total
      transaction.update(contributorRef, {
        'yearlyPayments': yearlyPayments,
        'lastPaymentDate': FieldValue.serverTimestamp(),
      });

      // 4. Write: Create the Transaction Record (Receipt)
      transaction.set(financeRef, {
        'contributorId': contributorId,
        'contributorName': contributorName,
        'amount': amountCollected,
        'year': year,
        'collectedBy': collectedBy,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'income',
        'source': 'collection'
      });
    });
  }
}