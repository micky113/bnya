import 'package:bnya/data/models/contributor/contributor.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bnya/services/auth_service.dart'; // Import your AuthService

class EditContributorDialog extends StatefulWidget {
  final Contributor contributor;

  const EditContributorDialog({super.key, required this.contributor});

  @override
  State<EditContributorDialog> createState() => _EditContributorDialogState();
}

class _EditContributorDialogState extends State<EditContributorDialog> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService(); // Auth Instance

  // Allowed Admin Emails
  final List<String> _adminEmails = ["mohanty747@gmail.com"];

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _targetController;

  String _selectedType = 'resident';
  bool _isLoading = false;

  // State for Target Field Lock
  bool _isTargetEditable = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contributor.name);
    _phoneController = TextEditingController(
      text: widget.contributor.contactNumber,
    );
    _addressController = TextEditingController(
      text: widget.contributor.address,
    );
    _targetController = TextEditingController(
      text:
          widget.contributor.targetAmount > 0
              ? widget.contributor.targetAmount.toStringAsFixed(0)
              : '',
    );
    _selectedType = widget.contributor.type;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  // --- AUTH LOGIC ---
  Future<void> _unlockTargetField() async {
    // 1. Check if already signed in
    User? user = FirebaseAuth.instance.currentUser;

    // 2. If not, trigger Google Sign In
    if (user == null) {
      user = await _authService.signInWithGoogle();
    }

    if (user != null) {
      // 3. Verify Email
      if (_adminEmails.contains(user.email)) {
        setState(() {
          _isTargetEditable = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Access Granted! You can now edit the target."),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Access Denied. You are not authorized."),
            backgroundColor: Colors.red,
          ),
        );
        // Optional: Sign out unauthorized user
        await _authService.signOut();
      }
    }
  }

  Future<void> _updateContributor() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        await FirebaseFirestore.instance
            .collection('contributors')
            .doc(widget.contributor.id)
            .update({
              'name': _nameController.text.trim(),
              'type': _selectedType,
              'contactNumber': _phoneController.text.trim(),
              'address': _addressController.text.trim(),
              // Only update target if it was unlocked (or keep existing if locked logic needed, but usually we just overwrite)
              'targetAmount': double.tryParse(_targetController.text) ?? 0.0,
            });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile Updated!'),
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
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    const Text(
                      "Edit Profile",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),

                // Read-Only ID
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  width: double.infinity,
                  child: Text(
                    "ID: ${widget.contributor.id}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "Name",
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  validator: (val) => val!.isEmpty ? "Name required" : null,
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type Dropdown
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: const InputDecoration(
                          labelText: "Type",
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'resident',
                            child: Text("Resident"),
                          ),
                          DropdownMenuItem(value: 'shop', child: Text("Shop")),
                          DropdownMenuItem(
                            value: 'business',
                            child: Text("Business"),
                          ),
                          DropdownMenuItem(
                            value: 'donor',
                            child: Text("Donor"),
                          ),
                        ],
                        onChanged:
                            (val) => setState(() => _selectedType = val!),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // --- SECURE TARGET FIELD ---
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _targetController,
                        keyboardType: TextInputType.number,
                        // 1. Logic: If _isTargetEditable is false, field is read-only
                        readOnly: !_isTargetEditable,
                        decoration: InputDecoration(
                          labelText: "Target (₹)",
                          border: const OutlineInputBorder(),
                          filled: true,
                          // Visual cue for disabled state
                          fillColor:
                              _isTargetEditable
                                  ? Colors.white
                                  : Colors.grey[200],
                          suffixIcon: IconButton(
                            // 2. Lock/Unlock Icon
                            icon: Icon(
                              _isTargetEditable ? Icons.lock_open : Icons.lock,
                              color:
                                  _isTargetEditable
                                      ? Colors.green
                                      : Colors.grey,
                              size: 20,
                            ),
                            tooltip:
                                _isTargetEditable ? "Unlocked" : "Admin Only",
                            onPressed:
                                _isTargetEditable
                                    ? null
                                    : _unlockTargetField, // Trigger Auth
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone",
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: "Address / Flat No",
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _updateContributor,
                    icon:
                        _isLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Icon(Icons.save),
                    label: Text(_isLoading ? "UPDATING..." : "SAVE CHANGES"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                    ),
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
