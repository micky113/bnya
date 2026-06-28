import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bnya/view/lottery/ticket_model.dart';

class TicketDirectoryScreen extends StatefulWidget {
  const TicketDirectoryScreen({super.key});

  @override
  State<TicketDirectoryScreen> createState() => _TicketDirectoryScreenState();
}

class _TicketDirectoryScreenState extends State<TicketDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFilter = "All"; // All, Sold, Consolation, Grand, Winners
  int _currentPage = 1;
  int _rowsPerPage = 10;

  bool _isLoadingAllPage = false;
  bool _isLoadingMetrics = false;
  List<Ticket> _allTicketsPage = []; // Current page tickets
  int _totalAllCount = 0; // Total matching tickets count

  int _totalSold = 0;
  int _activeBooks = 0;
  int _totalPrizes = 0;

  final List<DocumentSnapshot> _pageStartDocs = [];

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    _loadTicketsPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    if (mounted) {
      setState(() {
        _isLoadingMetrics = true;
      });
    }

    try {
      final firestore = FirebaseFirestore.instance;

      // Parallelized index-free count queries
      final results = await Future.wait([
        firestore.collection('tickets').where('isSold', isEqualTo: true).count().get(),
        firestore.collection('tickets').where('hasWonConsolation', isEqualTo: true).count().get(),
        firestore.collection('tickets').where('hasWonGrandPrize', isEqualTo: true).count().get(),
      ]);

      final soldCount = results[0].count ?? 0;
      final consolationCount = results[1].count ?? 0;
      final grandCount = results[2].count ?? 0;

      // Active Books logic:
      // If consolation winner draws have run, activeBooks matches consolation winners count.
      // Else, estimate active books mathematically based on soldCount.
      int activeBooksCount = consolationCount;
      if (activeBooksCount == 0 && soldCount > 0) {
        activeBooksCount = (soldCount / 100).ceil().clamp(1, 200);
      }

      if (mounted) {
        setState(() {
          _totalSold = soldCount;
          _activeBooks = activeBooksCount;
          _totalPrizes = consolationCount + grandCount;
          _isLoadingMetrics = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading metrics: $e");
      if (mounted) {
        setState(() {
          _isLoadingMetrics = false;
        });
      }
    }
  }

  Future<void> _loadTicketsPage() async {
    if (mounted) {
      setState(() {
        _isLoadingAllPage = true;
      });
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final term = _searchQuery.trim().toLowerCase();
      final hasSearch = term.isNotEmpty;

      // Case A: Default view (No active text search query)
      if (!hasSearch) {
        Query query = firestore.collection('tickets');

        if (_selectedFilter == "Sold") {
          query = query.where('isSold', isEqualTo: true);
        } else if (_selectedFilter == "Consolation") {
          query = query.where('hasWonConsolation', isEqualTo: true);
        } else if (_selectedFilter == "Grand") {
          query = query.where('hasWonGrandPrize', isEqualTo: true);
        }

        // Fetch all consolation/grand/winners in memory for simple client pagination (since counts are small)
        if (_selectedFilter == "Winners") {
          final results = await Future.wait([
            firestore.collection('tickets').where('hasWonConsolation', isEqualTo: true).get(),
            firestore.collection('tickets').where('hasWonGrandPrize', isEqualTo: true).get(),
          ]);
          final List<DocumentSnapshot> docs = [];
          docs.addAll(results[0].docs);
          docs.addAll(results[1].docs);

          var allMatched = docs.map((doc) => Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
          final Map<int, Ticket> uniqueMap = {};
          for (var t in allMatched) {
            uniqueMap[t.ticketNumber] = t;
          }
          allMatched = uniqueMap.values.toList();
          allMatched.sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));

          if (mounted) {
            setState(() {
              _totalAllCount = allMatched.length;
              final int startRow = (_currentPage - 1) * _rowsPerPage;
              int endRow = startRow + _rowsPerPage;
              if (endRow > _totalAllCount) endRow = _totalAllCount;

              _allTicketsPage = (startRow < _totalAllCount) ? allMatched.sublist(startRow, endRow) : [];
              _isLoadingAllPage = false;
            });
          }
          return;
        } else if (_selectedFilter == "Consolation" || _selectedFilter == "Grand") {
          final snap = await query.get();
          var allMatched = snap.docs.map((doc) => Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
          allMatched.sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));

          if (mounted) {
            setState(() {
              _totalAllCount = allMatched.length;
              final int startRow = (_currentPage - 1) * _rowsPerPage;
              int endRow = startRow + _rowsPerPage;
              if (endRow > _totalAllCount) endRow = _totalAllCount;

              _allTicketsPage = (startRow < _totalAllCount) ? allMatched.sublist(startRow, endRow) : [];
              _isLoadingAllPage = false;
            });
          }
          return;
        }

        // Standard paginated list for "All" or "Sold" categories
        final countSnap = await query.count().get();
        final totalCount = countSnap.count ?? 0;

        query = query.orderBy('ticketNumber');

        if (_currentPage > 1 && _pageStartDocs.length >= _currentPage - 1) {
          query = query.startAfterDocument(_pageStartDocs[_currentPage - 2]);
        }

        final snap = await query.limit(_rowsPerPage).get();

        if (mounted) {
          setState(() {
            _totalAllCount = totalCount;
            _allTicketsPage = snap.docs.map((doc) {
              return Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id);
            }).toList();

            if (snap.docs.isNotEmpty) {
              final lastDoc = snap.docs.last;
              if (_pageStartDocs.length < _currentPage) {
                _pageStartDocs.add(lastDoc);
              } else {
                _pageStartDocs[_currentPage - 1] = lastDoc;
              }
            }
            _isLoadingAllPage = false;
          });
        }
      }
      // Case B: Search Query Active (perform server-side target lookup)
      else {
        final cleanNumeric = term.replaceAll(RegExp(r'[^0-9]'), '');
        final intVal = int.tryParse(cleanNumeric);
        List<DocumentSnapshot> docs = [];

        final List<Future<dynamic>> futures = [];

        // 1. Ticket Number exact match
        if (intVal != null && intVal >= 1 && intVal <= 20000) {
          futures.add(firestore.collection('tickets').doc(intVal.toString()).get());
        }

        // 2. Book ID match
        if (intVal != null && intVal >= 1 && intVal <= 200) {
          if (term.contains('b') || term.contains('book')) {
            futures.add(
              firestore.collection('tickets')
                  .where('bookId', isEqualTo: intVal)
                  .limit(100)
                  .get()
            );
          }
        }

        // 3. Phone number prefix/exact match
        if (cleanNumeric.isNotEmpty && cleanNumeric.length >= 3) {
          futures.add(
            firestore.collection('tickets')
                .where('buyerPhone', isGreaterThanOrEqualTo: cleanNumeric)
                .where('buyerPhone', isLessThanOrEqualTo: '$cleanNumeric\uf8ff')
                .limit(100)
                .get()
          );
        }

        // 4. Buyer Name prefix match (if term contains letters or cleanNumeric is short)
        final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(term);
        if (hasLetters || cleanNumeric.isEmpty || (cleanNumeric.length < 3 && term.isNotEmpty)) {
          final queryTerm = _searchQuery.trim();
          if (queryTerm.isNotEmpty) {
            futures.add(
              firestore.collection('tickets')
                  .where('buyerName', isGreaterThanOrEqualTo: queryTerm)
                  .where('buyerName', isLessThanOrEqualTo: '$queryTerm\uf8ff')
                  .limit(100)
                  .get()
            );

            // Search with capitalized version
            final capitalized = '${queryTerm[0].toUpperCase()}${queryTerm.substring(1)}';
            if (capitalized != queryTerm) {
              futures.add(
                firestore.collection('tickets')
                    .where('buyerName', isGreaterThanOrEqualTo: capitalized)
                    .where('buyerName', isLessThanOrEqualTo: '$capitalized\uf8ff')
                    .limit(100)
                    .get()
              );
            }

            // Search lowercase version
            final lowercase = queryTerm.toLowerCase();
            if (lowercase != queryTerm && lowercase != capitalized) {
              futures.add(
                firestore.collection('tickets')
                    .where('buyerName', isGreaterThanOrEqualTo: lowercase)
                    .where('buyerName', isLessThanOrEqualTo: '$lowercase\uf8ff')
                    .limit(100)
                    .get()
              );
            }
          }
        }

        final results = await Future.wait(futures);
        for (final res in results) {
          if (res is DocumentSnapshot) {
            if (res.exists) {
              docs.add(res);
            }
          } else if (res is QuerySnapshot) {
            docs.addAll(res.docs);
          }
        }

        var allMatched = docs.map((doc) => Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
        final Map<int, Ticket> uniqueMap = {};
        for (var t in allMatched) {
          uniqueMap[t.ticketNumber] = t;
        }
        allMatched = uniqueMap.values.toList();
        allMatched.sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));

        // Filter search results dynamically by status category in memory
        if (_selectedFilter == "Sold") {
          allMatched = allMatched.where((t) => t.isSold && !t.hasWonConsolation && !t.hasWonGrandPrize).toList();
        } else if (_selectedFilter == "Consolation") {
          allMatched = allMatched.where((t) => t.hasWonConsolation).toList();
        } else if (_selectedFilter == "Grand") {
          allMatched = allMatched.where((t) => t.hasWonGrandPrize).toList();
        } else if (_selectedFilter == "Winners") {
          allMatched = allMatched.where((t) => t.hasWonConsolation || t.hasWonGrandPrize).toList();
        }

        if (mounted) {
          setState(() {
            _totalAllCount = allMatched.length;
            final int startRow = (_currentPage - 1) * _rowsPerPage;
            int endRow = startRow + _rowsPerPage;
            if (endRow > _totalAllCount) endRow = _totalAllCount;

            _allTicketsPage = (startRow < _totalAllCount) ? allMatched.sublist(startRow, endRow) : [];
            _isLoadingAllPage = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading tickets page: $e");
      if (mounted) {
        setState(() {
          _isLoadingAllPage = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDefaultAll = _selectedFilter == "All" && _searchQuery.isEmpty;
    final totalPages = (_totalAllCount / _rowsPerPage).ceil();
    final int startRow = (_currentPage - 1) * _rowsPerPage;
    int endRow = startRow + _rowsPerPage;
    if (endRow > _totalAllCount) endRow = _totalAllCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FA),
      appBar: AppBar(
        title: const Text(
          "Ticket Directory Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00695C),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Metrics & List",
            onPressed: () {
              _loadMetrics();
              _loadTicketsPage();
            },
          ),
        ],
      ),
      body: _isLoadingMetrics && _allTicketsPage.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Metrics Bar
                    _buildMetricsRow(_totalSold, _activeBooks, _totalPrizes),
                    const SizedBox(height: 24),

                    // Search and Filter Bar
                    _buildSearchFilterRow(),
                    const SizedBox(height: 16),

                    // Main Data Table Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isLoadingAllPage && isDefaultAll)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48.0),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (_allTicketsPage.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48.0),
                                child: Center(
                                  child: Text(
                                    "No matching ticket records found.",
                                    style: TextStyle(color: Colors.grey, fontSize: 16),
                                  ),
                                ),
                              )
                            else ...[
                              _buildResponsiveTable(_allTicketsPage),
                              const SizedBox(height: 16),
                              _buildPaginationControls(totalPages, _totalAllCount, startRow, endRow),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMetricsRow(int sold, int books, int prizes) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: isMobile ? 1 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: isMobile ? 2.5 : 2.8,
          children: [
            _buildMetricCard(
              title: "TOTAL TICKETS SOLD",
              value: "$sold",
              subtitle: "Active participants",
              icon: Icons.confirmation_number,
              color: const Color(0xFF00695C),
            ),
            _buildMetricCard(
              title: "ACTIVE BOOKS",
              value: "$books",
              subtitle: "Book groups active",
              icon: Icons.book,
              color: const Color(0xFF0277BD),
            ),
            _buildMetricCard(
              title: "TOTAL PRIZES AWARDED",
              value: "$prizes",
              subtitle: "Winners drawn",
              icon: Icons.emoji_events,
              color: const Color(0xFFD84315),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 6)),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 20,
              child: Icon(icon, color: color, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchFilterRow() {
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (isMobile) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _currentPage = 1;
                    _pageStartDocs.clear();
                  });
                  _loadTicketsPage();
                },
                decoration: InputDecoration(
                  hintText: "Search by Name, Phone, Ticket # or Book ID...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = "";
                              _currentPage = 1;
                              _pageStartDocs.clear();
                            });
                            _loadTicketsPage();
                          },
                        )
                      : null,
                  fillColor: Colors.grey.shade50,
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFilter,
                    isExpanded: true,
                    icon: const Icon(Icons.filter_list, color: Color(0xFF00695C)),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedFilter = newValue;
                          _currentPage = 1;
                          _pageStartDocs.clear();
                        });
                        _loadTicketsPage();
                      }
                    },
                    items: <String>[
                      'All',
                      'Sold',
                      'Consolation',
                      'Grand',
                      'Winners'
                    ].map<DropdownMenuItem<String>>((String value) {
                      String display = value;
                      if (value == "Sold") display = "Sold (No Prizes)";
                      if (value == "Consolation") display = "Consolation Winners";
                      if (value == "Grand") display = "Grand Prize Winners";
                      if (value == "Winners") display = "All Winners";
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          display,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _rowsPerPage,
                    isExpanded: true,
                    icon: const Icon(Icons.format_list_numbered, color: Color(0xFF00695C)),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _rowsPerPage = newValue;
                          _currentPage = 1;
                          _pageStartDocs.clear();
                        });
                        _loadTicketsPage();
                      }
                    },
                    items: <int>[5, 10, 25, 50].map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text("$value rows"),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _currentPage = 1;
                    _pageStartDocs.clear();
                  });
                  _loadTicketsPage();
                },
                decoration: InputDecoration(
                  hintText: "Search by Name, Phone, Ticket # or Book ID...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = "";
                              _currentPage = 1;
                              _pageStartDocs.clear();
                            });
                            _loadTicketsPage();
                          },
                        )
                      : null,
                  fillColor: Colors.grey.shade50,
                  filled: true,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFilter,
                  icon: const Icon(Icons.filter_list, color: Color(0xFF00695C)),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedFilter = newValue;
                        _currentPage = 1;
                        _pageStartDocs.clear();
                      });
                      _loadTicketsPage();
                    }
                  },
                  items: <String>[
                    'All',
                    'Sold',
                    'Consolation',
                    'Grand',
                    'Winners'
                  ].map<DropdownMenuItem<String>>((String value) {
                    String display = value;
                    if (value == "Sold") display = "Sold (No Prizes)";
                    if (value == "Consolation") display = "Consolation Winners";
                    if (value == "Grand") display = "Grand Prize Winners";
                    if (value == "Winners") display = "All Winners";
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        display,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _rowsPerPage,
                  icon: const Icon(Icons.format_list_numbered, color: Color(0xFF00695C)),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _rowsPerPage = newValue;
                        _currentPage = 1;
                        _pageStartDocs.clear();
                      });
                      _loadTicketsPage();
                    }
                  },
                  items: <int>[5, 10, 25, 50].map<DropdownMenuItem<int>>((int value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text("$value rows"),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveTable(
    List<Ticket> pageTickets,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 36,
        headingRowColor: WidgetStateProperty.all(const Color(0xFF00695C).withOpacity(0.05)),
        columns: const [
          DataColumn(
            label: Text("Ticket #", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00695C))),
          ),
          DataColumn(
            label: Text("Book ID", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00695C))),
          ),
          DataColumn(
            label: Text("Buyer Name", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00695C))),
          ),
          DataColumn(
            label: Text("Phone Number", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00695C))),
          ),
          DataColumn(
            label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00695C))),
          ),
        ],
        rows: pageTickets.map((ticket) {
          return DataRow(
            cells: [
              DataCell(
                Text(
                  "#${Ticket.formatNumber(ticket.ticketNumber)}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ),
              DataCell(
                Text(
                  "Book ${ticket.bookId}",
                  style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w500),
                ),
              ),
              DataCell(
                Text(ticket.buyerName),
              ),
              DataCell(
                Text(
                  ticket.buyerPhone,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              DataCell(_buildStatusBadge(ticket)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusBadge(Ticket ticket) {
    Color bgColor;
    Color textColor;
    String text;

    if (ticket.hasWonGrandPrize) {
      bgColor = Colors.amber.shade100;
      textColor = Colors.amber.shade900;
      text = "🏆 Won Grand Prize";
    } else if (ticket.hasWonConsolation) {
      bgColor = Colors.indigo.shade50;
      textColor = Colors.indigo.shade800;
      text = "🎟️ Won Consolation";
    } else if (ticket.isSold) {
      bgColor = Colors.teal.shade50;
      textColor = Colors.teal.shade800;
      text = "Sold";
    } else {
      bgColor = Colors.grey.shade100;
      textColor = Colors.grey.shade800;
      text = "Unsold";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildPaginationControls(int totalPages, int totalRows, int startRow, int endRow) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() {
                            _currentPage--;
                          });
                          _loadTicketsPage();
                        }
                      : null,
                ),
                Text(
                  "Page $_currentPage of $totalPages",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < totalPages
                      ? () {
                          setState(() {
                            _currentPage++;
                          });
                          _loadTicketsPage();
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Showing ${startRow + 1} to $endRow of $totalRows tickets",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Showing ${startRow + 1} to $endRow of $totalRows tickets",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                        });
                        _loadTicketsPage();
                      }
                    : null,
              ),
              Text(
                "Page $_currentPage of $totalPages",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages
                    ? () {
                        setState(() {
                          _currentPage++;
                        });
                        _loadTicketsPage();
                      }
                    : null,
              ),
            ],
          ),
          const Expanded(
            child: SizedBox(),
          ),
        ],
      ),
    );
  }
}
