import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data'; // Added for Uint8List
import 'package:bnya/widgets/add_contributor_dialog/add_contributor_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bnya/data/models/contributor/contributor.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class ContributorMapScreen extends StatefulWidget {
  const ContributorMapScreen({super.key});

  @override
  State<ContributorMapScreen> createState() => _ContributorMapScreenState();
}

class _ContributorMapScreenState extends State<ContributorMapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  MapType _currentMapType = MapType.normal;
  bool _isLocating = false;
  
  // This controls the "Blue Dot". We default to false, 
  // but we will try to set it to true in initState.
  bool _canShowBlueDot = false; 

  // --- ADD MODE LOGIC ---
  bool _isAddMode = false;
  LatLng _screenCenter = const LatLng(20.2613, 85.8344); // Track center

  // Custom Marker Icons
  BitmapDescriptor? _greenMarkerIcon;
  BitmapDescriptor? _redMarkerIcon;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(20.2613, 85.8344),
    zoom: 17.5,
  );

  final NumberFormat _currency = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 0,
    locale: 'en_IN',
  );

  final List<String> _paymentTypes = [
    'Kalash',
    'Coupon',
    'SBI',
    'HDFC',
    'Others',
  ];
  final List<String> _adminEmails = [
    "mohanty747@gmail.com",
    "treasurer@society.com",
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomMarkers();
    
    // --- UPDATED: Automatically ask for permission & show location on load ---
    _zoomToMyLocation(); 
  }

  // --- 1. IMAGE LOADER ---
  Future<BitmapDescriptor> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    ui.FrameInfo fi = await codec.getNextFrame();
    return BitmapDescriptor.fromBytes(
      (await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
  }

  Future<void> _loadCustomMarkers() async {
    try {
      final green = await getBytesFromAsset('images/green_marker.png', 100);
      final red = await getBytesFromAsset('images/red_marker.png', 100);
      if (mounted) {
        setState(() {
          _greenMarkerIcon = green;
          _redMarkerIcon = red;
        });
      }
    } catch (e) {
      print("Error loading markers: $e");
    }
  }

  // --- 2. GPS LOCATION ---
  Future<void> _zoomToMyLocation() async {
    setState(() => _isLocating = true);
    
    // 1. Check Service
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack("Please enable Location Services");
      setState(() => _isLocating = false);
      return;
    }

    // 2. Check/Request Permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnack("Location permission denied");
        setState(() => _isLocating = false);
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      _showSnack("Location permission permanently denied");
      setState(() => _isLocating = false);
      return;
    }

    // 3. Enable Blue Dot
    setState(() => _canShowBlueDot = true);

    try {
      // 4. Get Position and Move Camera
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 19.0,
          ),
        ),
      );
    } catch (e) {
      _showSnack("Weak GPS Signal. Try outdoors.");
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  // --- 3. BUILD UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Locality Map"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance.collection('contributors').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final contributors =
              snapshot.data!.docs
                  .map((doc) => Contributor.fromFirestore(doc))
                  .toList();
          final unmappedContributors =
              contributors.where((c) => c.location == null).toList();

          Set<Marker> markers = {};
          final int currentYear = DateTime.now().year;

          for (var c in contributors) {
            if (c.location != null) {
              double paid = c.getYearTotal(currentYear);
              double pending = c.targetAmount - paid;
              bool isPaid = pending < 1.0;
              BitmapDescriptor iconToUse = BitmapDescriptor.defaultMarker;
              if (_greenMarkerIcon != null && _redMarkerIcon != null) {
                iconToUse = isPaid ? _greenMarkerIcon! : _redMarkerIcon!;
              }

              markers.add(
                Marker(
                  markerId: MarkerId(c.id),
                  position: LatLng(c.location!.latitude, c.location!.longitude),
                  icon: iconToUse,
                  // --- LOCKED: NOT DRAGGABLE ---
                  draggable: false,
                  infoWindow: InfoWindow(
                    title: c.name,
                    snippet: isPaid ? "Paid" : "Due: ₹${pending.toInt()}",
                  ),
                  onTap: () {
                    Future.delayed(const Duration(milliseconds: 100), () {
                      _showContributorDetails(context, c);
                    });
                  },
                ),
              );
            }
          }

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: _initialCameraPosition,
                markers: markers,
                mapType: _currentMapType,
                // --- THIS ENABLES THE BLUE DOT ---
                myLocationEnabled: _canShowBlueDot, 
                // We disable the default button because we made a custom one
                myLocationButtonEnabled: false, 
                zoomControlsEnabled: false,
                compassEnabled: true,
                onMapCreated: (GoogleMapController controller) {
                  _controller.complete(controller);
                },
                onCameraMove: (position) {
                  // Track center of screen constantly
                  _screenCenter = position.target;
                },
              ),

              // --- TARGET CROSSHAIR (Only in Add Mode) ---
              if (_isAddMode)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: 40,
                    ), // Offset for pin height
                    child: Icon(
                      Icons.add_location_alt,
                      size: 50,
                      color: Colors.black87,
                    ),
                  ),
                ),

              if (_isAddMode)
                Positioned(
                  top: 10,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[800],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: const Text(
                      "Drag map to place Target",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // --- LEGEND ---
              Positioned(
                bottom: 30,
                left: 20,
                right: 80,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _legendItem('images/red_marker.png', Colors.red),
                      const Text(
                        " Pending",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _legendItem('images/green_marker.png', Colors.green),
                      const Text(
                        " Paid",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // --- BUTTONS ---
              Positioned(
                top: 20,
                right: 20,
                child: FloatingActionButton.small(
                  heroTag: "map_type",
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green[800],
                  onPressed:
                      () => setState(
                        () =>
                            _currentMapType =
                                _currentMapType == MapType.normal
                                    ? MapType.hybrid
                                    : MapType.normal,
                      ),
                  child: Icon(
                    _currentMapType == MapType.normal
                        ? Icons.satellite_alt
                        : Icons.map,
                  ),
                ),
              ),

              // ADD MODE BUTTONS
              Positioned(
                bottom: 100,
                right: 20,
                child: Column(
                  children: [
                    // CONFIRM BUTTON (Only shows when in Add Mode)
                    if (_isAddMode) ...[
                      FloatingActionButton.extended(
                        heroTag: "confirm_btn",
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.check),
                        label: const Text("PLACE HERE"),
                        onPressed: () {
                          // 1. Turn off add mode
                          setState(() => _isAddMode = false);

                          // 2. Open the NEW Contributor Dialog
                          // Passing the _screenCenter (LatLng) so we can save the location
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder:
                                (ctx) => AddContributorDialog(
                                  location: _screenCenter,
                                ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // TOGGLE BUTTON
                    FloatingActionButton(
                      heroTag: "toggle_mode",
                      backgroundColor: _isAddMode ? Colors.red : Colors.white,
                      foregroundColor:
                          _isAddMode ? Colors.white : Colors.orange[800],
                      onPressed: () {
                        setState(() {
                          _isAddMode = !_isAddMode;
                        });
                      },
                      child: Icon(_isAddMode ? Icons.close : Icons.add),
                    ),
                  ],
                ),
              ),

              // GPS BUTTON
              Positioned(
                bottom: 30,
                right: 20,
                child: FloatingActionButton(
                  heroTag: "gps_btn",
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue[900],
                  onPressed: _isLocating ? null : _zoomToMyLocation,
                  child:
                      _isLocating
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.my_location),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _legendItem(String assetPath, Color fallbackColor) {
    return Image.asset(
      assetPath,
      width: 16,
      height: 16,
      errorBuilder:
          (c, e, s) => Icon(Icons.location_on, size: 16, color: fallbackColor),
    );
  }

  // --- DETAILS SHEET ---
  void _showContributorDetails(BuildContext context, Contributor c) {
    final int currentYear = DateTime.now().year;
    final double paid = c.getYearTotal(currentYear);
    final double pending = c.targetAmount - paid;
    final double progress =
        c.targetAmount > 0 ? (paid / c.targetAmount).clamp(0.0, 1.0) : 0;
    final bool isAdmin =
        FirebaseAuth.instance.currentUser?.email != null &&
        _adminEmails.contains(FirebaseAuth.instance.currentUser!.email);

    // Retrieve previous payments if available in your Contributor model
    // Assuming 'yearlyPayments' is a Map<String, dynamic> in your model
    final Map<String, dynamic> pastPayments = c.yearlyPayments;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            builder:
                (_, scrollController) => SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage:
                              c.imageUrl != null
                                  ? NetworkImage(c.imageUrl!)
                                  : null,
                          child:
                              c.imageUrl == null
                                  ? Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.grey[400],
                                  )
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        // Show Type Badge (New)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            c.type
                                .toUpperCase(), // Assuming 'type' exists in model
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        Text(
                          "ID: ${c.id}",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Stats Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildStatColumn(
                                    "Target",
                                    c.targetAmount,
                                    Colors.black87,
                                  ),
                                  _buildStatColumn("Paid", paid, Colors.green),
                                  _buildStatColumn(
                                    "Pending",
                                    pending,
                                    pending > 0 ? Colors.red : Colors.green,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation(
                                    pending <= 0 ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Previous Years Section (New)
                        if (pastPayments.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Contribution History",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[800],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...pastPayments.entries.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Year ${e.key}",
                                          style: const TextStyle(
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          _currency.format(e.value),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        _detailRow(
                          Icons.phone,
                          c.contactNumber.isEmpty
                              ? "No Contact"
                              : c.contactNumber,
                        ),
                        const SizedBox(height: 12),
                        _detailRow(
                          Icons.location_on,
                          c.address.isEmpty ? "No Address" : c.address,
                        ),
                        const SizedBox(height: 30),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showAddPaymentDialog(context, c);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[900],
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_card,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  "ADD PAYMENT",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => _confirmUnpin(context, c),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange[800],
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              icon: const Icon(Icons.location_off),
                              label: const Text("UNPIN"),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: () => _confirmDelete(context, c),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Icon(Icons.delete),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _confirmUnpin(BuildContext context, Contributor c) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Unpin Location?"),
            content: Text("Unpin ${c.name}? You can re-assign them later."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await FirebaseFirestore.instance
                      .collection('contributors')
                      .doc(c.id)
                      .update({'location': FieldValue.delete()});
                  _showSnack("Location unpinned.");
                },
                child: const Text(
                  "Unpin",
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
          ),
    );
  }

  void _confirmDelete(BuildContext context, Contributor c) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Delete Contributor"),
            content: Text("Delete ${c.name}? This cannot be undone."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('contributors')
                      .doc(c.id)
                      .delete();
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildStatColumn(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          _currency.format(value),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }

  // --- PAYMENT DIALOG (Standard) ---
  void _showAddPaymentDialog(BuildContext context, Contributor c) {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String selectedType = 'Kalash';
    bool isLoading = false;
    Uint8List? imgBytes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> pickImg(ImageSource src) async {
                final xfile = await ImagePicker().pickImage(
                  source: src,
                  imageQuality: 50,
                );
                if (xfile != null) {
                  final bytes = await xfile.readAsBytes();
                  setSheetState(() => imgBytes = bytes);
                }
              }

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Add Payment for ${c.name}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Amount",
                          prefixText: "₹ ",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        children:
                            _paymentTypes
                                .map(
                                  (t) => ChoiceChip(
                                    label: Text(t),
                                    selected: selectedType == t,
                                    onSelected:
                                        (v) => setSheetState(
                                          () => selectedType = t,
                                        ),
                                  ),
                                )
                                .toList(),
                      ),
                      if (selectedType != 'Kalash') ...[
                        const SizedBox(height: 20),
                        TextField(
                          controller: refCtrl,
                          decoration: const InputDecoration(
                            labelText: "Reference No",
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickImg(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text("Camera"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickImg(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text("Gallery"),
                            ),
                          ),
                        ],
                      ),
                      if (imgBytes != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Image.memory(
                            imgBytes!,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed:
                              isLoading
                                  ? null
                                  : () async {
                                    final amt = double.tryParse(
                                      amountCtrl.text,
                                    );
                                    if (amt == null || amt <= 0) return;
                                    setSheetState(() => isLoading = true);

                                    String? url;
                                    if (imgBytes != null) {
                                      try {
                                        final ref = FirebaseStorage.instance
                                            .ref()
                                            .child(
                                              'payment_proofs/${c.id}/${DateTime.now().millisecondsSinceEpoch}.jpg',
                                            );
                                        await ref.putData(
                                          imgBytes!,
                                          SettableMetadata(
                                            contentType: 'image/jpeg',
                                          ),
                                        );
                                        url = await ref.getDownloadURL();
                                      } catch (e) {
                                        setSheetState(
                                          () => isLoading = false,
                                        );
                                        return;
                                      }
                                    }

                                    final newPay = PaymentRecord(
                                      id:
                                          DateTime.now()
                                              .millisecondsSinceEpoch
                                              .toString(),
                                      amount: amt,
                                      date: DateTime.now(),
                                      type: selectedType,
                                      referenceId: refCtrl.text,
                                      imageUrl: url,
                                    );

                                    final history =
                                        [
                                          ...c.paymentHistory,
                                          newPay,
                                        ].map((e) => e.toMap()).toList();
                                    await FirebaseFirestore.instance
                                        .collection('contributors')
                                        .doc(c.id)
                                        .update({'paymentHistory': history});
                                    if (mounted) Navigator.pop(context);
                                  },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[900],
                          ),
                          child:
                              isLoading
                                  ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                  : const Text(
                                    "CONFIRM PAYMENT",
                                    style: TextStyle(color: Colors.white),
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

  // --- ASSIGN LOCATION DIALOG (Standard) ---
  void _showAssignLocationDialog(
    BuildContext context,
    LatLng targetPos,
    List<Contributor> unmapped,
  ) {
    final searchCtrl = TextEditingController();
    if (unmapped.isEmpty) {
      _showSnack("All contributors already have locations!");
      return;
    }

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setState) {
              final filtered =
                  unmapped
                      .where(
                        (u) => u.name.toLowerCase().contains(
                          searchCtrl.text.toLowerCase(),
                        ),
                      )
                      .toList();
              return AlertDialog(
                title: const Text("Assign to this Location"),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 400,
                  child: Column(
                    children: [
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          hintText: "Search Name",
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final u = filtered[i];
                            return ListTile(
                              leading: CircleAvatar(child: Text(u.name[0])),
                              title: Text(u.name),
                              subtitle: Text(u.id),
                              onTap: () async {
                                await FirebaseFirestore.instance
                                    .collection('contributors')
                                    .doc(u.id)
                                    .update({
                                      'location': GeoPoint(
                                        targetPos.latitude,
                                        targetPos.longitude,
                                      ),
                                    });
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  _showSnack("Contributor Pinned Successfully");
                                }
                              },
                            );
                          },
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
}

// ==========================================
// NEW: ADD CONTRIBUTOR DIALOG CLASS
// ==========================================

class AddContributorDialog extends StatefulWidget {
  final LatLng location; // Added to save map location

  const AddContributorDialog({super.key, required this.location});

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
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 40,
    );

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
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('contributors_images')
          .child('$docId.jpg');
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
        final docRef = FirebaseFirestore.instance
            .collection('contributors')
            .doc(docId);
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: ID already exists!')),
            );
          setState(() => _isLoading = false);
          return;
        }

        // 2. Upload Image
        String? imageUrl;
        if (_imageBytes != null) {
          imageUrl = await _uploadImage(docId);
        }

        // 3. Prepare Yearly Payments Map
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

          'location': GeoPoint(
            widget.location.latitude,
            widget.location.longitude,
          ), // SAVING THE LOCATION FROM MAP

          'targetAmount': double.tryParse(_targetController.text) ?? 0.0,
          'paymentHistory': [],
          'yearlyPayments': pastPayments,

          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contributor Added!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
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
                    const Text(
                      "New Contributor",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
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
                      backgroundImage:
                          _imageBytes != null
                              ? MemoryImage(_imageBytes!)
                              : null,
                      child:
                          _imageBytes == null
                              ? const Icon(
                                Icons.add_a_photo,
                                size: 40,
                                color: Colors.grey,
                              )
                              : null,
                    ),
                  ),
                ),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "Tap to add photo",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Basic Info
                TextFormField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: "Unique ID (e.g. SHOP-01)",
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (val) => val!.isEmpty ? "ID required" : null,
                ),
                const SizedBox(height: 16),

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

                // Type & Current Target
                Row(
                  children: [
                    Expanded(
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
                    Expanded(
                      child: TextFormField(
                        controller: _targetController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Target $currentYear (₹)",
                          border: const OutlineInputBorder(),
                          filled: true,
                        ),
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
                      const Text(
                        "Previous Contributions (Optional)",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
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
                                fillColor: Colors.white,
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
                                fillColor: Colors.white,
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
                    onPressed: _isLoading ? null : _saveContributor,
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
                    label: Text(_isLoading ? "SAVING..." : "CREATE PROFILE"),
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