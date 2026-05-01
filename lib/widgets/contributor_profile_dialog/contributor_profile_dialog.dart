import 'package:bnya/data/models/contributor/contributor.dart';
import 'package:bnya/widgets/edit_contributor_dialog/edit_contributor_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ContributorProfileDialog extends StatelessWidget {
  final Contributor contributor;

  const ContributorProfileDialog({super.key, required this.contributor});

  @override
  Widget build(BuildContext context) {
    // Logic to separate "Current Year" from "Previous Years"
    final currentYear = DateTime.now().year.toString();
    // final currentYearPayment = contributor.yearlyPayments[currentYear] ?? 0.0;

    // // Filter for previous years
    // final previousPayments = Map.from(contributor.yearlyPayments)
    //   ..remove(currentYear); // Remove current year to leave only past records

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 500, // Fixed width for nice Web presentation
        // constraints: const BoxConstraints(maxHeight: 700),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. TOP IMAGE SECTION
                  _buildImageHeader(),

                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 2. IDENTITY & CONTACT DETAILS
                        _buildIdentitySection(),

                        const Divider(height: 32),

                        // 3. CURRENT YEAR STATUS
                        // _buildCurrentYearSection(
                        //   currentYear,
                        //   currentYearPayment,
                        // ),

                        const SizedBox(height: 24),

                        // 4. PREVIOUS YEARS HISTORY
                        // if (previousPayments.isNotEmpty) ...[
                        //   const Text(
                        //     "Previous History",
                        //     style: TextStyle(
                        //       fontSize: 16,
                        //       fontWeight: FontWeight.bold,
                        //       color: Colors.grey,
                        //     ),
                        //   ),
                        //   const SizedBox(height: 12),
                        //   _buildPreviousYearsList(previousPayments),
                        // ],
                      ],
                    ),
                  ),

                  // 5. CLOSE BUTTON
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey[50],
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("CLOSE PROFILE"),
                    ),
                  ),
                ],
              ),
            ),
            // 2. THE EDIT/DELETE BUTTONS (Floated Top Right)
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  // Edit Button
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      tooltip: "Edit Profile",
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder:
                              (context) => EditContributorDialog(
                                contributor: contributor,
                              ),
                        ).then((_) {
                          // Optional: If you want the profile dialog to refresh immediately
                          // without closing, you'd need to convert ContributorProfileDialog
                          // to a StatefulWidget and fetch data again.
                          // For now, closing the profile dialog is safer UI behavior:
                          Navigator.pop(context);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Delete Button
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: "Delete Profile",
                      onPressed: () => _deleteContributor(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildImageHeader() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        image:
            contributor.imageUrl != null
                ? DecorationImage(
                  image: NetworkImage(contributor.imageUrl!),
                  fit: BoxFit.fill,
                )
                : null,
      ),
      child:
          contributor.imageUrl == null
              ? Center(
                child: Icon(
                  contributor.type == 'shop' ? Icons.storefront : Icons.person,
                  size: 80,
                  color: Colors.blue.shade200,
                ),
              )
              : null,
    );
  }

  Widget _buildIdentitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                contributor.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                contributor.type.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _iconText(Icons.numbers, "ID: ${contributor.id}"),
        _iconText(Icons.location_on, contributor.address),
        _iconText(Icons.phone, contributor.contactNumber),
      ],
    );
  }

  Widget _buildCurrentYearSection(String year, double amount) {
    bool isPaid = amount > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.warning_amber_rounded,
            color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
            size: 32,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Payment Status ($year)",
                style: TextStyle(
                  color: isPaid ? Colors.green.shade900 : Colors.red.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isPaid ? "Paid: ₹${amount.toInt()}" : "No payment recorded yet",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isPaid ? Colors.black87 : Colors.red.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Function to handle deletion
  Future<void> _deleteContributor(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Delete Contributor?"),
            content: const Text(
              "This will permanently delete this profile.\n\n"
              "Note: Past transaction records in the finance log will remain, but they will no longer be linked to this profile.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('contributors')
            .doc(contributor.id)
            .delete();

        if (context.mounted) {
          Navigator.of(context).pop(); // Close Profile Dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile Deleted"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      }
    }
  }

  Widget _buildPreviousYearsList(Map<dynamic, dynamic> history) {
    // Sort years descending (newest first)
    final sortedYears = history.keys.toList()..sort((a, b) => b.compareTo(a));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          sortedYears.map((year) {
            return Container(
              width: 100, // Fixed width card for each year
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    year,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "₹${history[year]!.toInt()}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _iconText(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.grey[800])),
          ),
        ],
      ),
    );
  }
}
