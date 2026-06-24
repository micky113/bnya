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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('tickets').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error loading tickets: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allTickets = snapshot.data!.docs.map((doc) {
            return Ticket.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList();

          // Sort tickets by number ascending
          allTickets.sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));

          // Metrics calculations
          final totalSold = allTickets.where((t) => t.isSold).length;
          final activeBooks = allTickets.where((t) => t.isSold).map((t) => t.bookId).toSet().length;
          final consolationWinners = allTickets.where((t) => t.hasWonConsolation).length;
          final grandWinners = allTickets.where((t) => t.hasWonGrandPrize).length;
          final totalPrizes = consolationWinners + grandWinners;

          // Apply filters and searches
          final filteredTickets = allTickets.where((ticket) {
            final query = _searchQuery.toLowerCase();
            final matchesSearch = ticket.buyerName.toLowerCase().contains(query) ||
                ticket.buyerPhone.contains(query) ||
                ticket.ticketNumber.toString().contains(query) ||
                ticket.bookId.toString().contains(query);

            if (!matchesSearch) return false;

            switch (_selectedFilter) {
              case "Sold":
                return ticket.isSold && !ticket.hasWonConsolation && !ticket.hasWonGrandPrize;
              case "Consolation":
                return ticket.hasWonConsolation;
              case "Grand":
                return ticket.hasWonGrandPrize;
              case "Winners":
                return ticket.hasWonConsolation || ticket.hasWonGrandPrize;
              default:
                return true;
            }
          }).toList();

          // Pagination logic
          final totalRows = filteredTickets.length;
          final totalPages = (totalRows / _rowsPerPage).ceil();
          final int startRow = (_currentPage - 1) * _rowsPerPage;
          int endRow = startRow + _rowsPerPage;
          if (endRow > totalRows) endRow = totalRows;

          final pageTickets = (totalRows > 0)
              ? filteredTickets.sublist(startRow, endRow)
              : <Ticket>[];

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Metrics Bar
                  _buildMetricsRow(totalSold, activeBooks, totalPrizes),
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
                          if (filteredTickets.isEmpty)
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
                            _buildResponsiveTable(pageTickets),
                            const SizedBox(height: 16),
                            _buildPaginationControls(totalPages, totalRows, startRow, endRow),
                          ]
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
              value: sold.toString(),
              subtitle: "Out of 20,000 maximum",
              icon: Icons.local_activity,
              color: const Color(0xFF00695C),
            ),
            _buildMetricCard(
              title: "ACTIVE BOOKS",
              value: books.toString(),
              subtitle: "Books with >=1 ticket sold",
              icon: Icons.menu_book,
              color: const Color(0xFF0277BD),
            ),
            _buildMetricCard(
              title: "PRIZES AWARDED",
              value: prizes.toString(),
              subtitle: "Consolation + Grand Prizes",
              icon: Icons.emoji_events,
              color: Colors.amber.shade800,
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Flex(
          direction: isMobile ? Axis.vertical : Axis.horizontal,
          children: [
            // Search Input
            Expanded(
              flex: isMobile ? 0 : 3,
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _currentPage = 1; // reset page on search
                  });
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
                            });
                          },
                        )
                      : null,
                  fillColor: Colors.grey.shade50,
                  filled: true,
                ),
              ),
            ),
            if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 16),
            // Filter Dropdown
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
                        _currentPage = 1; // reset page on filter change
                      });
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
            if (!isMobile) ...[
              const SizedBox(width: 16),
              // Rows per page dropdown
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
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _rowsPerPage = newValue;
                          _currentPage = 1;
                        });
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
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveTable(List<Ticket> pageTickets) {
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
                  "#${ticket.ticketNumber.toString().padLeft(4, '0')}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ),
              DataCell(
                Text(
                  "Book ${ticket.bookId}",
                  style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w500),
                ),
              ),
              DataCell(Text(ticket.buyerName)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Showing ${startRow + 1} to $endRow of $totalRows tickets",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                        });
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
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
