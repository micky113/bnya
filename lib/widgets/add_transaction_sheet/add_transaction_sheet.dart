import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _sbiController = TextEditingController();
  final TextEditingController _hdfcController = TextEditingController();

  // State
  String _type = 'income'; // 'income' or 'expenditure'
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    double cash = double.tryParse(_cashController.text) ?? 0;
    double sbi = double.tryParse(_sbiController.text) ?? 0;
    double hdfc = double.tryParse(_hdfcController.text) ?? 0;

    if (cash == 0 && sbi == 0 && hdfc == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter at least one amount (Cash/Bank).")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final transactionData = {
        'type': _type, 
        'date': Timestamp.fromDate(_selectedDate),
        
        // UPDATED LOGIC: Save voucher for BOTH Income and Expenditure
        'voucher': _voucherController.text.trim().isNotEmpty 
            ? _voucherController.text.trim() 
            : (_type == 'income' ? 'Income' : 'Expense'), // Default fallback

        'cash': cash,
        'bankSbi': sbi,
        'bankHdfc': hdfc,
        
        // Auto-generate ID based on time
        'sheetRowId': DateTime.now().millisecondsSinceEpoch, 
        
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('ledger').add(transactionData);

      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Entry Saved!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine colors based on type
    final isIncome = _type == 'income';
    final themeColor = isIncome ? Colors.green : Colors.red;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, 
        right: 20, 
        top: 20
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Container(
                  width: 50, height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              Text("New Transaction", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900])),
              
              const SizedBox(height: 20),

              // 1. TYPE TOGGLE
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildTypeButton("Income", 'income', Colors.green),
                    _buildTypeButton("Expense", 'expenditure', Colors.red),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. DATE PICKER
              InkWell(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 16)),
                      const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. VOUCHER / DESCRIPTION FIELD (NOW VISIBLE FOR BOTH)
              TextFormField(
                controller: _voucherController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: isIncome ? "Payer Name / Description" : "Voucher / Purpose",
                  prefixIcon: Icon(Icons.description, color: themeColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (val) {
                  // Optional: Make it required if you want
                  if (val == null || val.isEmpty) return "Please enter a description";
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 4. AMOUNT FIELDS
              const Text("Amounts (Enter at least one)", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              
              Row(
                children: [
                  Expanded(child: _buildAmountField(_cashController, "Cash", Colors.orange)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildAmountField(_sbiController, "SBI", Colors.blue)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildAmountField(_hdfcController, "HDFC", Colors.indigo)),
                ],
              ),
              
              const SizedBox(height: 30),

              // 5. SUBMIT BUTTON
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitTransaction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("SAVE ENTRY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeButton(String label, String value, Color color) {
    bool isSelected = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)] : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? color : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountField(TextEditingController controller, String label, Color color) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color.withOpacity(0.3))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }
}