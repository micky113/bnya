import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class AddContributorDialog extends StatefulWidget {
  const AddContributorDialog({super.key});

  @override
  State<AddContributorDialog> createState() => _AddContributorDialogState();
}

class _AddContributorDialogState extends State<AddContributorDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _targetController = TextEditingController(); 
  
  // NEW: Previous Years Controllers
  final _prevYear1Controller = TextEditingController(); // e.g. 2024
  final _prevYear2Controller = TextEditingController(); // e.g. 2023

  // State
  String _selectedType = 'resident';
  bool _isLoading = false;

  // Image State
  Uint8List? _imageBytes; 
  XFile? _pickedFile; 

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _targetController.dispose();
    _prevYear1Controller.dispose();
    _prevYear2Controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);

    if (image != null) {
      final Uint8List bytes = await image.readAsBytes();
      setState(() {
        _pickedFile = image;
        _imageBytes = bytes;
      });
    }
  }

  Future<String?> _uploadImage(String docId) async {
    if (_imageBytes == null) return null;
    try {
      final storageRef = FirebaseStorage.instance.ref().child('contributors_images').child('$docId.jpg');
      final uploadTask = storageRef.putData(_imageBytes!);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Image Upload Error: $e");
      return null;
    }
  }

  Future<void> _saveContributor() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final String docId = _idController.text.trim().toUpperCase();

        // 1. Check Duplicates
        final docRef = FirebaseFirestore.instance.collection('contributors').doc(docId);
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: ID already exists!')));
          setState(() => _isLoading = false);
          return;
        }

        // 2. Upload Image
        String? imageUrl;
        if (_imageBytes != null) {
          imageUrl = await _uploadImage(docId);
        }

        // 3. Prepare Yearly Payments Map
        // Calculate years dynamically or hardcode based on your "2025 Drive" context
        int currentYear = DateTime.now().year; 
        String year1 = (currentYear - 1).toString(); // 2024
        String year2 = (currentYear - 2).toString(); // 2023

        Map<String, double> pastPayments = {};
        
        double val1 = double.tryParse(_prevYear1Controller.text) ?? 0;
        if (val1 > 0) pastPayments[year1] = val1;

        double val2 = double.tryParse(_prevYear2Controller.text) ?? 0;
        if (val2 > 0) pastPayments[year2] = val2;

        // 4. Save to Firestore
        await docRef.set({
          'id': docId,
          'name': _nameController.text.trim(),
          'type': _selectedType,
          'contactNumber': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'imageUrl': imageUrl,
          
          'targetAmount': double.tryParse(_targetController.text) ?? 0.0,
          'paymentHistory': [], // Empty list for new detailed payments
          'yearlyPayments': pastPayments, // Populate with the past data we just collected
          
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contributor Added!'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int currentYear = DateTime.now().year;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("New Contributor", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),

                // Image Picker
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _imageBytes != null ? MemoryImage(_imageBytes!) : null,
                      child: _imageBytes == null ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey) : null,
                    ),
                  ),
                ),
                const Center(child: Padding(padding: EdgeInsets.only(top: 8), child: Text("Tap to add photo", style: TextStyle(fontSize: 12, color: Colors.grey)))),
                const SizedBox(height: 20),

                // Basic Info
                TextFormField(
                  controller: _idController,
                  decoration: const InputDecoration(labelText: "Unique ID (e.g. SHOP-01)", border: OutlineInputBorder(), filled: true),
                  textCapitalization: TextCapitalization.characters,
                  validator: (val) => val!.isEmpty ? "ID required" : null,
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder(), filled: true),
                  validator: (val) => val!.isEmpty ? "Name required" : null,
                ),
                const SizedBox(height: 16),

                // Type & Current Target
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: const InputDecoration(labelText: "Type", border: OutlineInputBorder(), filled: true),
                        items: const [
                          DropdownMenuItem(value: 'resident', child: Text("Resident")),
                          DropdownMenuItem(value: 'shop', child: Text("Shop")),
                          DropdownMenuItem(value: 'business', child: Text("Business")),
                          DropdownMenuItem(value: 'donor', child: Text("Donor")),
                        ],
                        onChanged: (val) => setState(() => _selectedType = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _targetController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: "Target $currentYear (₹)", border: const OutlineInputBorder(), filled: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // NEW: Previous Years Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Previous Contributions (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _prevYear1Controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: "${currentYear - 1}", 
                                prefixText: "₹ ",
                                isDense: true,
                                border: const OutlineInputBorder(), 
                                filled: true,
                                fillColor: Colors.white
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _prevYear2Controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: "${currentYear - 2}", 
                                prefixText: "₹ ",
                                isDense: true,
                                border: const OutlineInputBorder(), 
                                filled: true,
                                fillColor: Colors.white
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Contact Details
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "Phone", border: OutlineInputBorder(), filled: true),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: "Address / Flat No", border: OutlineInputBorder(), filled: true),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveContributor,
                    icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Icon(Icons.save),
                    label: Text(_isLoading ? "SAVING..." : "CREATE PROFILE"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}