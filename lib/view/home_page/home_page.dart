import 'package:bnya/data/models/contributor/contributor.dart';
import 'package:bnya/view/contributor_directory_screen/contributor_directory_screen.dart';
import 'package:bnya/view/ledger_screen/ledger_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final TextEditingController _publicSearchController = TextEditingController();
  bool _isVerifying = false; // To show loading state during search
  List<Contributor> _allContributors = [];
  List<Contributor> _suggestions = [];

  final List<String> allowedEmails = [
    "mohanty747@gmail.com",
    "treasurer@society.com",
    "utkalspace@gmail.com",
    "mishra.debidatta@gmail.com",
  ];

  @override
  void dispose() {
    _publicSearchController.dispose();
    super.dispose();
  }

  String _formatCurrency(double amount) {
    return amount
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  // --- Search Suggestions Logic ---
  void _onSearchChanged(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    final stripped = clean.replaceAll(RegExp(r'[^a-z0-9]'), '');

    setState(() {
      _suggestions = _allContributors.where((c) {
        final cId = c.id.toLowerCase();
        final cName = c.name.toLowerCase();
        final cIdStripped = cId.replaceAll(RegExp(r'[^a-z0-9]'), '');
        return cId.contains(clean) ||
            cName.contains(clean) ||
            (stripped.isNotEmpty && cIdStripped.contains(stripped));
      }).take(5).toList();
    });
  }

  void _selectContributor(Contributor c) {
    setState(() {
      _suggestions = [];
      _publicSearchController.text = "${c.name} (${c.id})";
    });
    FocusScope.of(context).unfocus();
    _showContributorVerification(c);
  }

  void _showContributorVerification(Contributor c) {
    double totalPaid = 0;
    for (var payment in c.paymentHistory) {
      totalPaid += payment.amount;
    }
    for (var val in c.yearlyPayments.values) {
      totalPaid += val;
    }
    _showVerificationDialog(c.id, c.name, totalPaid, true);
  }

  // --- 1. Verify via ID OR Name ---
  Future<void> _verifyContribution() async {
    final String rawInput = _publicSearchController.text.trim();
    if (rawInput.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _suggestions = [];
    });

    try {
      String cleanInput = rawInput;
      // If the input is in "Name (ID)" format, extract the ID inside parentheses
      final RegExp regExp = RegExp(r'\(([^)]+)\)');
      final Match? match = regExp.firstMatch(cleanInput);
      if (match != null && match.group(1) != null) {
        cleanInput = match.group(1)!.trim();
      }

      final String searchTarget = cleanInput.toUpperCase();

      // Check 1: In-memory exact ID or Name lookup
      final Contributor? exactMatch = _allContributors.cast<Contributor?>().firstWhere(
        (c) =>
            c != null &&
            (c.id.toUpperCase() == searchTarget ||
                c.name.toUpperCase() == searchTarget),
        orElse: () => null,
      );

      if (exactMatch != null) {
        _showContributorVerification(exactMatch);
        setState(() => _isVerifying = false);
        return;
      }

      // Check 2: In-memory fuzzy stripped ID lookup (e.g. "SHOP01" or "SHOP 01" matching "SHOP-01")
      final String strippedTarget = searchTarget.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (strippedTarget.isNotEmpty) {
        final Contributor? fuzzyMatch = _allContributors.cast<Contributor?>().firstWhere(
          (c) =>
              c != null &&
              c.id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '') ==
                  strippedTarget,
          orElse: () => null,
        );

        if (fuzzyMatch != null) {
          _showContributorVerification(fuzzyMatch);
          setState(() => _isVerifying = false);
          return;
        }
      }

      // Check 3: Firestore queries if not found in local memory
      DocumentSnapshot? foundDoc;

      // STEP A: Try Direct Document ID Lookup
      final docRef = FirebaseFirestore.instance
          .collection('contributors')
          .doc(searchTarget);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        foundDoc = docSnap;
      } else {
        // STEP B: Query by internal 'id' field
        QuerySnapshot idQuery = await FirebaseFirestore.instance
            .collection('contributors')
            .where('id', isEqualTo: searchTarget)
            .limit(1)
            .get();

        if (idQuery.docs.isNotEmpty) {
          foundDoc = idQuery.docs.first;
        } else {
          // STEP C: Search by Name field
          QuerySnapshot nameQuery = await FirebaseFirestore.instance
              .collection('contributors')
              .where('name', isEqualTo: cleanInput)
              .limit(1)
              .get();

          if (nameQuery.docs.isNotEmpty) {
            foundDoc = nameQuery.docs.first;
          } else {
            QuerySnapshot nameQueryUpper = await FirebaseFirestore.instance
                .collection('contributors')
                .where('name', isEqualTo: searchTarget)
                .limit(1)
                .get();

            if (nameQueryUpper.docs.isNotEmpty) {
              foundDoc = nameQueryUpper.docs.first;
            }
          }
        }
      }

      if (!mounted) return;

      if (foundDoc != null && foundDoc.exists) {
        final Contributor contributor = Contributor.fromFirestore(foundDoc);
        _showContributorVerification(contributor);
      } else {
        // --- NOT FOUND ---
        _showVerificationDialog(rawInput, "", 0, false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
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
                    name.isNotEmpty ? "$name ($id)" : "ID: $id",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
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
                    "We could not find any records for: $id",
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

                    _allContributors = snapshot.data!.docs
                        .map((doc) => Contributor.fromFirestore(doc))
                        .where((c) => c.type.toLowerCase() != 'lottery_buyer')
                        .toList();

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
                      "Enter your Name or Shop ID (e.g., SHOP-01) to check your payment status securely.",
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
                              decoration: InputDecoration(
                                hintText: "ENTER NAME OR ID HERE",
                                hintStyle: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: 0,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                suffixIcon: _publicSearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _publicSearchController.clear();
                                            _suggestions = [];
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: _onSearchChanged,
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

                    // LIVE SUGGESTIONS DROPDOWN
                    if (_suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final Contributor c = _suggestions[index];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.blue[50],
                                child: Text(
                                  c.name.isNotEmpty
                                      ? c.name[0].toUpperCase()
                                      : "?",
                                  style: TextStyle(
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                "${c.name} (${c.id})",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                c.type.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.blue[800],
                              ),
                              onTap: () => _selectContributor(c),
                            );
                          },
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
