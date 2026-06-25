import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bnya/view/lottery/ticket_model.dart';

enum DrawState {
  idle,
  drawingConsolations,
  readyForGrandPrizes,
  drawingGrandPrize,
  allFinished
}

class LiveDrawScreen extends StatefulWidget {
  const LiveDrawScreen({super.key});

  @override
  State<LiveDrawScreen> createState() => _LiveDrawScreenState();
}

class _LiveDrawScreenState extends State<LiveDrawScreen> {
  DrawState _currentState = DrawState.idle;

  // Local storage for tickets
  List<Ticket> _allSoldTickets = [];
  bool _isLoading = false;

  // Consolation draw data
  List<int> _activeBookIds = [];
  Map<int, List<Ticket>> _ticketsByBook = {}; // bookId -> list of sold tickets
  Map<int, Ticket> _consolationWinners = {}; // bookId -> winning Ticket
  Map<int, String> _consolationDisplayNumbers = {}; // bookId -> ticket number string being rolled
  Set<int> _settledBooks = {};
  int _currentlySettlingBookIndex = -1;
  Timer? _consolationRollTimer;
  final ScrollController _gridScrollController = ScrollController();

  // Grand Prize draw data
  List<Ticket> _grandPrizePool = [];
  List<Ticket> _grandPrizeWinners = [];
  int _currentGrandPrizeIndex = 0; // 0 to 4 (for 5 grand prizes)
  
  // Grand Prize Animation states
  int _countdownSeconds = 3;
  Timer? _countdownTimer;
  bool _isCountingDown = false;
  Ticket? _revealedGrandWinner;
  String _rollingGrandName = "";
  String _rollingGrandNumber = "";
  Timer? _grandRollTimer;

  // Firestore Sync state
  bool _isSyncing = false;
  bool _isSynced = false;

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
  void dispose() {
    _consolationRollTimer?.cancel();
    _countdownTimer?.cancel();
    _grandRollTimer?.cancel();
    _gridScrollController.dispose();
    super.dispose();
  }

  // Load sold tickets into memory
  Future<void> _loadSoldTickets() async {
    setState(() {
      _isLoading = true;
      _isSynced = false;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tickets')
          .where('isSold', isEqualTo: true)
          .get();

      final tickets = snapshot.docs.map((doc) {
        return Ticket.fromMap(doc.data(), doc.id);
      }).toList();

      setState(() {
        _allSoldTickets = tickets;
        
        // Group by Book ID
        _ticketsByBook.clear();
        for (var t in tickets) {
          _ticketsByBook.putIfAbsent(t.bookId, () => []).add(t);
        }

        // Identify active book IDs
        _activeBookIds = _ticketsByBook.keys.toList()..sort();
        
        _currentState = DrawState.idle;
        _consolationWinners.clear();
        _settledBooks.clear();
        _grandPrizeWinners.clear();
        _revealedGrandWinner = null;
        _currentGrandPrizeIndex = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Loaded ${_allSoldTickets.length} sold tickets across ${_activeBookIds.length} active books!"),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading tickets: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Draw algorithm - Consolation Prizes
  void _startConsolationDraw() {
    if (_activeBookIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No active books to draw from. Add sold tickets first.")),
      );
      return;
    }

    setState(() {
      _currentState = DrawState.drawingConsolations;
      _settledBooks.clear();
      _currentlySettlingBookIndex = 0;
    });

    final Random random = Random();

    // 1. Run local draw calculations
    for (int bookId in _activeBookIds) {
      final bookTickets = _ticketsByBook[bookId]!;
      // Pick exactly ONE ticket from this book
      final winner = bookTickets[random.nextInt(bookTickets.length)];
      _consolationWinners[bookId] = winner.copyWith(hasWonConsolation: true);
    }

    // 2. Start rolling slot machine animation
    _consolationRollTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      setState(() {
        for (int bookId in _activeBookIds) {
          if (!_settledBooks.contains(bookId)) {
            final bookTickets = _ticketsByBook[bookId]!;
            final randomTicket = bookTickets[random.nextInt(bookTickets.length)];
            _consolationDisplayNumbers[bookId] = randomTicket.ticketNumber.toString().padLeft(4, '0');
          }
        }
      });
    });

    // 3. Sequentially settle each book's draw
    _settleNextBook();
  }

  void _settleNextBook() {
    if (_currentlySettlingBookIndex >= _activeBookIds.length) {
      // Consolation draw completed
      _consolationRollTimer?.cancel();
      setState(() {
        _currentState = DrawState.readyForGrandPrizes;
        _currentlySettlingBookIndex = -1;
      });

      // Prepare grand prize pool (Sold tickets that did NOT win consolation)
      final consolationWinnerNumbers = _consolationWinners.values.map((t) => t.ticketNumber).toSet();
      _grandPrizePool = _allSoldTickets
          .where((t) => !consolationWinnerNumbers.contains(t.ticketNumber))
          .toList();

      return;
    }

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      
      final int bookId = _activeBookIds[_currentlySettlingBookIndex];
      setState(() {
        _settledBooks.add(bookId);
        // Set display number to the actual winner
        _consolationDisplayNumbers[bookId] = _consolationWinners[bookId]!.ticketNumber.toString().padLeft(4, '0');
        _currentlySettlingBookIndex++;
      });

      // Auto scroll the grid to follow settling cards
      if (_gridScrollController.hasClients) {
        final double maxScroll = _gridScrollController.position.maxScrollExtent;
        final double currentProgress = _currentlySettlingBookIndex / _activeBookIds.length;
        _gridScrollController.animateTo(
          maxScroll * currentProgress,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }

      _settleNextBook();
    });
  }

  // Draw algorithm - Grand Prize
  void _drawNextGrandPrize() {
    if (_grandPrizeWinners.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All 5 Grand Prizes have already been drawn.")),
      );
      return;
    }

    if (_grandPrizePool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No eligible tickets remaining for Grand Prize draw.")),
      );
      return;
    }

