class Ticket {
  final int ticketNumber;
  final int bookId;
  final String buyerName;
  final String buyerPhone;
  final bool isSold;
  final bool hasWonConsolation;
  final bool hasWonGrandPrize;

  Ticket({
    required this.ticketNumber,
    required this.buyerName,
    required this.buyerPhone,
    this.isSold = false,
    this.hasWonConsolation = false,
    this.hasWonGrandPrize = false,
  }) : bookId = ((ticketNumber - 1) ~/ 100) + 1;

  // Constructor to create a Ticket from a Map (Firestore data)
  factory Ticket.fromMap(Map<String, dynamic> map, String docId) {
    final tNum = int.tryParse(docId) ?? (map['ticketNumber'] as int? ?? 0);
    return Ticket(
      ticketNumber: tNum,
      buyerName: map['buyerName'] ?? '',
      buyerPhone: map['buyerPhone'] ?? '',
      isSold: map['isSold'] ?? false,
      hasWonConsolation: map['hasWonConsolation'] ?? false,
      hasWonGrandPrize: map['hasWonGrandPrize'] ?? false,
    );
  }

  // Convert Ticket to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'ticketNumber': ticketNumber,
      'bookId': bookId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'isSold': isSold,
      'hasWonConsolation': hasWonConsolation,
      'hasWonGrandPrize': hasWonGrandPrize,
    };
  }

  // Clone with changes
  Ticket copyWith({
    int? ticketNumber,
    String? buyerName,
    String? buyerPhone,
    bool? isSold,
    bool? hasWonConsolation,
    bool? hasWonGrandPrize,
  }) {
    return Ticket(
      ticketNumber: ticketNumber ?? this.ticketNumber,
      buyerName: buyerName ?? this.buyerName,
      buyerPhone: buyerPhone ?? this.buyerPhone,
      isSold: isSold ?? this.isSold,
      hasWonConsolation: hasWonConsolation ?? this.hasWonConsolation,
      hasWonGrandPrize: hasWonGrandPrize ?? this.hasWonGrandPrize,
    );
  }
}
