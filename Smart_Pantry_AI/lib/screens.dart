import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'product_model.dart';
import 'shopping_model.dart';
import 'storage_service.dart';
import 'ocr_service.dart';
import 'recipe_service.dart';

/// ===============================================================
/// PANTRY CATEGORIES
/// ===============================================================
/// Keep this list UNIQUE.
/// "Groceries" is included because OCRService can return Groceries.
const List<String> pantryCategories = [
  'Dairy',
  'Grains',
  'Snacks',
  'Beverages',
  'Household',
  'Groceries',
  'Others',
];

/// Makes sure an OCR/manual category is always valid for the dropdown.
String safeCategory(String? category) {
  if (category != null && pantryCategories.contains(category)) {
    return category;
  }
  return 'Others';
}

/// ===============================================================
/// MAIN PANTRY HOME PAGE
/// ===============================================================

class PantryPulseHomePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const PantryPulseHomePage({
    super.key,
    required this.cameras,
  });

  @override
  State<PantryPulseHomePage> createState() => _PantryPulseHomePageState();
}

class _PantryPulseHomePageState extends State<PantryPulseHomePage> {
  int selectedIndex = 0;

  List<Product> pantryItems = [];

  String searchQuery = '';

  final TextEditingController searchController =
      TextEditingController();

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPantry();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPantry() async {
    try {
      final items = await StorageService.loadProducts();

      if (!mounted) return;

      setState(() {
        pantryItems = items;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        pantryItems = [];
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load pantry: $e'),
        ),
      );
    }
  }

  Future<void> _savePantry() async {
    await StorageService.saveProducts(pantryItems);
  }