    setState(() {
      _currentState = DrawState.drawingGrandPrize;
      _isCountingDown = true;
      _countdownSeconds = 3;
      _revealedGrandWinner = null;
    });

    final Random random = Random();

    // Select the winner from pool
    final winnerIndex = random.nextInt(_grandPrizePool.length);
    final selectedWinner = _grandPrizePool[winnerIndex];
    
    // Remove winner from pool so they can't win again
    _grandPrizePool.removeAt(winnerIndex);

    // Setup rolling names/numbers for projector visual drama
    _grandRollTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      final randomTicket = _allSoldTickets[random.nextInt(_allSoldTickets.length)];
      setState(() {
        _rollingGrandNumber = randomTicket.ticketNumber.toString().padLeft(4, '0');
        _rollingGrandName = _maskName(randomTicket.buyerName);
      });
    });

    // Start 3-second countdown
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        } else {
          // Reveal Grand Winner
          _countdownTimer?.cancel();
          _grandRollTimer?.cancel();
          _isCountingDown = false;
          _revealedGrandWinner = selectedWinner.copyWith(hasWonGrandPrize: true);
          _grandPrizeWinners.add(_revealedGrandWinner!);
          _currentGrandPrizeIndex++;
        }
      });
    });
  }

  // Sync to database via batch update
  Future<void> _syncDrawResults() async {
    setState(() => _isSyncing = true);

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final WriteBatch batch = firestore.batch();

      // 1. Reset all winning flags in the tickets collection first to clear any old draws
      final oldWinnersSnap = await firestore
          .collection('tickets')
          .where('hasWonGrandPrize', isEqualTo: true)
          .get();
      for (var doc in oldWinnersSnap.docs) {
        batch.update(doc.reference, {'hasWonGrandPrize': false});
      }

      final oldConsolationsSnap = await firestore
          .collection('tickets')
          .where('hasWonConsolation', isEqualTo: true)
          .get();
      for (var doc in oldConsolationsSnap.docs) {
        batch.update(doc.reference, {'hasWonConsolation': false});
      }

      // 2. Delete all previous winners in the separate grand_winners and consolation_winners collections
      final oldGrandWinnersColl = await firestore.collection('grand_winners').get();
      for (var doc in oldGrandWinnersColl.docs) {
        batch.delete(doc.reference);
      }

      final oldConsolationWinnersColl = await firestore.collection('consolation_winners').get();
      for (var doc in oldConsolationWinnersColl.docs) {
        batch.delete(doc.reference);
      }

      // 3. Write new Consolation winners into the consolation_winners collection and update tickets flags
      for (var winner in _consolationWinners.values) {
        // Write to separate collection
        final winnerDocRef = firestore.collection('consolation_winners').doc(winner.ticketNumber.toString());
        batch.set(winnerDocRef, winner.toMap());

        // Update main tickets flag
        final docRef = firestore.collection('tickets').doc(winner.ticketNumber.toString());
        batch.update(docRef, {
          'hasWonConsolation': true,
        });
      }

      // 4. Write new Grand prize winners into the grand_winners collection and update tickets flags
      for (var winner in _grandPrizeWinners) {
        // Write to separate collection
        final winnerDocRef = firestore.collection('grand_winners').doc(winner.ticketNumber.toString());
        batch.set(winnerDocRef, winner.toMap());

        // Update main tickets flag
        final docRef = firestore.collection('tickets').doc(winner.ticketNumber.toString());
        batch.update(docRef, {
          'hasWonGrandPrize': true,
        });
      }

      await batch.commit();

      setState(() {
        _isSynced = true;
        _currentState = DrawState.allFinished;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Success"),
            content: const Text("All draw results have been successfully saved to Cloud Firestore!"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to sync results to Firestore: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Cinematic deep slate dark
      appBar: AppBar(
        title: const Text(
          "LIVE PROJECTOR DRAW SCREEN",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.teal.shade400,
        elevation: 4,
        actions: [
          if (_currentState == DrawState.idle || _allSoldTickets.isEmpty)
            TextButton.icon(
              onPressed: _isLoading ? null : _loadSoldTickets,
              icon: const Icon(Icons.refresh, color: Colors.tealAccent),
              label: const Text("Load Tickets", style: TextStyle(color: Colors.tealAccent)),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : _allSoldTickets.isEmpty
              ? _buildEmptyState()
              : _buildMainDrawContent(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.slow_motion_video, size: 80, color: Colors.teal.shade800),
          const SizedBox(height: 16),
          const Text(
            "Ready for Cinematic Draw Session",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "First, load all the registered/sold tickets from database.",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: _loadSoldTickets,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text("LOAD FIREBASE TICKETS", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMainDrawContent() {
    switch (_currentState) {
      case DrawState.idle:
        return _buildIdleState();
      case DrawState.drawingConsolations:
      case DrawState.readyForGrandPrizes:
        return _buildConsolationsDrawState();
      case DrawState.drawingGrandPrize:
        return _buildGrandPrizeDrawState();
      case DrawState.allFinished:
        return _buildAllFinishedState();
    }
  }

  Widget _buildIdleState() {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.teal.shade800, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline, size: 100, color: Colors.tealAccent),
              const SizedBox(height: 24),
              const Text(
                "COMMUNITY LOTTERY DRAW",
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),
              _buildInfoRow("Total Sold Tickets in Pool", _allSoldTickets.length.toString()),
              _buildInfoRow("Active Books", _activeBookIds.length.toString()),
              _buildInfoRow("Consolation Prizes (1 per book)", _activeBookIds.length.toString()),
              _buildInfoRow("Grand Prizes (Global Draw)", "5 Prizes"),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.shade700,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                  ),
                  onPressed: _startConsolationDraw,
                  child: const Text(
                    "START DRAWING CONSOLATION PRIZES",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildConsolationsDrawState() {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Column(
      children: [
        // Top Banner Info
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E293B),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _currentState == DrawState.drawingConsolations
                              ? Icons.autorenew
                              : Icons.check_circle,
                          color: Colors.tealAccent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _currentState == DrawState.drawingConsolations
                                ? "PHASE 1: CONSOLATION DRAWS"
                                : "CONSOLATION DRAWS COMPLETED",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentState == DrawState.drawingConsolations
                          ? "Drawing 1 ticket from each of the ${_activeBookIds.length} active books..."
                          : "Drawn ${_consolationWinners.length} consolation winners. Ready for Grand Prizes.",
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    if (_currentState == DrawState.readyForGrandPrizes) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _currentState = DrawState.drawingGrandPrize;
                            _currentGrandPrizeIndex = 0;
                          });
                        },
                        icon: const Icon(Icons.emoji_events),
                        label: const Text("PROCEED TO GRAND PRIZES", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      _currentState == DrawState.drawingConsolations ? Icons.autorenew : Icons.check_circle,
                      color: Colors.tealAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentState == DrawState.drawingConsolations
                                ? "PHASE 1: DRAWING CONSOLATION WINNERS"
                                : "CONSOLATION WINNERS DRAWS COMPLETED",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _currentState == DrawState.drawingConsolations
                                ? "Drawing 1 ticket from each of the ${_activeBookIds.length} active books..."
                                : "Drawn ${_consolationWinners.length} consolation winners. Ready for Grand Prizes.",
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (_currentState == DrawState.readyForGrandPrizes) ...[
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        onPressed: () {
                          setState(() {
                            _currentState = DrawState.drawingGrandPrize;
                            _currentGrandPrizeIndex = 0;
                          });
                        },
                        icon: const Icon(Icons.emoji_events),
                        label: const Text("PROCEED TO GRAND PRIZES", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
        ),

        // Grid View
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: GridView.builder(
              controller: _gridScrollController,
              itemCount: _activeBookIds.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 1.6,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final int bookId = _activeBookIds[index];
                final bool isSettled = _settledBooks.contains(bookId);
                final String currentNum = _consolationDisplayNumbers[bookId] ?? "----";
                final Ticket? winner = _consolationWinners[bookId];

                return Container(
                  decoration: BoxDecoration(
                    color: isSettled ? const Color(0xFF0F2D37) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSettled ? Colors.tealAccent : Colors.teal.shade900,
                      width: isSettled ? 2.0 : 1.0,
                    ),
                    boxShadow: isSettled
                        ? [
                            BoxShadow(
                              color: Colors.tealAccent.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Book #$bookId",
                        style: TextStyle(
                          color: isSettled ? Colors.tealAccent : Colors.grey.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        currentNum,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                          shadows: isSettled
                              ? [const Shadow(color: Colors.tealAccent, blurRadius: 8)]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isSettled && winner != null)
                        Text(
                          _maskName(winner.buyerName),
                          style: const TextStyle(color: Colors.white70, fontSize: 10, overflow: TextOverflow.ellipsis),
                          textAlign: TextAlign.center,
                        )
                      else
                        const Text(
                          "Rolling...",
                          style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrandPrizeDrawState() {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Gold Title
              Text(
                "GRAND PRIZE DRAWING",
                style: TextStyle(
                  color: Colors.amber.shade400,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  shadows: [
                    Shadow(color: Colors.amber.shade900, blurRadius: 15),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Prize ${_currentGrandPrizeIndex + 1} of 5",
                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 36),

              // Giant Screen Card
              Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.amber.shade700, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.shade900.withOpacity(0.2),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Countdown overlay
                    if (_isCountingDown)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _countdownSeconds.toString(),
                            style: TextStyle(
                              color: Colors.amber.shade400,
                              fontSize: 100,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "SELECTING WINNER...",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "$_rollingGrandNumber - $_rollingGrandName",
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontFamily: 'monospace'),
                          ),
                        ],
                      )
                    // Winner reveal
                    else if (_revealedGrandWinner != null)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
                          const SizedBox(height: 16),
                          Text(
                            "TICKET #${_revealedGrandWinner!.ticketNumber.toString().padLeft(4, '0')}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _maskName(_revealedGrandWinner!.buyerName),
                            style: TextStyle(
                              color: Colors.amber.shade300,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Book #${_revealedGrandWinner!.bookId}",
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      )
                    // Waiting state
                    else
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.casino_outlined, size: 60, color: Colors.white38),
                          SizedBox(height: 16),
                          Text(
                            "READY TO DRAW",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Controls
              if (!_isCountingDown && _grandPrizeWinners.length < 5)
                SizedBox(
                  width: 250,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade600,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 6,
                    ),
                    onPressed: _drawNextGrandPrize,
                    icon: const Icon(Icons.play_arrow, size: 24),
                    label: Text(
                      _revealedGrandWinner == null ? "DRAW GRAND PRIZE" : "DRAW NEXT PRIZE",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1),
                    ),
                  ),
                ),

              const SizedBox(height: 48),

              // Progress Indicators showing drawn grand prizes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final isDrawn = index < _grandPrizeWinners.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDrawn ? Colors.amber.shade700 : const Color(0xFF1E293B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber.shade700, width: 2),
                    ),
                    child: Center(
                      child: isDrawn
                          ? const Icon(Icons.star, color: Colors.white, size: 20)
                          : Text(
                              (index + 1).toString(),
                              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                    ),
                  );
                }),
              ),

              if (_grandPrizeWinners.length == 5) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: 300,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSyncing ? null : _syncDrawResults,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done),
                    label: const Text(
                      "SYNC DRAW RESULTS TO CLOUD",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllFinishedState() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 850),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                const SizedBox(height: 16),
                const Text(
                  "LOTTERY SESSION COMPLETED!",
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                const Text(
                  "All prizes have been drawn and synchronized with Firestore.",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),

                // Grand Prize Winners Card
                const Text(
                  "🏆 GRAND PRIZE WINNERS 🏆",
                  style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _grandPrizeWinners.length,
                  itemBuilder: (context, index) {
                    final winner = _grandPrizeWinners[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Grand Prize #${index + 1}",
                            style: TextStyle(color: Colors.amber.shade200, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "Ticket #${winner.ticketNumber.toString().padLeft(4, '0')}",
                            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _maskName(winner.buyerName),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),
                const Text(
                  "🎟️ CONSOLATION WINNERS 🎟️",
                  style: TextStyle(color: Colors.tealAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.teal.shade800),
                  ),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _activeBookIds.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemBuilder: (context, index) {
                      final bookId = _activeBookIds[index];
                      final winner = _consolationWinners[bookId];
                      if (winner == null) return const SizedBox.shrink();
                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Book #$bookId",
                              style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Ticket #${winner.ticketNumber.toString().padLeft(4, '0')}",
                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _maskName(winner.buyerName),
                              style: const TextStyle(color: Colors.white70, fontSize: 9, overflow: TextOverflow.ellipsis),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentState = DrawState.idle;
                        _allSoldTickets.clear();
                      });
                    },
                    child: const Text("RESET & PREPARE FOR NEW SESSION", style: TextStyle(fontWeight: FontWeight.bold)),
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
