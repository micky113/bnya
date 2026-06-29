import 'dart:typed_data'; // Required for Uint8List
import 'package:bnya/data/models/contributor/contributor.dart';
import 'package:bnya/view/lottery/ticket_model.dart';
import 'package:bnya/services/auth_service.dart';
import 'package:bnya/view/contributor_map_screen/contributor_map_screen.dart' hide AddContributorDialog;
import 'package:bnya/widgets/add_contributor_dialog/add_contributor_dialog.dart';
import 'package:bnya/widgets/edit_contributor_dialog/edit_contributor_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ContributorDirectoryScreen extends StatefulWidget {
  const ContributorDirectoryScreen({super.key});

  @override
  State<ContributorDirectoryScreen> createState() =>
      _ContributorDirectoryScreenState();
}

class _ContributorDirectoryScreenState
    extends State<ContributorDirectoryScreen> {
  final NumberFormat _currency = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 0,
    locale: 'en_IN',
  );
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final List<String> _paymentTypes = [
    'Kalash',
    'Coupon',
    'Cheque',
    'Others',
  ];

  // --- FILTER STATE ---
  String _selectedFilter = 'All';
  final List<String> _filterOptions = [
    'All',
    'Resident',
    'Shop',
    'Business',
    'Donor',
  ];

  // Auth & Security
  final AuthService _authService = AuthService();
  final List<String> _adminEmails = [
    "mohanty747@gmail.com",
    "treasurer@society.com",
    "utkalspace@gmail.com",
    "mishra.debidatta@gmail.com",
  ];

  // Search State
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- IMPORT FUNCTION ---
  Future<void> _importKalashData() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Reading Excel file...")));

    try {
      Uint8List? fileBytes = result.files.single.bytes;
      if (fileBytes == null) throw "Could not read file data.";

      var decoder = SpreadsheetDecoder.decodeBytes(fileBytes);
      var table = decoder.tables['Sheet1'];
      if (table == null) {
        if (decoder.tables.isNotEmpty) {
          table = decoder.tables.values.first;
        } else {
          throw "Sheet1 not found";
        }
      }

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      String? currentDocId;
      String? currentName;

      for (int i = 11; i <= 110; i++) {
        if (i >= table.maxRows) break;
        var row = table.rows[i];

        var cellSlNo = row.length > 6 ? row[6] : null;
        var cellName = row.length > 7 ? row[7] : null;
        var cellAmount = row.length > 8 ? row[8] : null;

        String slNo = cellSlNo?.toString().trim() ?? "";
        String name = cellName?.toString().trim() ?? "";
        double amount =
            double.tryParse(cellAmount?.toString().replaceAll(',', '') ?? "") ??
            0.0;

        if (slNo.isEmpty && name.isEmpty && amount == 0) continue;

        if (name.isNotEmpty) {
          currentName = name;
          currentDocId = slNo.isNotEmpty ? "KALASH-$slNo" : "KALASH-REF-$i";

          var payment = {
            'id':
                DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
            'amount': amount,
            'date': Timestamp.fromDate(DateTime.now()),
            'type': 'Kalash',
            'referenceId': slNo,
            'remarks': 'Imported from Sheet1',
            'imageUrl': null,
          };

          DocumentReference docRef = FirebaseFirestore.instance
              .collection('contributors')
              .doc(currentDocId);

          batch.set(docRef, {
            'id': currentDocId,
            'name': currentName,
            'type': 'resident',
            'targetAmount': 501.0,
            'contactNumber': '',
            'address': '',
            'imageUrl': null,
            'yearlyPayments': {},
            'paymentHistory': FieldValue.arrayUnion([payment]),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          count++;
        } else if (name.isEmpty && amount > 0 && currentDocId != null) {
          var payment = {
            'id':
                DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
            'amount': amount,
            'date': Timestamp.fromDate(DateTime.now()),
            'type': 'Kalash',
            'referenceId': '',
            'remarks': 'Extra payment row',
            'imageUrl': null,
          };
          DocumentReference docRef = FirebaseFirestore.instance
              .collection('contributors')
              .doc(currentDocId);
          batch.update(docRef, {
            'paymentHistory': FieldValue.arrayUnion([payment]),
          });
          count++;
        }
      }
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Imported $count entries successfully!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Import Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- SECURE DELETE LOGIC ---
  Future<void> _handleDelete(
    BuildContext context,
    Contributor contributor,
  ) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await _authService.signInWithGoogle();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Auth Error: $e")));
        return;
      }
    }
    if (user != null && _adminEmails.contains(user.email)) {
      if (mounted) _confirmDelete(context, contributor);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Access Denied."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, Contributor contributor) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Delete Contributor"),
            content: Text("Delete ${contributor.name}?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('contributors')
                      .doc(contributor.id)
                      .delete();
                  if (mounted) Navigator.pop(context);
                },
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  // --- VIEW IMAGE DIALOG ---
  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(12),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (ctx, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder:
                            (context, error, stackTrace) => const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.white,
                                size: 50,
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 18,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title:
            _isSearching
                ? TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    hintText: "Search...",
                    hintStyle: TextStyle(color: Colors.black54),
                    border: InputBorder.none,
                  ),
                  onChanged:
                      (val) => setState(() => _searchQuery = val.toLowerCase()),
                )
                : const Text("Contributor Directory"),
        backgroundColor: _isSearching ? Colors.white : Colors.blue[900],
        foregroundColor: _isSearching ? Colors.black : Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: "View Map",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ContributorMapScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed:
                () => setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = "";
                    _searchController.clear();
                  }
                }),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _importKalashData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            () => showDialog(
              context: context,
              builder: (_) => const AddContributorDialog(),
            ),
        backgroundColor: Colors.blue[900],
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text("Add Payee", style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance.collection('contributors').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          var docs =
              snapshot.data!.docs
                  .map((d) => Contributor.fromFirestore(d))
                  .where((c) => c.type.toLowerCase() != 'lottery_buyer')
                  .toList();

          if (_searchQuery.isNotEmpty) {
            docs =
                docs.where((c) {
                  return c.name.toLowerCase().contains(_searchQuery) ||
                      c.id.toLowerCase().contains(_searchQuery);
                }).toList();
          }

          if (_selectedFilter != 'All') {
            docs =
                docs
                    .where(
                      (c) =>
                          c.type.toLowerCase() == _selectedFilter.toLowerCase(),
                    )
                    .toList();
          }

          double grandTotal = 0;
          int currentYear = DateTime.now().year;
          for (var c in docs) grandTotal += c.getYearTotal(currentYear);

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filterOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final type = _filterOptions[index];
                    final isSelected = _selectedFilter == type;
                    return ChoiceChip(
                      label: Text(type),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = type;
                        });
                      },
                      selectedColor: Colors.blue[100],
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.blue[900] : Colors.black87,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: Colors.grey[100],
                      side:
                          isSelected
                              ? BorderSide.none
                              : BorderSide(color: Colors.grey.shade300),
                    );
                  },
                ),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20, top: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final contributor = docs[index];
                    double totalPaid = contributor.getYearTotal(currentYear);
                    double target = contributor.targetAmount;
                    double remaining = target - totalPaid;
                    double progress =
                        target > 0 ? (totalPaid / target).clamp(0.0, 1.0) : 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: Text(
                            contributor.name.isNotEmpty
                                ? contributor.name[0]
                                : '?',
                            style: TextStyle(
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "${contributor.name} (${contributor.id})",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_selectedFilter == 'All')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  contributor.type.toUpperCase(),
                                  style: const TextStyle(fontSize: 8),
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.blue,
                            size: 32,
                          ),
                          onPressed:
                              () => _showAddPaymentDialog(context, contributor),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (target > 0) ...[
                              LinearProgressIndicator(
                                value: progress,
                                color:
                                    remaining <= 0
                                        ? Colors.green
                                        : Colors.orange,
                              ),
                              Text(
                                "Paid: ${_currency.format(totalPaid)} | Due: ${_currency.format(remaining)}",
                                style: const TextStyle(fontSize: 11),
                              ),
                            ] else
                              Text(
                                "Paid: ${_currency.format(totalPaid)}",
                                style: const TextStyle(color: Colors.green),
                              ),
                          ],
                        ),
                        children: [
                          // --- PAYMENT HISTORY ---
                          if (contributor.paymentHistory.isNotEmpty)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: contributor.paymentHistory.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final payment = contributor.paymentHistory[i];
                                String subText = _dateFormat.format(
                                  payment.date,
                                );
                                if (payment.referenceId.isNotEmpty) {
                                  subText += "\nRef: ${payment.referenceId}";
                                }
                                if (payment.remarks.isNotEmpty) {
                                  final parsedTickets = _parseTicketNumbers(
                                    payment.remarks,
                                  );
                                  if (parsedTickets.isNotEmpty) {
                                    subText +=
                                        "\nTickets: ${parsedTickets.map((t) => '#${Ticket.formatNumber(t)}').join(', ')}";
                                  } else {
                                    subText += "\nRemarks: ${payment.remarks}";
                                  }
                                }

                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.history,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  title: Text(
                                    _currency.format(payment.amount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    subText,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (payment.imageUrl != null &&
                                          payment.imageUrl!.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.image,
                                            color: Colors.blue,
                                          ),
                                          onPressed:
                                              () => _showImageDialog(
                                                payment.imageUrl!,
                                              ),
                                          tooltip: "View Receipt",
                                        ),
                                      _buildPaymentTypeChip(payment.type),
                                    ],
                                  ),
                                );
                              },
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text("No current history records found."),
                            ),

                          // --- NEW: YEARLY PAYMENTS (PAST RECORDS) ---
                          if (contributor.yearlyPayments.isNotEmpty) ...[
                            const Divider(thickness: 1, height: 24),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color: Colors.grey[50],
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "PAST YEAR RECORDS",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children:
                                        contributor.yearlyPayments.entries.map((
                                          e,
                                        ) {
                                          return Chip(
                                            label: Text(
                                              "${e.key}: ${_currency.format(e.value)}",
                                            ),
                                            backgroundColor: Colors.white,
                                            side: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                            labelStyle: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          );
                                        }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blue[900],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Collection:",
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    Text(
                      _currency.format(grandTotal),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaymentTypeChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(type, style: const TextStyle(fontSize: 10)),
    );
  }

  // --- ADD PAYMENT DIALOG ---
  void _showAddPaymentDialog(BuildContext context, Contributor contributor) {
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final ticketsController = TextEditingController();
    String selectedType = 'Kalash';
    bool isLoading = false;

    Uint8List? _selectedImageBytes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            bool showRefField = (selectedType != 'Kalash');

            Future<void> _pickImage(ImageSource source) async {
              final picker = ImagePicker();
              final XFile? pickedFile = await picker.pickImage(
                source: source,
                imageQuality: 50,
              );
              if (pickedFile != null) {
                final bytes = await pickedFile.readAsBytes();
                setSheetState(() {
                  _selectedImageBytes = bytes;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Add Payment",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Enter Amount",
                        prefixText: "₹ ",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      children:
                          _paymentTypes
                              .map(
                                (type) => ChoiceChip(
                                  label: Text(type),
                                  selected: selectedType == type,
                                  onSelected:
                                      (val) => setSheetState(
                                        () => selectedType = type,
                                      ),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ticketsController,
                      decoration: const InputDecoration(
                        labelText: 'Lottery Ticket Numbers(eg: A2001-A2100)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (showRefField) ...[
                      const SizedBox(height: 20),
                      TextField(
                        controller: referenceController,
                        decoration: InputDecoration(
                          labelText: selectedType == 'Coupon'
                              ? 'Coupon No'
                              : selectedType == 'Cheque'
                                  ? 'Cheque No'
                                  : 'UTR No',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text("Take Photo"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text("Gallery"),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedImageBytes != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Stack(
                            children: [
                              Image.memory(
                                _selectedImageBytes!,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                right: 0,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => setSheetState(
                                    () => _selectedImageBytes = null,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed:
                            isLoading
                                ? null
                                : () async {
                                  final amount = double.tryParse(
                                    amountController.text,
                                  );
                                  if (amount == null || amount <= 0) return;

                                  setSheetState(() => isLoading = true);

                                  String? uploadedImageUrl;

                                  if (_selectedImageBytes != null) {
                                    try {
                                      String fileName =
                                          "${DateTime.now().millisecondsSinceEpoch}.jpg";
                                      Reference storageRef = FirebaseStorage
                                          .instance
                                          .ref()
                                          .child('payment_proofs')
                                          .child(contributor.id)
                                          .child(fileName);

                                      await storageRef.putData(
                                        _selectedImageBytes!,
                                        SettableMetadata(
                                          contentType: 'image/jpeg',
                                        ),
                                      );

                                      uploadedImageUrl =
                                          await storageRef.getDownloadURL();
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Image Upload Failed: $e",
                                            ),
                                          ),
                                        );
                                      }
                                      setSheetState(() => isLoading = false);
                                      return;
                                    }
                                  }

                                  final newPayment = PaymentRecord(
                                    id:
                                        DateTime.now().millisecondsSinceEpoch
                                            .toString(),
                                    amount: amount,
                                    date: DateTime.now(),
                                    type: selectedType,
                                    referenceId:
                                        referenceController.text.trim(),
                                    remarks: ticketsController.text.trim(),
                                    imageUrl: uploadedImageUrl,
                                  );

                                  final updatedHistory =
                                      [
                                        ...contributor.paymentHistory,
                                        newPayment,
                                      ].map((e) => e.toMap()).toList();

                                  final firestore = FirebaseFirestore.instance;

                                  // Parse and validate tickets for duplicates
                                  final List<int> tickets = _parseTicketNumbers(ticketsController.text);
                                  if (tickets.isNotEmpty) {
                                    final List<DocumentSnapshot> snaps = await Future.wait(
                                      tickets.map((t) => firestore.collection('tickets').doc(t.toString()).get())
                                    );
                                    final List<int> duplicateTickets = [];
                                    for (final snap in snaps) {
                                      if (snap.exists) {
                                        final int? existingNum = int.tryParse(snap.id);
                                        if (existingNum != null) {
                                          duplicateTickets.add(existingNum);
                                        }
                                      }
                                    }
                                    if (duplicateTickets.isNotEmpty) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("Error: Ticket(s) #${duplicateTickets.join(', ')} already registered!"),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                      setSheetState(() => isLoading = false);
                                      return;
                                    }
                                  }

                                  final batch = firestore.batch();

                                  final contributorRef = firestore.collection('contributors').doc(contributor.id);
                                  batch.update(contributorRef, {
                                    'paymentHistory': updatedHistory,
                                  });

                                  final ledgerRef = firestore.collection('ledger').doc();
                                  batch.set(ledgerRef, {
                                    'type': 'income',
                                    'date': Timestamp.now(),
                                    'voucher': 'Collection: ${contributor.name} (${contributor.id})',
                                    'cash': amount,
                                    'bankSbi': 0.0,
                                    'bankHdfc': 0.0,
                                    'sheetRowId': DateTime.now().millisecondsSinceEpoch,
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });

                                  // Register the tickets in Firestore
                                  for (final tNum in tickets) {
                                    final int bookId = ((tNum - 1) ~/ 100) + 1;
                                    final ticketRef = firestore.collection('tickets').doc(tNum.toString());
                                    batch.set(ticketRef, {
                                      'ticketNumber': tNum,
                                      'bookId': bookId,
                                      'buyerName': contributor.name,
                                      'buyerPhone': contributor.contactNumber,
                                      'isSold': true,
                                      'hasWonConsolation': false,
                                      'hasWonGrandPrize': false,
                                    }, SetOptions(merge: true));
                                  }

                                  await batch.commit();

                                  if (mounted) Navigator.pop(context);
                                },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[900],
                        ),
                        child:
                            isLoading
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : const Text(
                                  "CONFIRM PAYMENT",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
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
