import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bnya/view/lottery/ticket_model.dart';

class WinnersScreen extends StatefulWidget {
  const WinnersScreen({super.key});

  @override
  State<WinnersScreen> createState() => _WinnersScreenState();
}

class _WinnersScreenState extends State<WinnersScreen> {
  final TextEditingController _checkTicketController = TextEditingController();
  bool _isChecking = false;
  String _checkResult = "";
  Color _checkResultColor = Colors.grey;

  // Real-time winners loaded from separate collections
  List<Ticket> _grandWinners = [];
  List<Ticket> _consolationWinners = [];
  bool _isLoadingGrand = true;
  bool _isLoadingConsolation = true;
  StreamSubscription? _grandSub;
  StreamSubscription? _consolationSub;

  // Mask Name helper for privacy
  String _maskName(String name) {
    if (name.isEmpty) return "";
    final parts = name.split(' ');
    if (parts.length == 1) {
      if (parts[0].length > 4) {
        return "${parts[0].substring(0, 3)}...";
      }
      return parts[0];
    }
    final firstPart = parts.sublist(0, parts.length - 1).join(' ');
    final lastPart = parts.last;
    if (lastPart.isNotEmpty) {
      return "$firstPart ${lastPart[0]}.";
    }
    return firstPart;
  }

  @override
  void initState() {
    super.initState();
    _listenToWinners();
  }

  void _listenToWinners() {
    _grandSub = FirebaseFirestore.instance
        .collection('grand_winners')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _grandWinners = snapshot.docs.map((doc) {
            return Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList()..sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));
          _isLoadingGrand = false;
        });
      }
    }, onError: (e) {
      print("ERROR: Failed to stream grand_winners collection: $e");
      if (mounted) setState(() => _isLoadingGrand = false);
    });

    _consolationSub = FirebaseFirestore.instance
        .collection('consolation_winners')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _consolationWinners = snapshot.docs.map((doc) {
            return Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList()..sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));
          _isLoadingConsolation = false;
        });
      }
    }, onError: (e) {
      print("ERROR: Failed to stream consolation_winners collection: $e");
      if (mounted) setState(() => _isLoadingConsolation = false);
    });
  }

  // Check if a specific ticket won
  Future<void> _checkMyTicket() async {
    final String input = _checkTicketController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isChecking = true;
      _checkResult = "";
    });

    try {
      final int? ticketNum = int.tryParse(input);
      if (ticketNum == null || ticketNum < 1 || ticketNum > 20000) {
        setState(() {
          _checkResult = "Please enter a valid ticket number between 1 and 20,000.";
          _checkResultColor = Colors.orange;
        });
        return;
      }

      final docSnap = await FirebaseFirestore.instance
          .collection('tickets')
          .doc(ticketNum.toString())
          .get();

      if (!docSnap.exists) {
        setState(() {
          _checkResult = "Ticket #$ticketNum is not registered in the system (Unsold).";
          _checkResultColor = Colors.grey.shade600;
        });
        return;
      }

      final ticket = Ticket.fromMap(docSnap.data() as Map<String, dynamic>, docSnap.id);

      setState(() {
        if (ticket.hasWonGrandPrize) {
          _checkResult = "🎉 CONGRATULATIONS! Ticket #$ticketNum (${_maskName(ticket.buyerName)}) has won a GRAND PRIZE! 🏆";
          _checkResultColor = Colors.amber.shade800;
        } else if (ticket.hasWonConsolation) {
          _checkResult = "🎉 CONGRATULATIONS! Ticket #$ticketNum (${_maskName(ticket.buyerName)}) has won a Consolation Prize! 🎟️";
          _checkResultColor = Colors.teal.shade800;
        } else {
          _checkResult = "Ticket #$ticketNum is registered to ${_maskName(ticket.buyerName)} but did not win a prize in this draw. Better luck next time!";
          _checkResultColor = Colors.blueGrey;
        }
      });
    } catch (e) {
      setState(() {
        _checkResult = "Error checking ticket: $e";
        _checkResultColor = Colors.red;
      });
    } finally {
      setState(() => _isChecking = false);
    }
  }

  @override
  void dispose() {
    _grandSub?.cancel();
    _consolationSub?.cancel();
    _checkTicketController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (_isLoadingGrand || _isLoadingConsolation) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F9FA),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00695C)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FA),
      appBar: AppBar(
        title: const Text(
          "Lottery Winners Circle",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00695C),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gold Trophy Header
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.emoji_events, size: 72, color: Colors.amber),
                    const SizedBox(height: 12),
                    const Text(
                      "CONGRATULATIONS TO THE WINNERS",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF00695C),
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                        ),
                    const SizedBox(height: 6),
                    Text(
                      "Community Lottery Draw 2025 results are synchronized live",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Ticket verification box ("Did I win?")
              _buildSearchCheckerCard(isMobile),
              const SizedBox(height: 32),

              // Grand Prize Section
              _buildGrandWinnersSection(_grandWinners, isMobile),
              const SizedBox(height: 32),

              // Consolation Winners Section
              _buildConsolationWinnersSection(_consolationWinners, isMobile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchCheckerCard(bool isMobile) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.teal.shade50, width: 1.5),
        ),
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.search, color: Color(0xFF00695C)),
                SizedBox(width: 8),
                Text(
                  "Check Your Ticket Number",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _checkTicketController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: "Enter Ticket ID (1 - 20000)",
                      fillColor: Colors.grey.shade50,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onSubmitted: (_) => _checkMyTicket(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00695C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isChecking ? null : _checkMyTicket,
                    child: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text("CHECK RESULT", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            if (_checkResult.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _checkResultColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _checkResultColor.withOpacity(0.3)),
                ),
                child: Text(
                  _checkResult,
                  style: TextStyle(color: _checkResultColor, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGrandWinnersSection(List<Ticket> winners, bool isMobile) {
    if (winners.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: const Center(
          child: Text(
            "Grand prizes draw has not started yet. Stay tuned!",
            style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "🏆 GRAND PRIZE WINNERS",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF00695C), letterSpacing: 1.2),
        ),
        const Divider(height: 20),
        const SizedBox(height: 10),
        
        // Grid View of winners
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: winners.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: isMobile ? 360 : 260,
            childAspectRatio: 1.4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final winner = winners[index];
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.amber, width: 2),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.amber.shade50, Colors.white],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "PRIZE #${index + 1}",
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "#${winner.ticketNumber.toString().padLeft(4, '0')}",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _maskName(winner.buyerName),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00695C)),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Book #${winner.bookId}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildConsolationWinnersSection(List<Ticket> winners, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "🎟️ CONSOLATION PRIZE WINNERS",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0277BD)),
        ),
        const Divider(height: 20),
        const SizedBox(height: 10),

        if (winners.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: const Center(
              child: Text(
                "Consolation prizes draw has not started yet. Stay tuned!",
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ),
          )
        else
          // List of consolation winners
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: winners.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 2.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final winner = winners[index];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Ticket #${winner.ticketNumber}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _maskName(winner.buyerName),
                    style: const TextStyle(color: Colors.blueGrey, fontSize: 11, overflow: TextOverflow.ellipsis),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    "Book #${winner.bookId}",
                    style: const TextStyle(color: Colors.grey, fontSize: 9),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
