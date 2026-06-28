import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bnya/view/lottery/ticket_model.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AdminUploadScreen extends StatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ticketController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  final _csvController = TextEditingController();
  
  bool _isSavingSingle = false;
  bool _isUploadingBulk = false;
  double _bulkProgress = 0.0;
  String _bulkStatus = "";
  bool _isScanning = false;

  @override
  void dispose() {
    _ticketController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _csvController.dispose();
    super.dispose();
  }

  Future<String?> _showApiKeyDialog(String initialValue) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Gemini API Key Setup"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Enter your Gemini API Key. This will be securely saved in Firestore for all organizers.",
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "API Key",
                  hintText: "AIzaSy...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "You can get a free API key from Google AI Studio (aistudio.google.com).",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _getOrPromptApiKey() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('keys').get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['geminiApiKey'] != null && data['geminiApiKey'].toString().trim().isNotEmpty) {
          return data['geminiApiKey'].toString().trim();
        }
      }
    } catch (e) {
      debugPrint("Error fetching API key: $e");
    }

    if (!mounted) return null;
    final String? enteredKey = await _showApiKeyDialog("");

    if (enteredKey == null || enteredKey.isEmpty) {
      return null;
    }

    try {
      await FirebaseFirestore.instance.collection('config').doc('keys').set({
        'geminiApiKey': enteredKey,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving API key to Firestore: $e");
    }

    return enteredKey;
  }

  Future<void> _scanTicketPhoto() async {
    final apiKey = await _getOrPromptApiKey();
    if (!mounted) return;
    if (apiKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Scan cancelled: Gemini API key is required.")),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();
    XFile? imageFile;
    try {
      imageFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
    } catch (e) {
      imageFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
    }

    if (imageFile == null) return;

    setState(() => _isScanning = true);

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final uri = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey"
      );

      final prompt = "Analyze this physical lottery ticket image. Extract the ticket number(s) (which are numeric), "
          "the buyer's name, and the buyer's phone number. Provide the result strictly in JSON format with "
          "these exact keys: 'ticketNumbers' (list of integers), 'buyerName' (string), and 'buyerPhone' (string). "
          "If a field cannot be found, return empty list or empty string. Do not include markdown code block "
          "formatting (like ```json) in your response, return raw JSON string only.";

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
                {
                  "inlineData": {
                    "mimeType": "image/jpeg",
                    "data": base64Image,
                  }
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 429) {
        throw Exception("Rate limit exceeded (429). If you are using the Gemini free tier, please wait a minute before scanning again or check your API key quota on Google AI Studio.");
      } else if (response.statusCode != 200) {
        throw Exception("API returned status code ${response.statusCode}. Please check that your API Key is valid.");
      }

      final responseData = jsonDecode(response.body);
      final String textContent = responseData['candidates'][0]['content']['parts'][0]['text'] ?? '';
      
      String cleanedText = textContent.trim();
      if (cleanedText.startsWith("```")) {
        cleanedText = cleanedText.substring(3);
        if (cleanedText.startsWith("json")) {
          cleanedText = cleanedText.substring(4);
        }
      }
      if (cleanedText.endsWith("```")) {
        cleanedText = cleanedText.substring(0, cleanedText.length - 3);
      }
      cleanedText = cleanedText.trim();

      final parsed = jsonDecode(cleanedText) as Map<String, dynamic>;

      final List<dynamic> tNumsList = parsed['ticketNumbers'] ?? [];
      final String name = parsed['buyerName'] ?? '';
      final String phone = parsed['buyerPhone'] ?? '';

      final String tNumsStr = tNumsList.map((e) => e.toString()).join(", ");

      if (mounted) {
        setState(() {
          if (tNumsStr.isNotEmpty) _ticketController.text = tNumsStr;
          if (name.isNotEmpty) _nameController.text = name;
          if (phone.isNotEmpty) _phoneController.text = phone;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Scan complete! Please review and save."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Scan failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // Save single ticket with duplication checks
  Future<void> _saveSingleTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingSingle = true);

    try {
      final String name = _nameController.text.trim();
      final String phone = _phoneController.text.trim();

      // Parse ticket numbers using robust regex range parser
      final List<int> ticketNums = _parseTicketNumbers(_ticketController.text);

      final List<int> uniqueNums = ticketNums.toSet().toList();

      if (uniqueNums.isEmpty) {
        setState(() => _isSavingSingle = false);
        return;
      }

      // Duplication check in Firestore in parallel
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final List<DocumentSnapshot> docSnaps = await Future.wait(
        uniqueNums.map((n) => firestore.collection('tickets').doc(n.toString()).get())
      );

      final List<int> existingTickets = [];
      for (final snap in docSnaps) {
        if (snap.exists) {
          final int? existingNum = int.tryParse(snap.id);
          if (existingNum != null) {
            existingTickets.add(existingNum);
          }
        }
      }

      if (existingTickets.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: Ticket(s) #${existingTickets.join(', ')} already registered!"),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSavingSingle = false);
        return;
      }

      // Write tickets in a batch write
      final WriteBatch batch = firestore.batch();
      for (final n in uniqueNums) {
        final int bookId = ((n - 1) ~/ 100) + 1;
        final ticket = Ticket(
          ticketNumber: n,
          bookId: bookId,
          buyerName: name,
          buyerPhone: phone,
          isSold: true,
        );
        final docRef = firestore.collection('tickets').doc(n.toString());
        batch.set(docRef, ticket.toMap());
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ticket(s) #${uniqueNums.join(', ')} successfully registered!"),
            backgroundColor: Colors.green,
          ),
        );
        _ticketController.clear();
        _nameController.clear();
        _phoneController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to register tickets: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSingle = false);
    }
  }

  // Bulk Upload logic via Firestore batch writes
  Future<void> _uploadBulkTickets() async {
    final String csvText = _csvController.text.trim();
    if (csvText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter or generate CSV data first.")),
      );
      return;
    }

    setState(() {
      _isUploadingBulk = true;
      _bulkProgress = 0.0;
      _bulkStatus = "Parsing CSV data...";
    });

    try {
      final List<String> lines = csvText.split('\n');
      final List<Ticket> parsedTickets = [];

      for (String line in lines) {
        if (line.trim().isEmpty) continue;
        final List<String> parts = line.split(',');
        if (parts.length >= 4) {
          final int? tNum = int.tryParse(parts[0].trim());
          final int? bId = int.tryParse(parts[1].trim());
          final String name = parts[2].trim();
          final String phone = parts[3].trim();

          if (tNum != null && tNum >= 1 && tNum <= 20000 && bId != null) {
            parsedTickets.add(Ticket(
              ticketNumber: tNum,
              bookId: bId,
              buyerName: name,
              buyerPhone: phone,
              isSold: true,
            ));
          }
        } else if (parts.length == 3) {
          final int? tNum = int.tryParse(parts[0].trim());
          final String name = parts[1].trim();
          final String phone = parts[2].trim();

          if (tNum != null && tNum >= 1 && tNum <= 20000) {
            parsedTickets.add(Ticket(
              ticketNumber: tNum,
              bookId: ((tNum - 1) ~/ 100) + 1,
              buyerName: name,
              buyerPhone: phone,
              isSold: true,
            ));
          }
        }
      }

      if (parsedTickets.isEmpty) {
        throw Exception("No valid rows could be parsed. Format: ticketNumber,bookId,buyerName,buyerPhone OR ticketNumber,buyerName,buyerPhone");
      }

      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      int batchSize = 500;
      int total = parsedTickets.length;

      for (int i = 0; i < total; i += batchSize) {
        final WriteBatch batch = firestore.batch();
        final int end = (i + batchSize < total) ? i + batchSize : total;

        setState(() {
          _bulkStatus = "Uploading tickets ${i + 1} to $end of $total...";
          _bulkProgress = i / total;
        });

        for (int j = i; j < end; j++) {
          final ticket = parsedTickets[j];
          final docRef = firestore.collection('tickets').doc(ticket.ticketNumber.toString());
          batch.set(docRef, ticket.toMap());
        }

        await batch.commit();
      }

      setState(() {
        _bulkProgress = 1.0;
        _bulkStatus = "Successfully uploaded $total tickets!";
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Successfully uploaded $total tickets in batches!"),
            backgroundColor: Colors.green,
          ),
        );
        _csvController.clear();
      }
    } catch (e) {
      setState(() {
        _bulkStatus = "Upload failed: $e";
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bulk upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingBulk = false;
        });
      }
    }
  }

  // Helper to generate mock data for quick testing
  void _generateMockCSV() {
    final List<String> mockNames = [
      "Amit Kumar", "Priya Sharma", "Rajesh Patel", "Siddharth Das",
      "Ananya Sen", "Vikram Singh", "Sunita Rao", "Deepak Gupta",
      "Nehal Joshi", "Rohan Mehta", "Manish Pandey", "Sneha Nair"
    ];
    
    final StringBuffer sb = StringBuffer();
    // Generate 500 random tickets starting from a random index (within 1 to 20000 range)
    final double startingNumber = (1 + (19500 * (DateTime.now().millisecond / 1000))).floorToDouble();
    int start = startingNumber.toInt();

    for (int i = 0; i < 500; i++) {
      final int ticketNum = start + i;
      if (ticketNum > 20000) break;
      final int bookId = ((ticketNum - 1) ~/ 100) + 1;
      final String name = mockNames[i % mockNames.length] + " ${100 + i}";
      final String phone = "98765${(10000 + i).toString().substring(1)}";
      sb.writeln("$ticketNum,$bookId,$name,$phone");
    }

    setState(() {
      _csvController.text = sb.toString();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Generated 500 mock tickets inside CSV workspace.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FA),
      appBar: AppBar(
        title: const Text(
          "Admin Ticket Registration",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00695C),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Card(
                color: const Color(0xFF00695C),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white24,
                        radius: isMobile ? 22 : 28,
                        child: Icon(Icons.app_registration, color: Colors.white, size: isMobile ? 24 : 30),
                      ),
                      SizedBox(width: isMobile ? 12 : 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Lottery Registration Panel",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 18 : 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isMobile
                                  ? "Register sold tickets. Range: 1 - 20,000. Book ID is automatic."
                                  : "Register sold tickets into Cloud Firestore. Tickets range from 1 to 20,000. Book ID is automatically calculated.",
                              style: TextStyle(
                                color: Colors.teal.shade100,
                                fontSize: isMobile ? 12 : 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Forms Layout
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: _buildManualFormCard()),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: _buildBulkUploadCard()),
                  ],
                )
              else
                Column(
                  children: [
                    _buildManualFormCard(),
                    const SizedBox(height: 24),
                    _buildBulkUploadCard(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualFormCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1, color: Color(0xFF0277BD)),
                  const SizedBox(width: 10),
                  const Text(
                    "Manual Single Registration",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () async {
                      final doc = await FirebaseFirestore.instance.collection('config').doc('keys').get();
                      final currentKey = doc.exists ? (doc.data()?['geminiApiKey']?.toString() ?? '') : '';
                      if (!mounted) return;
                      final String? enteredKey = await _showApiKeyDialog(currentKey);
                      if (enteredKey != null) {
                        await FirebaseFirestore.instance.collection('config').doc('keys').set({
                          'geminiApiKey': enteredKey,
                        }, SetOptions(merge: true));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Gemini API Key updated successfully!")),
                        );
                      }
                    },
                    tooltip: "Configure Gemini API Key",
                    icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFF00695C)),
                  ),
                  IconButton(
                    onPressed: _isScanning ? null : _scanTicketPhoto,
                    tooltip: "Scan Physical Ticket via AI",
                    icon: _isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00695C)),
                          )
                        : const Icon(Icons.camera_alt_outlined, color: Color(0xFF00695C)),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Ticket Number field
              const Text(
                "Ticket Number(s) (1 - 20000, comma-separated)",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _ticketController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  hintText: "e.g. 1542, 1545, 1600",
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Ticket number(s) required";
                  }
                  final tickets = _parseTicketNumbers(value);
                  if (tickets.isEmpty) {
                    return "Please enter valid ticket number(s) or range (e.g. A2001-A2010)";
                  }
                  for (final num in tickets) {
                    if (num < 1 || num > 20000) {
                      return "Ticket numbers must be between 1 and 20,000 (invalid: #$num)";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Buyer Name field
              const Text(
                "Buyer's Full Name",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: "Enter buyer's name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Buyer name is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Buyer Phone field
              const Text(
                "Buyer's Phone Number",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: "Enter 10-digit phone number",
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Phone number is required";
                  }
                  if (value.trim().length < 8) {
                    return "Enter a valid phone number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSavingSingle ? null : _saveSingleTicket,
                  icon: _isSavingSingle
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text(
                    "REGISTER TICKET",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulkUploadCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cloud_upload_outlined, color: Color(0xFF0277BD)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Bulk CSV Upload",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _isUploadingBulk ? null : _generateMockCSV,
                        icon: const Icon(Icons.build_outlined, size: 16),
                        label: const Text("Generate Mock CSV"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0277BD),
                          side: const BorderSide(color: Color(0xFF0277BD)),
                        ),
                      )
                    ],
                  )
                : Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined, color: Color(0xFF0277BD)),
                      const SizedBox(width: 10),
                      const Text(
                        "Bulk CSV Upload Simulation",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _isUploadingBulk ? null : _generateMockCSV,
                        icon: const Icon(Icons.build_outlined, size: 16),
                        label: const Text("Generate Mock CSV"),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0277BD),
                        ),
                      )
                    ],
                  ),
            const Divider(height: 24),
            const Text(
              "Paste CSV rows in the format: ticketNumber, buyerName, buyerPhone (one per line)",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),

            // CSV Input area
            TextField(
              controller: _csvController,
              maxLines: 8,
              enabled: !_isUploadingBulk,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: "e.g.\n1,Amit Kumar,9876543210\n2,Priya Sharma,9876543211\n105,Vikram Singh,9876543212",
                fillColor: Colors.grey.shade50,
                filled: true,
              ),
            ),
            const SizedBox(height: 20),

            // Bulk Progress/Status indicator
            if (_isUploadingBulk || _bulkStatus.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0277BD).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _bulkStatus,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0277BD).withOpacity(0.9),
                          ),
                        ),
                        const Spacer(),
                        if (_isUploadingBulk)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _bulkProgress,
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFF0277BD),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0277BD),
                  side: const BorderSide(color: Color(0xFF0277BD), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isUploadingBulk ? null : _uploadBulkTickets,
                icon: const Icon(Icons.publish),
                label: const Text(
                  "START BULK BATCH WRITE",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<int> _parseTicketNumbers(String input) {
  final List<int> results = [];
  final parts = input.split(',');
  for (var part in parts) {
    part = part.trim();
    if (part.isEmpty) continue;

    final rangeMatch = RegExp(r'[a-zA-Z]*\s*(\d+)\s*(?:-|to)\s*[a-zA-Z]*\s*(\d+)').firstMatch(part);
    if (rangeMatch != null) {
      final start = int.tryParse(rangeMatch.group(1)!) ?? 0;
      final end = int.tryParse(rangeMatch.group(2)!) ?? 0;
      if (start > 0 && end >= start) {
        for (int i = start; i <= end; i++) {
          results.add(i);
        }
      }
    } else {
      final numberMatch = RegExp(r'\d+').firstMatch(part);
      if (numberMatch != null) {
        final numVal = int.tryParse(numberMatch.group(0)!) ?? 0;
        if (numVal > 0) {
          results.add(numVal);
        }
      }
    }
  }
  return results.toSet().toList();
}
