import 'dart:io';
import 'package:bnya/data/models/ledger_model/ledger_model.dart';
import 'package:bnya/widgets/add_transaction_sheet/add_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart'; // Import File Picker
import 'package:excel/excel.dart' hide Border; // Import Excel

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currency = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 0,
    locale: 'en_IN',
  );
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final TextEditingController _searchController = TextEditingController();

  // --- FILTER STATE ---
  String _currentFilter = 'All';
  bool _isSearching = false;
  String _searchQuery = "";

  int? _selectedYear;
  int? _selectedMonth;

  final List<int> _years = List.generate(10, (index) => 2024 + index);
  final List<String> _months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- 1. NEW: BULK UPLOAD FUNCTION ---
  Future<void> _importExcelData() async {
    try {
      // A. Pick File
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) return; // User canceled

      // Show Loading
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Processing Excel file..."),
          duration: Duration(seconds: 2),
        ),
      );

      // B. Decode Excel
      var fileBytes = File(result.files.single.path!).readAsBytesSync();
      var excel = Excel.decodeBytes(fileBytes);

      // C. Find "Sheet3" (or use the first sheet if unsure)
      // Note: Excel package keys might be "Sheet3" or just "Sheet 3" depending on the file
      var table = excel.tables['Sheet3'];
      if (table == null) {
        // Fallback: Try to find a sheet with "Collection" in it or just take the 3rd one
        if (excel.tables.length >= 3) {
          table = excel.tables.values.elementAt(2); // 0-indexed, so 2 is 3rd
        } else {
          throw "Sheet3 not found!";
        }
      }

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      DateTime lastValidDate = DateTime(2025, 4, 1); // Default start date

      // D. Iterate Rows (Skip first 3 headers)
      // We assume the structure:
      // Col 1 (B): Income Desc | Col 2 (C): Inc Cash | Col 3 (D): Inc Bank
      // Col 5 (F): Exp Date    | Col 6 (G): Voucher  | Col 7 (H): Exp Desc | Col 10 (K): Exp Cash | Col 11 (L): Exp Bank

      for (var i = 3; i < table.maxRows; i++) {
        var row = table.rows[i];
        if (row.isEmpty) continue;

        // Helper to safely get cell value
        dynamic getVal(int colIndex) {
          if (colIndex >= row.length) return null;
          return row[colIndex]?.value;
        }

        // --- 1. PARSE INCOME SIDE ---
        String incDesc = getVal(1)?.toString() ?? "";
        // Clean amounts (remove commas/strings)
        double incCash =
            double.tryParse(getVal(2)?.toString().replaceAll(',', '') ?? "") ??
            0;
        double incBank =
            double.tryParse(getVal(3)?.toString().replaceAll(',', '') ?? "") ??
            0;

        if (incDesc.isNotEmpty && !incDesc.toLowerCase().contains("total")) {
          DocumentReference docRef =
              FirebaseFirestore.instance.collection('ledger').doc();
          batch.set(docRef, {
            'type': 'income',
            'date': Timestamp.fromDate(
              DateTime(2025, 4, 1),
            ), // Default Opening Balance Date
            'voucher': 'Income', // Default
            'description': incDesc,
            'cash': incCash,
            'bankSbi': 0.0,
            'bankHdfc': incBank, // Assuming bank col is HDFC or generic
            'sheetRowId': i,
            'createdAt': FieldValue.serverTimestamp(),
          });
          count++;
        }

        // --- 2. PARSE EXPENDITURE SIDE ---
        // Date Logic
        var dateVal = getVal(5);
        if (dateVal != null) {
          if (dateVal is int) {
            // Excel date serial
            lastValidDate = DateTime(
              1900,
              1,
              1,
            ).add(Duration(days: dateVal - 2));
          } else if (dateVal is String) {
            try {
              lastValidDate = DateFormat('yyyy-MM-dd').parse(dateVal);
            } catch (e) {
              // Keep previous date if parse fails
            }
          }
        }

        String expVoucher = getVal(6)?.toString() ?? "";
        String expDesc = getVal(7)?.toString() ?? "";
        double expCash =
            double.tryParse(getVal(10)?.toString().replaceAll(',', '') ?? "") ??
            0;
        double expBank =
            double.tryParse(getVal(11)?.toString().replaceAll(',', '') ?? "") ??
            0;

        if (expDesc.isNotEmpty && !expDesc.toLowerCase().contains("total")) {
          DocumentReference docRef =
              FirebaseFirestore.instance.collection('ledger').doc();
          batch.set(docRef, {
            'type': 'expenditure',
            'date': Timestamp.fromDate(lastValidDate),
            'voucher': expVoucher,
            'description': expDesc,
            'cash': expCash,
            'bankSbi': expBank, // Assuming first bank col is SBI? Or generic.
            'bankHdfc': 0.0,
            'sheetRowId': i,
            'createdAt': FieldValue.serverTimestamp(),
          });
          count++;
        }
      }

      // E. Commit
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully imported $count entries!"),
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

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Financial Ledger"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // --- 2. UPLOAD BUTTON RESTORED ---
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: "Import from Excel",
            onPressed: _importExcelData,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [Tab(text: "TRANSACTIONS"), Tab(text: "SUMMARY")],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEntrySheet(context),
        backgroundColor: Colors.blue[900],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("New Entry", style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('ledger')
                .orderBy('date', descending: true)
                .orderBy('sheetRowId', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          var allDocs =
              snapshot.data!.docs
                  .map((d) => LedgerEntry.fromFirestore(d))
                  .toList();

          double balCash = 0, balSbi = 0, balHdfc = 0;
          double inCash = 0, inSbi = 0, inHdfc = 0;
          double outCash = 0, outSbi = 0, outHdfc = 0;

          for (var e in allDocs) {
            bool isIncome = e.type == 'income';
            if (isIncome) {
              balCash += e.cash;
              balSbi += e.bankSbi;
              balHdfc += e.bankHdfc;
              inCash += e.cash;
              inSbi += e.bankSbi;
              inHdfc += e.bankHdfc;
            } else {
              balCash -= e.cash;
              balSbi -= e.bankSbi;
              balHdfc -= e.bankHdfc;
              outCash += e.cash;
              outSbi += e.bankSbi;
              outHdfc += e.bankHdfc;
            }
          }

          // Apply Filters
          List<LedgerEntry> filteredDocs = allDocs;

          if (_currentFilter == 'Income') {
            filteredDocs =
                filteredDocs.where((e) => e.type == 'income').toList();
          } else if (_currentFilter == 'Expense') {
            filteredDocs =
                filteredDocs.where((e) => e.type == 'expenditure').toList();
          }

          if (_selectedYear != null) {
            filteredDocs =
                filteredDocs
                    .where((e) => e.date.year == _selectedYear)
                    .toList();
          }
          if (_selectedMonth != null) {
            filteredDocs =
                filteredDocs
                    .where((e) => e.date.month == _selectedMonth)
                    .toList();
          }

          if (_searchQuery.isNotEmpty) {
            filteredDocs =
                filteredDocs.where((e) {
                  final voucher = e.voucher?.toLowerCase() ?? "";
                  return voucher.contains(_searchQuery.toLowerCase());
                }).toList();
          }

          double viewTotal = filteredDocs.fold(
            0,
            (sum, item) => sum + item.total,
          );

          return TabBarView(
            controller: _tabController,
            children: [
              // TAB 1
              Column(
                children: [
                  _buildBalanceHeader(balCash, balSbi, balHdfc),

                  Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child:
                              _isSearching
                                  ? _buildSearchBar()
                                  : _buildFilterRow(),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              _buildDropdown("Year", _selectedYear, _years, (
                                val,
                              ) {
                                setState(() => _selectedYear = val);
                              }),
                              const SizedBox(width: 12),
                              _buildDropdown(
                                "Month",
                                _selectedMonth,
                                List.generate(12, (i) => i + 1),
                                (val) {
                                  setState(() => _selectedMonth = val);
                                },
                                itemsLabels: _months,
                              ),
                              const Spacer(),
                              if (_selectedYear != null ||
                                  _selectedMonth != null)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedYear = null;
                                      _selectedMonth = null;
                                    });
                                  },
                                  child: const Text(
                                    "Clear Date",
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  Expanded(
                    child:
                        filteredDocs.isEmpty
                            ? Center(
                              child: Text(
                                "No entries found",
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                            : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                80,
                              ),
                              itemCount: filteredDocs.length,
                              separatorBuilder:
                                  (ctx, i) => const Divider(height: 1),
                              itemBuilder:
                                  (context, index) => _buildTransactionTile(
                                    filteredDocs[index],
                                  ),
                            ),
                  ),

                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 100, 16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      border: Border(
                        top: BorderSide(color: Colors.blue.withOpacity(0.2)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          "Total View",
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: w / 6),
                        Text(
                          _currency.format(viewTotal),
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // TAB 2
              _buildSummaryTab(inCash, inSbi, inHdfc, outCash, outSbi, outHdfc),
            ],
          );
        },
      ),
    );
  }

  // --- WIDGETS ---
  // (Keep all your existing helper widgets like _buildDropdown, _buildSearchBar, _buildFilterRow, etc.)
  // Just copying the crucial ones below for completeness of the structure:

  Widget _buildDropdown<T>(
    String hint,
    T? value,
    List<T> items,
    ValueChanged<T?> onChanged, {
    List<String>? itemsLabels,
  }) {
    return DropdownButton<T>(
      value: value,
      hint: Text(
        hint,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
      underline: const SizedBox(),
      icon: const Icon(Icons.arrow_drop_down, size: 18),
      isDense: true,
      items:
          items.asMap().entries.map((entry) {
            int idx = entry.key;
            T item = entry.value;
            String label =
                itemsLabels != null ? itemsLabels[idx] : item.toString();
            return DropdownMenuItem<T>(
              value: item,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildFilterRow() {
    return Row(
      children: [
        _buildFilterChip('All'),
        const SizedBox(width: 8),
        _buildFilterChip('Income'),
        const SizedBox(width: 8),
        _buildFilterChip('Expense'),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.search, color: Colors.black54),
          onPressed: () => setState(() => _isSearching = true),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        const Icon(Icons.search, color: Colors.black54),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Search voucher...",
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.black54),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchQuery = "";
              _searchController.clear();
            });
          },
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = _currentFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) setState(() => _currentFilter = label);
      },
      selectedColor: Colors.blue[100],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[900] : Colors.black54,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  // (Include _buildBalanceHeader, _buildBalanceCard, _buildTransactionTile, _buildModeBadge, _buildSummaryTab, _buildAbstractSection, _buildAbstractRow, _showAddEntrySheet from previous code)

  Widget _buildBalanceHeader(double cash, double sbi, double hdfc) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.blue[900],
      child: Row(
        children: [
          Expanded(
            child: _buildBalanceCard("CASH", cash, Colors.orange, Icons.money),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildBalanceCard(
              "SBI",
              sbi,
              Colors.blue,
              Icons.account_balance,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildBalanceCard(
              "HDFC",
              hdfc,
              Colors.indigo,
              Icons.apartment,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(
    String label,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color.withOpacity(0.8), size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _currency.format(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(LedgerEntry entry) {
    bool isIncome = entry.type == 'income';
    String title = isIncome ? "INCOME" : "EXPENSE";
    if (entry.voucher != null && entry.voucher!.isNotEmpty)
      title = entry.voucher!;

    return ListTile(
      tileColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: isIncome ? Colors.green[50] : Colors.red[50],
        child: Icon(
          isIncome ? Icons.arrow_downward : Icons.arrow_upward,
          color: isIncome ? Colors.green : Colors.red,
          size: 20,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        _dateFormat.format(entry.date),
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            "${isIncome ? '+' : '-'} ${_currency.format(entry.total)}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.green[800] : Colors.red[800],
              fontSize: 15,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.cash > 0) _buildModeBadge("CASH", Colors.orange),
              if (entry.bankSbi > 0) _buildModeBadge("SBI", Colors.blue),
              if (entry.bankHdfc > 0) _buildModeBadge("HDFC", Colors.indigo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSummaryTab(
    double inC,
    double inS,
    double inH,
    double outC,
    double outS,
    double outH,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildAbstractSection("INCOME", inC, inS, inH, Colors.green),
        const SizedBox(height: 20),
        _buildAbstractSection("EXPENDITURE", outC, outS, outH, Colors.red),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildAbstractSection(
    String title,
    double c,
    double s,
    double h,
    MaterialColor color,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color[800],
            ),
          ),
          const Divider(),
          _buildAbstractRow("Cash", c),
          _buildAbstractRow("SBI Bank", s),
          _buildAbstractRow("HDFC Bank", h),
          const Divider(),
          _buildAbstractRow("TOTAL", c + s + h, isBold: true),
        ],
      ),
    );
  }

  Widget _buildAbstractRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            _currency.format(amount),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddEntrySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const AddTransactionSheet(),
    );
  }
}
