import 'package:bnya/data/models/collection_service/collection_service.dart';
import 'package:bnya/data/models/contributor/contributor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter

class PaymentEntryDialog extends StatefulWidget {
  final Contributor contributor;
  final String adminName;

  const PaymentEntryDialog({
    super.key,
    required this.contributor,
    required this.adminName,
  });

  @override
  State<PaymentEntryDialog> createState() => _PaymentEntryDialogState();
}

class _PaymentEntryDialogState extends State<PaymentEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  late TextEditingController _collectorController;

  // Default to current year
  String _selectedYear = DateTime.now().year.toString();
  bool _isLoading = false;

  // Instance of our backend service
  final CollectionService _collectionService = CollectionService();

  @override
  void initState() {
    super.initState();
    _collectorController = TextEditingController(text: widget.adminName);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _collectorController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        double amount = double.parse(_amountController.text);

        await _collectionService.recordPayment(
          contributorId: widget.contributor.id,
          contributorName: widget.contributor.name,
          amountCollected: amount,
          year: _selectedYear,
          collectedBy: widget.adminName, // NEW
        );

        if (mounted) {
          Navigator.of(context).pop(); // Close dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Success! Added ₹$amount to ${widget.contributor.name}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Current year for dropdown logic
    int currentYear = DateTime.now().year;
    List<String> yearOptions = [
      (currentYear - 2).toString(),
      (currentYear - 1).toString(),
      currentYear.toString(),
      (currentYear + 1).toString(),
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400, // Fixed width for Web aesthetics
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Add Payment",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Contributor Info Badge
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.contributor.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "ID: ${widget.contributor.id} • ${widget.contributor.type.toUpperCase()}",
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Amount Field
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  labelText: "Amount Received",
                  prefixText: "₹ ",
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Please enter amount';
                  if (double.tryParse(value) == 0)
                    return 'Amount cannot be zero';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Year Dropdown
              DropdownButtonFormField<String>(
                value: _selectedYear,
                decoration: const InputDecoration(
                  labelText: "For Year",
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                items:
                    yearOptions.map((String year) {
                      return DropdownMenuItem<String>(
                        value: year,
                        child: Text(year),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedYear = newValue!;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Collector details
              TextFormField(
                controller: _collectorController,
                decoration: const InputDecoration(
                  labelText: "Collector Name",
                  hintText: "Who is receiving the money?",
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty)
                            ? 'Enter collector name'
                            : null,
              ),

              const SizedBox(height: 24),
              // Action Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            "CONFIRM PAYMENT",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