  void addProduct(Product product) {
    setState(() {
      pantryItems.add(product);
      selectedIndex = 2;
    });

    _savePantry();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Product added to pantry!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void deleteProduct(Product product) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text(
            'Are you sure you want to delete "${product.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  pantryItems.removeWhere(
                    (p) => p.id == product.id,
                  );
                });

                _savePantry();

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Product removed from pantry'),
                  ),
                );
              },
              child: const Text(
                'DELETE',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  String getStatus(String expDate) {
    if (expDate.isEmpty ||
        expDate.toLowerCase() == 'not detected') {
      return 'Fresh';
    }

    DateTime? date;

    final formats = [
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'dd.MM.yyyy',
      'dd/MM/yy',
      'dd-MM-yy',
      'yyyy-MM-dd',
    ];

    for (final format in formats) {
      try {
        date = DateFormat(format).parseStrict(expDate);
        break;
      } catch (_) {}
    }

    if (date == null) {
      return 'Fresh';
    }

    final today = DateTime.now();

    final expiryDay = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final todayDay = DateTime(
      today.year,
      today.month,
      today.day,
    );

    final diff = expiryDay.difference(todayDay).inDays;

    if (diff < 0) {
      return 'Expired';
    }

    if (diff <= 7) {
      return 'Expiring Soon';
    }

    return 'Fresh';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Expired':
        return Colors.red;
      case 'Expiring Soon':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pantry Pulse',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: IndexedStack(
        index: selectedIndex,
        children: [
          buildHome(),

          OCRScannerPage(
            cameras: widget.cameras,
            onProductAdded: addProduct,
            isActive: selectedIndex == 1,
          ),

          buildPantry(),

          RecipesScreen(
            pantryItems: pantryItems,
          ),

          const PlannerScreen(),

          AnalyticsScreen(
            pantryItems: pantryItems,
          ),
        ],
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,

        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },

        labelBehavior:
            NavigationDestinationLabelBehavior.alwaysShow,

        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen),
            label: 'Pantry',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Recipes',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Planner',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }

  /// =============================================================
  /// HOME
  /// =============================================================

  Widget buildHome() {
    final expired = pantryItems
        .where(
          (item) => getStatus(item.exp) == 'Expired',
        )
        .length;

    final expiring = pantryItems
        .where(
          (item) => getStatus(item.exp) == 'Expiring Soon',
        )
        .length;

    final lowStock = pantryItems
        .where(
          (item) =>
              item.quantity.toLowerCase().contains('low'),
        )
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Text(
            'Welcome to Pantry Pulse 👋',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Manage your kitchen smarter with AI-powered analytics.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 25),

          /// SCAN BUTTON
          Material(
            color: Colors.green,
            borderRadius: BorderRadius.circular(20),

            child: InkWell(
              borderRadius: BorderRadius.circular(20),

              onTap: () {
                setState(() {
                  selectedIndex = 1;
                });
              },

              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),

                child: const Column(
                  children: [
                    Icon(
                      Icons.document_scanner,
                      color: Colors.white,
                      size: 60,
                    ),

                    SizedBox(height: 12),

                    Text(
                      'SCAN PRODUCT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text(
                      'Use OCR to read product labels',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 15),

          /// ACTION BUTTONS
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: showAddManualDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('ADD ITEM'),

                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      selectedIndex = 3;
                    });
                  },

                  icon: const Icon(Icons.auto_awesome),

                  label: const Text('AI RECIPES'),

                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                    ),
                    backgroundColor: Colors.orange.shade50,
                    foregroundColor: Colors.orange.shade900,
                    elevation: 0,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: Colors.orange.shade100,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          const Text(
            'Quick Summary',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),

            mainAxisSpacing: 12,
            crossAxisSpacing: 12,

            childAspectRatio: 1.3,

            children: [
              summaryCard(
                'Total Items',
                pantryItems.length.toString(),
                Icons.inventory_2,
                Colors.blue,
              ),

              summaryCard(
                'Expired',
                expired.toString(),
                Icons.error_outline,
                Colors.red,
              ),

              summaryCard(
                'Expiring Soon',
                expiring.toString(),
                Icons.warning_amber,
                Colors.orange,
              ),

              summaryCard(
                'Low Stock',
                lowStock.toString(),
                Icons.trending_down,
                Colors.purple,
              ),
            ],
          ),

          const SizedBox(height: 30),

          if (pantryItems.isNotEmpty) ...[
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,

              children: [
                const Text(
                  'Recent Items',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedIndex = 2;
                    });
                  },
                  child: const Text('View All'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            ...pantryItems.reversed.take(3).map(
              (item) {
                final status = getStatus(item.exp);

                return Card(
                  margin:
                      const EdgeInsets.only(bottom: 8),

                  child: ListTile(
                    title: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    subtitle: Text(
                      '${item.brand} • ${item.quantity}',
                    ),

                    trailing: Text(
                      status,
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget summaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),

      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [
          Icon(
            icon,
            size: 30,
            color: color,
          ),

          const SizedBox(height: 5),

          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// =============================================================
  /// PANTRY
  /// =============================================================

  Widget buildPantry() {
    final filteredItems =
        pantryItems.where((item) {
      final q = searchQuery.toLowerCase();

      return item.name.toLowerCase().contains(q) ||
          item.brand.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),

          child: TextField(
            controller: searchController,

            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },

            decoration: InputDecoration(
              hintText: 'Search pantry...',

              prefixIcon:
                  const Icon(Icons.search),

              filled: true,

              fillColor: Colors.white,

              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: filteredItems.isEmpty
              ? buildEmptyState()

              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),

                  itemCount:
                      filteredItems.length,

                  itemBuilder: (context, index) {
                    final item =
                        filteredItems[index];

                    final status =
                        getStatus(item.exp);

                    return Card(
                      margin:
                          const EdgeInsets.only(
                        bottom: 12,
                      ),

                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(15),
                      ),

                      child: ListTile(
                        title: Text(
                          item.name,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        subtitle: Text(
                          'Category: ${item.category}\n'
                          'Qty: ${item.quantity}\n'
                          'MFD: ${item.mfd}\n'
                          'EXP: ${item.exp}\n'
                          'Price: ₹${item.price.toStringAsFixed(2)}',
                        ),

                        isThreeLine: true,

                        trailing: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,

                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),

                              decoration:
                                  BoxDecoration(
                                color:
                                    _getStatusColor(
                                  status,
                                ).withValues(
                                  alpha: 0.1,
                                ),

                                borderRadius:
                                    BorderRadius.circular(
                                  8,
                                ),
                              ),

                              child: Text(
                                status,
                                style: TextStyle(
                                  color:
                                      _getStatusColor(
                                    status,
                                  ),
                                  fontSize: 10,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),

                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),

                              onPressed: () =>
                                  deleteProduct(item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [
          Icon(
            Icons.kitchen,
            size: 80,
            color: Colors.grey.shade300,
          ),

          const SizedBox(height: 20),

          const Text(
            'Pantry is empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Text(
            'Scan items to get started.',
            style: TextStyle(
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 30),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,

            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    selectedIndex = 1;
                  });
                },

                icon:
                    const Icon(Icons.camera_alt),

                label: const Text('Scan'),
              ),

              const SizedBox(width: 15),

              OutlinedButton.icon(
                onPressed:
                    showAddManualDialog,

                icon:
                    const Icon(Icons.edit),

                label:
                    const Text('Manual'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// =============================================================
  /// MANUAL ADD PRODUCT
  /// =============================================================

  void showAddManualDialog() {
    final nameController =
        TextEditingController();

    final brandController =
        TextEditingController();

    final qtyController =
        TextEditingController();

    final expController =
        TextEditingController();

    final mfdController =
        TextEditingController();

    final priceController =
        TextEditingController();

    String category = 'Others';

    showModalBottomSheet(
      context: context,

      isScrollControlled: true,

      builder: (sheetContext) {
        return StatefulBuilder(
          builder:
              (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(context)
                        .viewInsets
                        .bottom,

                left: 20,
                right: 20,
                top: 20,
              ),

              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,

                  children: [
                    const Text(
                      'Add Product Manually',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextField(
                      controller:
                          nameController,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Product Name',
                      ),
                    ),

                    TextField(
                      controller:
                          brandController,

                      decoration:
                          const InputDecoration(
                        labelText: 'Brand',
                      ),
                    ),

                    TextField(
                      controller:
                          qtyController,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Quantity',
                      ),
                    ),

                    TextField(
                      controller:
                          priceController,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Price (₹)',
                      ),

                      keyboardType:
                          TextInputType.number,
                    ),

                    TextField(
                      controller:
                          mfdController,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'MFD (DD/MM/YYYY)',
                      ),
                    ),

                    TextField(
                      controller:
                          expController,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'EXP (DD/MM/YYYY)',
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// FIXED DROPDOWN
                    DropdownButtonFormField<String>(
                      initialValue:
                          safeCategory(category),

                      items:
                          pantryCategories
                              .map(
                                (c) =>
                                    DropdownMenuItem<
                                        String>(
                                  value: c,
                                  child:
                                      Text(c),
                                ),
                              )
                              .toList(),

                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() {
                            category = value;
                          });
                        }
                      },

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Category',
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,

                      child: ElevatedButton(
                        onPressed: () {
                          if (nameController
                              .text
                              .trim()
                              .isEmpty) {
                            ScaffoldMessenger
                                .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter product name',
                                ),
                              ),
                            );

                            return;
                          }

                          addProduct(
                            Product(
                              id: DateTime
                                  .now()
                                  .millisecondsSinceEpoch
                                  .toString(),

                              name:
                                  nameController
                                      .text
                                      .trim(),

                              brand:
                                  brandController
                                      .text
                                      .trim()
                                      .isEmpty
                                  ? 'Unknown'
                                  : brandController
                                      .text
                                      .trim(),

                              quantity:
                                  qtyController
                                      .text
                                      .trim()
                                      .isEmpty
                                  ? 'Not detected'
                                  : qtyController
                                      .text
                                      .trim(),

                              mfd:
                                  mfdController
                                      .text
                                      .trim()
                                      .isEmpty
                                  ? 'Not detected'
                                  : mfdController
                                      .text
                                      .trim(),

                              exp:
                                  expController
                                      .text
                                      .trim()
                                      .isEmpty
                                  ? 'Not detected'
                                  : expController
                                      .text
                                      .trim(),

                              category:
                                  safeCategory(
                                category,
                              ),

                              addedDate:
                                  DateTime.now(),

                              price:
                                  double.tryParse(
                                    priceController
                                        .text
                                        .trim(),
                                  ) ??
                                  0.0,
                            ),
                          );

                          Navigator.pop(
                            sheetContext,
                          );
                        },

                        child:
                            const Text(
                          'ADD TO PANTRY',
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// ===============================================================
/// OCR SCANNER — TWO SIDE PRODUCT SCAN
/// ===============================================================

class OCRScannerPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(Product) onProductAdded;
  final bool isActive;

  const OCRScannerPage({
    super.key,
    required this.cameras,
    required this.onProductAdded,
    required this.isActive,
  });

  @override
  State<OCRScannerPage> createState() => _OCRScannerPageState();
}

class _OCRScannerPageState extends State<OCRScannerPage>
    with WidgetsBindingObserver {
  CameraController? controller;

  final TextRecognizer textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  bool isProcessing = false;
  FlashMode flashMode = FlashMode.off;

  bool frontScanned = false;
  Map<String, String>? frontDetails;

  String scanTitle = '1 of 2 — FRONT SIDE';
  String scanMessage = 'Scan the FRONT of the product';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeCamera();
  }

  @override
  void didUpdateWidget(OCRScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !oldWidget.isActive) {
      controller?.resumePreview();
    }

    if (!widget.isActive && oldWidget.isActive) {
      controller?.pausePreview();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final currentController = controller;

    if (currentController == null ||
        !currentController.value.isInitialized) {
      if (state == AppLifecycleState.resumed) {
        initializeCamera();
      }
      return;
    }

    if (state == AppLifecycleState.inactive) {
      currentController.dispose();
      controller = null;
    } else if (state == AppLifecycleState.resumed) {
      initializeCamera();
    }
  }

  Future<void> initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    if (controller != null) {
      try {
        if (controller!.value.isInitialized) return;
      } catch (_) {}
    }

    final camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await newController.initialize();
      await newController.setFlashMode(flashMode);

      if (!mounted) {
        await newController.dispose();
        return;
      }

      setState(() {
        controller = newController;
      });
    } catch (e) {
      await newController.dispose();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e')),
      );
    }
  }

  void resetScanner() {
    setState(() {
      frontScanned = false;
      frontDetails = null;
      scanTitle = '1 of 2 — FRONT SIDE';
      scanMessage = 'Scan the FRONT of the product';
    });
  }

  Future<void> scanProduct() async {
    final cameraController = controller;

    if (cameraController == null ||
        !cameraController.value.isInitialized ||
        isProcessing) {
      return;
    }

    setState(() {
      isProcessing = true;
    });

    try {
      final XFile image = await cameraController.takePicture();

      final inputImage = InputImage.fromFilePath(image.path);

      final recognizedText =
          await textRecognizer.processImage(inputImage);

      final ocrText = recognizedText.text.trim();

      if (!mounted) return;

      if (ocrText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No text detected. Move closer, improve lighting and try again.',
            ),
          ),
        );
        return;
      }

      // ------------------------------------------------------------
      // FIRST PHOTO: FRONT
      // ------------------------------------------------------------
      if (!frontScanned) {
        final details = OCRService.extractFrontDetails(ocrText);

        setState(() {
          frontDetails = details;
          frontScanned = true;
          scanTitle = '2 of 2 — BACK SIDE';
          scanMessage =
              'Turn the product around and scan the BACK';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Front scan complete. Now scan the back side.',
            ),
            duration: Duration(seconds: 3),
          ),
        );

        return;
      }

      // ------------------------------------------------------------
      // SECOND PHOTO: BACK
      // ------------------------------------------------------------
      final backDetails = OCRService.extractBackDetails(ocrText);

      final combinedDetails = OCRService.combineDetails(
        frontDetails ?? {},
        backDetails,
      );

      await _showConfirmationScreen(combinedDetails);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanning error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  Future<void> _showConfirmationScreen(
    Map<String, String> details,
  ) async {
    final nameController = TextEditingController(
      text: details['name'] ?? 'Unknown Product',
    );

    final brandController = TextEditingController(
      text: details['brand'] ?? 'Unknown Brand',
    );

    final qtyController = TextEditingController(
      text: details['quantity'] ?? 'Not detected',
    );

    final priceController = TextEditingController(
      text: details['price'] ?? '0.00',
    );

    final mfdController = TextEditingController(
      text: details['mfd'] ?? 'Not detected',
    );

    final expController = TextEditingController(
      text: details['exp'] ?? 'Not detected',
    );

    String category = safeCategory(details['category']);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        '🔍 Review Product',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Center(
                      child: Text(
                        'Check both scanned sides before adding',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                        prefixIcon: Icon(Icons.inventory_2),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: brandController,
                      decoration: const InputDecoration(
                        labelText: 'Brand',
                        prefixIcon: Icon(Icons.branding_watermark),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: qtyController,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        hintText: 'Example: 500 g',
                        prefixIcon: Icon(Icons.scale),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Price / MRP (₹)',
                        prefixIcon: Icon(Icons.currency_rupee),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: mfdController,
                      decoration: const InputDecoration(
                        labelText: 'MFD / MFG',
                        hintText: 'DD/MM/YYYY',
                        prefixIcon: Icon(Icons.date_range),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: expController,
                      decoration: const InputDecoration(
                        labelText: 'EXP / Best Before',
                        hintText: 'DD/MM/YYYY',
                        prefixIcon: Icon(Icons.event),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      initialValue: safeCategory(category),
                      items: pantryCategories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() {
                            category = value;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              resetScanner();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('RETAKE'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final name =
                                  nameController.text.trim();

                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Product name cannot be empty',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final product = Product(
                                id: DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                                name: name,
                                brand: brandController.text.trim().isEmpty
                                    ? 'Unknown Brand'
                                    : brandController.text.trim(),
                                quantity: qtyController.text.trim().isEmpty
                                    ? 'Not detected'
                                    : qtyController.text.trim(),
                                mfd: mfdController.text.trim().isEmpty
                                    ? 'Not detected'
                                    : mfdController.text.trim(),
                                exp: expController.text.trim().isEmpty
                                    ? 'Not detected'
                                    : expController.text.trim(),
                                category: safeCategory(category),
                                addedDate: DateTime.now(),
                                price: double.tryParse(
                                      priceController.text.trim(),
                                    ) ??
                                    0.0,
                              );

                              widget.onProductAdded(product);

                              Navigator.pop(sheetContext);
                              resetScanner();
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('ADD TO PANTRY'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    brandController.dispose();
    qtyController.dispose();
    priceController.dispose();
    mfdController.dispose();
    expController.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null ||
        !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: CameraPreview(controller!),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.18),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Text(
                        scanTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        scanMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Center(
            child: Container(
              width: 310,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: frontScanned
                      ? Colors.orange
                      : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          Positioned(
            top: 150,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  frontScanned
                      ? '🔄 Turn package around'
                      : '📦 Align FRONT label inside frame',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 45,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                onPressed: isProcessing ? null : scanProduct,
                backgroundColor:
                    frontScanned ? Colors.orange : Colors.green,
                child: isProcessing
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Icon(
                        Icons.camera_alt,
                        size: 40,
                        color: Colors.white,
                      ),
              ),
            ),
          ),

          Positioned(
            bottom: 50,
            right: 25,
            child: IconButton(
              icon: Icon(
                flashMode == FlashMode.off
                    ? Icons.flash_off
                    : Icons.flash_on,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () async {
                final newMode = flashMode == FlashMode.off
                    ? FlashMode.torch
                    : FlashMode.off;

                setState(() {
                  flashMode = newMode;
                });

                try {
                  await controller?.setFlashMode(newMode);
                } catch (_) {}
              },
            ),
          ),

          if (frontScanned)
            Positioned(
              bottom: 55,
              left: 25,
              child: IconButton(
                tooltip: 'Start over',
                icon: const Icon(
                  Icons.restart_alt,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed:
                    isProcessing ? null : resetScanner,
              ),
            ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// CHEF AI RECIPES
/// ===============================================================

class RecipesScreen extends StatefulWidget {
  final List<Product> pantryItems;

  const RecipesScreen({
    super.key,
    required this.pantryItems,
  });

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'content':
          'Hello! I am Chef AI 👨‍🍳\n\n'
          'Ask me for ANY recipe you want.\n\n'
          'For example:\n'
          '• How can I make chicken biryani?\n'
          '• How can I make chicken curry?\n'
          '• Give me a dal recipe\n'
          '• How can I make Maggi?\n'
          '• How can I make paneer butter masala?\n\n'
          'I will generate the recipe for the exact dish you ask for.',
    },
  ];

  bool isTyping = false;

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage() async {
    final userMessage = _chatController.text.trim();

    if (userMessage.isEmpty || isTyping) {
      return;
    }

    setState(() {
      _messages.add({
        'role': 'user',
        'content': userMessage,
      });
      _chatController.clear();
      isTyping = true;
    });

    _scrollToBottom();

    try {
      // Send the exact recipe request to Gemini.
      final response = await RecipeService.generateRecipe(userMessage);

      if (!mounted) return;

      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': response,
        });
        isTyping = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _messages.add({
          'role': 'assistant',
          'content':
              '❌ Sorry, I could not generate the recipe.\n\n'
              'Please check your Gemini API connection and try again.\n\n'
              'Error: $e',
        });
        isTyping = false;
      });
    }

    _scrollToBottom();
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _messages.add({
        'role': 'assistant',
        'content':
            'Hello! I am Chef AI 👨‍🍳\n\n'
            'Ask me for ANY recipe you want.\n\n'
            'For example:\n'
            '• Chicken Biryani\n'
            '• Chicken Curry\n'
            '• Dal\n'
            '• Maggi\n'
            '• Paneer Butter Masala\n\n'
            'I will generate the recipe for the exact dish you ask for.',
      });
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F3),
      appBar: AppBar(
        title: const Text(
          'Chef AI Kitchen Assistant',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Clear chat',
            onPressed: isTyping ? null : _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.88,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.green.shade600 : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isUser ? 20 : 0),
                        bottomRight: Radius.circular(isUser ? 0 : 20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.restaurant,
                                  size: 15,
                                  color: Colors.green.shade800,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'CHEF AI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        SelectableText(
                          message['content'] ?? '',
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (isTyping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Chef AI is preparing your recipe...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Colors.white),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      enabled: !isTyping,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Ask Chef AI for any recipe...',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _handleSendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.green,
                    child: IconButton(
                      icon: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                      ),
                      onPressed: isTyping ? null : _handleSendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// PLANNER + SHOPPING LIST
/// ===============================================================

class PlannerScreen
    extends StatefulWidget {
  const PlannerScreen({
    super.key,
  });

  @override
  State<PlannerScreen> createState() =>
      _PlannerScreenState();
}

class _PlannerScreenState
    extends State<PlannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController
      _tabController;

  List<ShoppingItem>
      shoppingList = [];

  final TextEditingController
      _shoppingController =
      TextEditingController();

  final List<String> weekDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  Map<String, String>
      mealPlan = {};

  @override
  void initState() {
    super.initState();

    _tabController =
        TabController(
      length: 2,
      vsync: this,
    );

    _loadShoppingList();

    for (final day in weekDays) {
      mealPlan[day] =
          'No meal planned';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _shoppingController.dispose();
    super.dispose();
  }

  Future<void>
      _loadShoppingList() async {
    try {
      final items =
          await StorageService
              .loadShoppingList();

      if (!mounted) return;

      setState(() {
        shoppingList = items;
      });
    } catch (_) {}
  }

  Future<void>
      _saveShoppingList() async {
    await StorageService
        .saveShoppingList(
      shoppingList,
    );
  }

  void _addShoppingItem() {
    final name =
        _shoppingController
            .text
            .trim();

    if (name.isEmpty) {
      return;
    }

    setState(() {
      shoppingList.add(
        ShoppingItem(
          id: DateTime
              .now()
              .millisecondsSinceEpoch
              .toString(),

          name: name,
        ),
      );

      _shoppingController.clear();
    });

    _saveShoppingList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller:
              _tabController,

          tabs: const [
            Tab(
              text: 'Weekly Planner',
              icon: Icon(
                Icons.calendar_month,
              ),
            ),

            Tab(
              text: 'Shopping List',
              icon: Icon(
                Icons.shopping_cart,
              ),
            ),
          ],
        ),

        Expanded(
          child: TabBarView(
            controller:
                _tabController,

            children: [
              buildWeeklyPlanner(),
              buildShoppingList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildWeeklyPlanner() {
    return ListView.builder(
      padding:
          const EdgeInsets.all(16),

      itemCount:
          weekDays.length,

      itemBuilder:
          (context, index) {
        final day =
            weekDays[index];

        return Card(
          margin:
              const EdgeInsets.only(
            bottom: 10,
          ),

          child: ListTile(
            leading:
                CircleAvatar(
              backgroundColor:
                  Colors.green
                      .shade100,

              child: Text(
                day[0],
              ),
            ),

            title: Text(
              day,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            subtitle: Text(
              mealPlan[day]!,
            ),

            trailing:
                IconButton(
              icon: const Icon(
                Icons.edit_outlined,
              ),

              onPressed: () =>
                  _editMeal(day),
            ),
          ),
        );
      },
    );
  }

  void _editMeal(
    String day,
  ) {
    final controller =
        TextEditingController(
      text:
          mealPlan[day] ==
                  'No meal planned'
              ? ''
              : mealPlan[day],
    );

    showDialog(
      context: context,

      builder:
          (dialogContext) {
        return AlertDialog(
          title: Text(
            'Plan Meal for $day',
          ),

          content: TextField(
            controller: controller,

            decoration:
                const InputDecoration(
              hintText:
                  'Enter dish name',
            ),
          ),

          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                dialogContext,
              ),

              child:
                  const Text(
                'CANCEL',
              ),
            ),

            TextButton(
              onPressed: () {
                setState(() {
                  mealPlan[day] =
                      controller
                              .text
                              .trim()
                              .isEmpty
                          ? 'No meal planned'
                          : controller
                              .text
                              .trim();
                });

                Navigator.pop(
                  dialogContext,
                );
              },

              child:
                  const Text(
                'SAVE',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildShoppingList() {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.all(
            16,
          ),

          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      _shoppingController,

                  decoration:
                      InputDecoration(
                    hintText:
                        'Add item to list...',

                    filled: true,

                    fillColor:
                        Colors.white,

                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        15,
                      ),

                      borderSide:
                          BorderSide.none,
                    ),
                  ),

                  onSubmitted:
                      (_) =>
                          _addShoppingItem(),
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              IconButton.filled(
                onPressed:
                    _addShoppingItem,

                icon: const Icon(
                  Icons.add,
                ),

                style:
                    IconButton.styleFrom(
                  backgroundColor:
                      Colors.green,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: shoppingList
                  .isEmpty
              ? const Center(
                  child: Text(
                    'Your shopping list is empty.',
                  ),
                )

              : ListView.builder(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 16,
                  ),

                  itemCount:
                      shoppingList.length,

                  itemBuilder:
                      (context, index) {
                    final item =
                        shoppingList[index];

                    return Card(
                      child:
                          CheckboxListTile(
                        value:
                            item.isBought,

                        onChanged:
                            (value) {
                          setState(() {
                            item.isBought =
                                value ??
                                    false;
                          });

                          _saveShoppingList();
                        },

                        title: Text(
                          item.name,

                          style:
                              TextStyle(
                            decoration:
                                item.isBought
                                    ? TextDecoration
                                        .lineThrough
                                    : null,

                            color:
                                item.isBought
                                    ? Colors
                                        .grey
                                    : Colors
                                        .black,
                          ),
                        ),

                        secondary:
                            IconButton(
                          icon:
                              const Icon(
                            Icons
                                .delete_outline,
                            color:
                                Colors.red,
                          ),

                          onPressed:
                              () {
                            setState(() {
                              shoppingList
                                  .removeAt(
                                index,
                              );
                            });

                            _saveShoppingList();
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// ===============================================================
/// ANALYTICS
/// ===============================================================

class AnalyticsScreen
    extends StatelessWidget {
  final List<Product>
      pantryItems;

  const AnalyticsScreen({
    super.key,
    required this.pantryItems,
  });

  String _getStatus(
    String expDate,
  ) {
    if (expDate.isEmpty ||
        expDate.toLowerCase() ==
            'not detected') {
      return 'Fresh';
    }

    DateTime? date;

    final formats = [
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'dd.MM.yyyy',
      'yyyy-MM-dd',
    ];

    for (final format in formats) {
      try {
        date =
            DateFormat(format)
                .parseStrict(expDate);

        break;
      } catch (_) {}
    }

    if (date == null) {
      return 'Fresh';
    }

    if (date.isBefore(
      DateTime.now(),
    )) {
      return 'Expired';
    }

    return 'Fresh';
  }

  @override
  Widget build(BuildContext context) {
    final monthlySpending =
        pantryItems.fold<double>(
      0.0,
      (sum, item) =>
          sum + item.price,
    );

    final foodWasteValue =
        pantryItems
            .where(
              (item) =>
                  _getStatus(
                    item.exp,
                  ) ==
                  'Expired',
            )
            .fold<double>(
              0.0,
              (sum, item) =>
                  sum +
                  (item.price > 0
                      ? item.price
                      : 45.0),
            );

    final totalItems =
        pantryItems.length;

    return SingleChildScrollView(
      padding:
          const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          const Text(
            'Analytics Dashboard',
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          _analyticsCard(
            'Budget Tracker',
            'Total Spending: ₹${monthlySpending.toStringAsFixed(2)}',
            'Based on prices entered for pantry items.',
            Icons.account_balance_wallet,
            Colors.blue,
          ),

          const SizedBox(height: 15),

          _analyticsCard(
            'Food Waste Analytics',
            'Waste Value: ₹${foodWasteValue.toStringAsFixed(2)}',
            'Estimated value of expired pantry items.',
            Icons.delete_sweep,
            Colors.red,
          ),

          const SizedBox(height: 15),

          _analyticsCard(
            'Pantry Inventory',
            '$totalItems Items',
            'Total products currently stored in your pantry.',
            Icons.inventory_2,
            Colors.green,
          ),

          const SizedBox(height: 30),

          const Text(
            'Category Distribution',
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          ..._buildCategoryRows(),
        ],
      ),
    );
  }

  List<Widget>
      _buildCategoryRows() {
    if (pantryItems.isEmpty) {
      return [
        const Text(
          'Add some pantry items to see category analytics.',
          style: TextStyle(
            color: Colors.grey,
          ),
        ),
      ];
    }

    final Map<String, int>
        counts = {};

    for (final item
        in pantryItems) {
      counts[item.category] =
          (counts[item.category] ??
                  0) +
              1;
    }

    final total =
        pantryItems.length;

    return counts.entries.map(
      (entry) {
        final percentage =
            entry.value / total;

        return Padding(
          padding:
              const EdgeInsets.only(
            bottom: 15,
          ),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,

            children: [
              Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .spaceBetween,

                children: [
                  Text(
                    entry.key,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.w500,
                    ),
                  ),

                  Text(
                    '${(percentage * 100).round()}%',
                  ),
                ],
              ),

              const SizedBox(
                height: 5,
              ),

              LinearProgressIndicator(
                value: percentage,

                backgroundColor:
                    Colors.grey
                        .shade200,

                borderRadius:
                    BorderRadius
                        .circular(
                  10,
                ),

                minHeight: 8,
              ),
            ],
          ),
        );
      },
    ).toList();
  }

  Widget _analyticsCard(
    String title,
    String value,
    String description,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        20,
      ),

      decoration:
          BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(
          20,
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(
              alpha: 0.05,
            ),

            blurRadius: 10,
          ),
        ],
      ),

      child: Row(
        children: [
          CircleAvatar(
            radius: 30,

            backgroundColor:
                color.withValues(
              alpha: 0.1,
            ),

            child: Icon(
              icon,
              color: color,
              size: 30,
            ),
          ),

          const SizedBox(
            width: 20,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    fontSize: 14,
                    color:
                        Colors.grey,
                  ),
                ),

                Text(
                  value,
                  style:
                      const TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 5,
                ),

                Text(
                  description,
                  style:
                      const TextStyle(
                    fontSize: 12,
                    color:
                        Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}