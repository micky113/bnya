import 'package:bnya/services/auth_service.dart';
import 'package:bnya/view/contributor_directory_screen/contributor_directory_screen.dart';
import 'package:bnya/view/ledger_screen/ledger_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:bnya/view/lottery/admin_upload_screen.dart';
import 'package:bnya/view/lottery/ticket_directory_screen.dart';
import 'package:bnya/view/lottery/live_draw_screen.dart';
import 'package:bnya/view/lottery/winners_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();
  final TextEditingController _publicSearchController = TextEditingController();
  bool _isVerifying = false; // To show loading state during search

  final List<String> allowedEmails = [
    "mohanty747@gmail.com",
    "treasurer@society.com",
    "utkalspace@gmail.com",
    "mishra.debidatta@gmail.com",
  ];

  String _formatCurrency(double amount) {
    return amount
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  // --- 1. UPDATED LOGIC: Verify via ID OR Name ---
  Future<void> _verifyContribution() async {
    final String rawInput = _publicSearchController.text.trim();
    if (rawInput.isEmpty) return;

    setState(() => _isVerifying = true);

    try {
      DocumentSnapshot? foundDoc;

      // STEP 1: Try Direct ID Lookup (Fastest)
      final String potentialId = rawInput.toUpperCase();
      final docRef = FirebaseFirestore.instance
          .collection('contributors')
          .doc(potentialId);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        foundDoc = docSnap;
      } else {
        // STEP 2: If ID not found, Search by Name field
        QuerySnapshot nameQuery =
            await FirebaseFirestore.instance
                .collection('contributors')
                .where('name', isEqualTo: rawInput)
                .limit(1)
                .get();

        if (nameQuery.docs.isNotEmpty) {
          foundDoc = nameQuery.docs.first;
        } else {
          // Try Uppercase Name search
          QuerySnapshot nameQueryUpper =
              await FirebaseFirestore.instance
                  .collection('contributors')
                  .where('name', isEqualTo: rawInput.toUpperCase())
                  .limit(1)
                  .get();

          if (nameQueryUpper.docs.isNotEmpty) {
            foundDoc = nameQueryUpper.docs.first;
          }
        }
      }

      if (!mounted) return;

      if (foundDoc != null && foundDoc.exists) {
        // --- RECORD FOUND ---
        final data = foundDoc.data() as Map<String, dynamic>;

        final String realId = foundDoc.id;
        final String name = data['name'] ?? 'Unknown';

        // --- UPDATED: Calculate Total from paymentHistory ---
        final List<dynamic> history =
            (data['paymentHistory'] as List<dynamic>?) ?? [];
        double totalPaid = 0;
        for (var payment in history) {
          if (payment is Map && payment['amount'] != null) {
            totalPaid += (payment['amount'] as num).toDouble();
          }
        }

        _showVerificationDialog(realId, name, totalPaid, true);
      } else {
        // --- NOT FOUND ---
        _showVerificationDialog(rawInput, "", 0, false);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // --- 2. The Result Dialog ---
  void _showVerificationDialog(
    String id,
    String name,
    double amount,
    bool exists,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  exists ? Icons.check_circle : Icons.error_outline,
                  size: 60,
                  color: exists ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  exists ? "Verified Member" : "Record Not Found",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                if (exists) ...[
                  Text(
                    name,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  Text("ID: $id", style: const TextStyle(color: Colors.grey)),
                  const Divider(height: 30),
                  const Text(
                    "Total Contribution",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    "₹ ${_formatCurrency(amount)}",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade100),
                    ),
                    child: const Text(
                      "Payment Active",
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    "We could not find any records for ID: $id",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Please check if you typed the ID correctly (e.g., SHOP-01).",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("CLOSE"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Navigation to Contributor Directory
  void _navigateToContributorDirectory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ContributorDirectoryScreen(),
      ),
    );
  }

  // Navigation to Financial Ledger
  void _navigateToLedger() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LedgerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            // Icon(Icons.apartment, size: 24),
            // SizedBox(width: 10),
            // Text("BNYA", style: TextStyle(fontWeight: FontWeight.bold)),
            Image.asset(
              'images/logo.png',
              height: 46, // 1. Set a fixed height (standard AppBar is 56)
              fit: BoxFit.fill,
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[900],
        elevation: 1,
        actions: [
          // 1. LOTTERY BUTTON
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 8.0 : 16.0),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                Widget screen;
                switch (value) {
                  case 'register':
                    screen = const AdminUploadScreen();
                    break;
                  case 'dashboard':
                    screen = const TicketDirectoryScreen();
                    break;
                  case 'draw':
                    screen = const LiveDrawScreen();
                    break;
                  case 'winners':
                    screen = const WinnersScreen();
                    break;
                  default:
                    return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => screen),
                );
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'register',
                  child: Row(
                    children: [
                      Icon(Icons.app_registration, color: Color(0xFF00695C), size: 20),
                      SizedBox(width: 10),
                      Text("Register Sold Tickets"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'dashboard',
                  child: Row(
                    children: [
                      Icon(Icons.dashboard_outlined, color: Color(0xFF0277BD), size: 20),
                      SizedBox(width: 10),
                      Text("Ticket Directory"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'draw',
                  child: Row(
                    children: [
                      Icon(Icons.live_tv_rounded, color: Colors.amber, size: 20),
                      SizedBox(width: 10),
                      Text("Live Projector Draw"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'winners',
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, color: Colors.orange, size: 20),
                      SizedBox(width: 10),
                      Text("Lottery Winners"),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8.0 : 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.shade200, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_activity_outlined, color: Colors.amber.shade900, size: 16),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      Text(
                        "LOTTERY 🎟️",
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: Colors.amber.shade900, size: 16),
                  ],
                ),
              ),
            ),
          ),
          
          // 2. CONTRIBUTOR DIRECTORY BUTTON
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 8.0 : 16.0),
            child: isMobile
                ? IconButton(
                    tooltip: "Contributor Directory",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue[50],
                      foregroundColor: Colors.blue[800],
                    ),
                    icon: const Icon(Icons.people_outline, size: 18),
                    onPressed: _navigateToContributorDirectory,
                  )
                : TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue[800],
                      backgroundColor: Colors.blue[50],
                    ),
                    icon: const Icon(Icons.people_outline, size: 18),
                    label: const Text("Contributor Directory"),
                    onPressed: _navigateToContributorDirectory,
                  ),
          ),
          
          // 3. FINANCIAL LEDGER BUTTON
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 12.0 : 16.0),
            child: isMobile
                ? IconButton(
                    tooltip: "Financial Ledger",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.blue[900],
                      side: BorderSide(color: Colors.blue.shade200, width: 1.5),
                    ),
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    onPressed: _navigateToLedger,
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[900],
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: Colors.blue.shade200, width: 1.5),
                      shape: const StadiumBorder(), // Pill shape
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    icon: Icon(Icons.account_balance_wallet_outlined, size: 16, color: Colors.blue[800]),
                    label: const Text(
                      "FINANCIAL LEDGER",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    onPressed: _navigateToLedger,
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // HERO SECTION
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('images/laxmi.jpg'),
                  fit: BoxFit.fill,
                ),
              ),
              child: const Column(
                children: [
                  Text(
                    "Welcome to the Community",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Collection Drive 2025",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  Text(
                    "Transparency • Community • Growth",
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),

            // STATS CARD
            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('contributors')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    int totalContributors = snapshot.data!.docs.length;

                    return Column(
                      children: [
                        Text(
                          "TOTAL FUNDS COLLECTED",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('ledger')
                              .where('type', isEqualTo: 'income')
                              .snapshots(),
                          builder: (context, ledgerSnapshot) {
                            double totalCollected = 0;
                            if (ledgerSnapshot.hasData) {
                              for (var doc in ledgerSnapshot.data!.docs) {
                                final data = doc.data() as Map<String, dynamic>;
                                final double cash = (data['cash'] ?? 0).toDouble();
                                final double bankSbi = (data['bankSbi'] ?? 0).toDouble();
                                final double bankHdfc = (data['bankHdfc'] ?? 0).toDouble();
                                totalCollected += (cash + bankSbi + bankHdfc);
                              }
                            }
                            return Text(
                              "₹ ${_formatCurrency(totalCollected)}",
                              style: TextStyle(
                                color: Colors.green[800],
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        const Divider(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem(
                              totalContributors.toString(),
                              "Contributors",
                            ),
                            _buildStatItem("Active", "Status"),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // VERIFICATION SECTION
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.blue.shade50),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.verified_user_rounded,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Verify Contribution",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Enter your Shop ID (e.g., SHOP-01) to check your payment status securely.",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stylish Input Field
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          const Icon(Icons.search, color: Colors.grey),
                          const SizedBox(width: 10),

                          // TEXT FIELD
                          Expanded(
                            child: TextField(
                              controller: _publicSearchController,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1.0,
                              ),
                              decoration: const InputDecoration(
                                hintText: "ENTER ID HERE",
                                hintStyle: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: 0,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) {
                                FocusScope.of(context).unfocus();
                                _verifyContribution();
                              },
                            ),
                          ),

                          const SizedBox(width: 12),

                          // The Action Button
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap:
                                  _isVerifying
                                      ? null
                                      : () {
                                        FocusScope.of(context).unfocus();
                                        _verifyContribution();
                                      },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade900,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade900.withOpacity(
                                        0.3,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child:
                                      _isVerifying
                                          ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                          ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // FOOTER
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Colors.grey[400],
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Secure • Transparent • Official",
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
