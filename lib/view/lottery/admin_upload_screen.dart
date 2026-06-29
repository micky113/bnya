import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bnya/view/lottery/ticket_model.dart';

class AdminUploadScreen extends StatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ticketController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isSavingSingle = false;

  @override
  void dispose() {
    _ticketController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }



  // Save single ticket with duplication checks
  Future<void> _saveSingleTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingSingle = true);

    try {
      final String name = _nameController.text.trim();
      final String phone = _phoneController.text.trim();

      // Parse ticket numbers using robust regex range parser
      final List<int> ticketNums = _parseTicketNumbers(_ticketController.text);

      final List<int> uniqueNums = ticketNums.toSet().toList();

      if (uniqueNums.isEmpty) {
        setState(() => _isSavingSingle = false);
        return;
      }

      // Duplication check in Firestore in parallel
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final List<DocumentSnapshot> docSnaps = await Future.wait(
        uniqueNums.map((n) => firestore.collection('tickets').doc(n.toString()).get())
      );

      final List<int> existingTickets = [];
      for (final snap in docSnaps) {
        if (snap.exists) {
          final int? existingNum = int.tryParse(snap.id);
          if (existingNum != null) {
            existingTickets.add(existingNum);
          }
        }
      }

      if (existingTickets.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: Ticket(s) #${existingTickets.join(', ')} already registered!"),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSavingSingle = false);
        return;
      }

      // Write tickets in a batch write
      final WriteBatch batch = firestore.batch();
      for (final n in uniqueNums) {
        final int bookId = ((n - 1) ~/ 100) + 1;
        final ticket = Ticket(
          ticketNumber: n,
          bookId: bookId,
          buyerName: name,
          buyerPhone: phone,
          isSold: true,
        );
        final docRef = firestore.collection('tickets').doc(n.toString());
        batch.set(docRef, ticket.toMap());
      }

      // Create/Update the daily ledger entry for lottery ticket sales
      final now = DateTime.now();
      final dateStr = "${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}";
      final ledgerDocId = "lottery_sales_$dateStr";
      final ledgerRef = firestore.collection('ledger').doc(ledgerDocId);
      
      batch.set(ledgerRef, {
        'type': 'income',
        'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
        'voucher': 'Lottery Ticket Sales - ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
        'cash': FieldValue.increment(uniqueNums.length * 100.0),
        'bankSbi': 0.0,
        'bankHdfc': 0.0,
        'sheetRowId': DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Create/Update the contributor profile for the lottery ticket buyer
      final String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final String contributorDocId = cleanPhone.isNotEmpty
          ? cleanPhone
          : name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toUpperCase();
      final contributorRef = firestore.collection('contributors').doc(contributorDocId);

      final double ticketAmount = uniqueNums.length * 100.0;
      final newPayment = {
        'id': 'lottery_${now.millisecondsSinceEpoch}_${uniqueNums.first}',
        'amount': ticketAmount,
        'date': Timestamp.fromDate(now),
        'type': 'Lottery',
        'referenceId': '',
        'remarks': 'Tickets: ${uniqueNums.map((e) => '#${Ticket.formatNumber(e)}').join(', ')}',
        'imageUrl': null,
      };

      batch.set(contributorRef, {
        'id': contributorDocId,
        'name': name,
        'type': 'lottery_buyer',
        'contactNumber': phone,
        'address': 'N/A',
        'paymentHistory': FieldValue.arrayUnion([newPayment]),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ticket(s) #${uniqueNums.join(', ')} successfully registered!"),
            backgroundColor: Colors.green,
          ),
        );
        _ticketController.clear();
        _nameController.clear();
        _phoneController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to register tickets: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSingle = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FA),
      appBar: AppBar(
        title: const Text(
          "Admin Ticket Registration",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00695C),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Card(
                color: const Color(0xFF00695C),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white24,
                        radius: isMobile ? 22 : 28,
                        child: Icon(Icons.app_registration, color: Colors.white, size: isMobile ? 24 : 30),
                      ),
                      SizedBox(width: isMobile ? 12 : 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Lottery Registration Panel",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 18 : 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isMobile
                                  ? "Register sold tickets. Range: 1 - 20,000. Book ID is automatic."
                                  : "Register sold tickets into Cloud Firestore. Tickets range from 1 to 20,000. Book ID is automatically calculated.",
                              style: TextStyle(
                                color: Colors.teal.shade100,
                                fontSize: isMobile ? 12 : 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Forms Layout
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _buildManualFormCard(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualFormCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1, color: Color(0xFF0277BD)),
                  const SizedBox(width: 10),
                  const Text(
                    "Manual Single Registration",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Ticket Number field
              const Text(
                "Ticket Number(s) (1 - 20000, comma-separated)",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _ticketController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  hintText: "e.g. 1542, 1545, 1600",
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Ticket number(s) required";
                  }
                  final tickets = _parseTicketNumbers(value);
                  if (tickets.isEmpty) {
                    return "Please enter valid ticket number(s) or range (e.g. A2001-A2010)";
                  }
                  for (final num in tickets) {
                    if (num < 1 || num > 20000) {
                      return "Ticket numbers must be between 1 and 20,000 (invalid: #$num)";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Buyer Name field
              const Text(
                "Buyer's Full Name",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: "Enter buyer's name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Buyer name is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Buyer Phone field
              const Text(
                "Buyer's Phone Number",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: "Enter 10-digit phone number",
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Phone number is required";
                  }
                  if (value.trim().length < 8) {
                    return "Enter a valid phone number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSavingSingle ? null : _saveSingleTicket,
                  icon: _isSavingSingle
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text(
                    "REGISTER TICKET",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


}

List<int> _parseTicketNumbers(String input) {
  final List<int> results = [];
  final parts = input.split(',');
  for (var part in parts) {
    part = part.trim().toUpperCase();
    if (part.isEmpty) continue;

    // Matches ranges like A0001-A0010, B0001-B0010, A0001 to A0010, or 0001-0010
    final rangeMatch = RegExp(r'^([A-B]?)(\d+)\s*(?:-|to)\s*([A-B]?)(\d+)$').firstMatch(part);
    if (rangeMatch != null) {
      final startPrefix = rangeMatch.group(1) ?? '';
      final startNum = int.tryParse(rangeMatch.group(2)!) ?? 0;
      final endPrefix = rangeMatch.group(3) ?? '';
      final endNum = int.tryParse(rangeMatch.group(4)!) ?? 0;

      final effectiveStartPrefix = startPrefix.isNotEmpty ? startPrefix : 'A';
      final effectiveEndPrefix = endPrefix.isNotEmpty ? endPrefix : effectiveStartPrefix;

      if (effectiveStartPrefix == effectiveEndPrefix) {
        final int offset = (effectiveStartPrefix == 'B') ? 10000 : 0;
        if (startNum > 0 && endNum >= startNum) {
          for (int i = startNum; i <= endNum; i++) {
            if (i >= 1 && i <= 10000) {
              results.add(offset + i);
            }
          }
        }
      }
    } else {
      final numberMatch = RegExp(r'^([A-B]?)(\d+)$').firstMatch(part);
      if (numberMatch != null) {
        final prefix = numberMatch.group(1) ?? '';
        final numVal = int.tryParse(numberMatch.group(2)!) ?? 0;
        final effectivePrefix = prefix.isNotEmpty ? prefix : 'A';
        final int offset = (effectivePrefix == 'B') ? 10000 : 0;
        if (numVal >= 1 && numVal <= 10000) {
          results.add(offset + numVal);
        }
      }
    }
  }
  return results.toSet().toList();
}
