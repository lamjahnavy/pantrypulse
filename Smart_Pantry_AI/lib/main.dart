import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'product_model.dart';
import 'storage_service.dart';
import 'ocr_service.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(PantryPulseApp(cameras: cameras));
}

class PantryPulseApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const PantryPulseApp({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pantry Pulse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        scaffoldBackgroundColor: const Color(0xFFF5F8F3),
        useMaterial3: true,
      ),
      home: PantryPulseHomePage(cameras: cameras),
    );
  }
}

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
  final TextEditingController searchController = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPantry();
  }

  Future<void> _loadPantry() async {
    final items = await StorageService.loadProducts();
    setState(() {
      pantryItems = items;
      isLoading = false;
    });
  }

  Future<void> _savePantry() async {
    await StorageService.saveProducts(pantryItems);
  }

  void addProduct(Product product) {
    setState(() {
      pantryItems.add(product);
      selectedIndex = 2; // Go to Pantry tab
    });
    _savePantry();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product added to pantry!')),
    );
  }

  void deleteProduct(Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              setState(() {
                pantryItems.removeWhere((p) => p.id == product.id);
              });
              _savePantry();
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String getStatus(String expDate) {
    if (expDate == 'Not detected') return 'Fresh';
    try {
      final date = DateFormat('dd/MM/yyyy').parse(expDate);
      final now = DateTime.now();
      final diff = date.difference(now).inDays;
      if (diff < 0) return 'Expired';
      if (diff <= 7) return 'Expiring Soon';
      return 'Fresh';
    } catch (_) {
      try {
        final date = DateFormat('dd-MM-yyyy').parse(expDate);
        final now = DateTime.now();
        final diff = date.difference(now).inDays;
        if (diff < 0) return 'Expired';
        if (diff <= 7) return 'Expiring Soon';
        return 'Fresh';
      } catch (e) {
        return 'Fresh';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pantry Pulse',
          style: TextStyle(fontWeight: FontWeight.bold),
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
          RecipesScreen(pantryItems: pantryItems),
          const PlannerScreen(),
          AnalyticsScreen(pantryItems: pantryItems),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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

  Widget buildHome() {
    final expired = pantryItems.where((i) => getStatus(i.exp) == 'Expired').length;
    final expiring = pantryItems.where((i) => getStatus(i.exp) == 'Expiring Soon').length;
    final lowStock = pantryItems.where((i) => i.quantity.toLowerCase().contains('low')).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Welcome to Pantry Pulse 👋', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Manage your kitchen smarter with AI-powered analytics.', style: TextStyle(fontSize: 15, color: Colors.grey)),
          const SizedBox(height: 25),

          Material(
            color: Colors.green,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => selectedIndex = 1),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: const Column(
                  children: [
                    Icon(Icons.document_scanner, color: Colors.white, size: 60),
                    SizedBox(height: 12),
                    Text('SCAN PRODUCT', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                    SizedBox(height: 5),
                    Text('Use OCR to read product labels', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: showAddManualDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('ADD ITEM'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => selectedIndex = 3),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('AI RECIPES'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.orange.shade50,
                    foregroundColor: Colors.orange.shade900,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.orange.shade100)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),
          const Text('Quick Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              summaryCard('Total Items', pantryItems.length.toString(), Icons.inventory_2, Colors.blue),
              summaryCard('Expired', expired.toString(), Icons.error_outline, Colors.red),
              summaryCard('Expiring Soon', expiring.toString(), Icons.warning_amber, Colors.orange),
              summaryCard('Low Stock', lowStock.toString(), Icons.trending_down, Colors.purple),
            ],
          ),

          const SizedBox(height: 30),
          if (pantryItems.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Items', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                TextButton(onPressed: () => setState(() => selectedIndex = 2), child: const Text('View All')),
              ],
            ),
            const SizedBox(height: 10),
            ...pantryItems.reversed.take(3).map((item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${item.brand} • ${item.quantity}'),
                trailing: Text(getStatus(item.exp), style: TextStyle(color: _getStatusColor(getStatus(item.exp)))),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'Expired') return Colors.red;
    if (status == 'Expiring Soon') return Colors.orange;
    return Colors.green;
  }

  Widget summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget buildPantry() {
    final filteredItems = pantryItems.where((item) {
      final q = searchQuery.toLowerCase();
      return item.name.toLowerCase().contains(q) ||
             item.brand.toLowerCase().contains(q) ||
             item.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: searchController,
            onChanged: (value) => setState(() => searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search pantry...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty
              ? buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    final status = getStatus(item.exp);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Qty: ${item.quantity} | Exp: ${item.exp}\nPrice: \$${item.price.toStringAsFixed(2)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(status, style: TextStyle(color: _getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => deleteProduct(item)),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.kitchen, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          const Text('Pantry is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Scan items to get started.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(onPressed: () => setState(() => selectedIndex = 1), icon: const Icon(Icons.camera_alt), label: const Text('Scan')),
              const SizedBox(width: 15),
              OutlinedButton.icon(onPressed: showAddManualDialog, icon: const Icon(Icons.edit), label: const Text('Manual')),
            ],
          ),
        ],
      ),
    );
  }

  void showAddManualDialog() {
    final nameController = TextEditingController();
    final brandController = TextEditingController();
    final qtyController = TextEditingController();
    final expController = TextEditingController();
    final mfdController = TextEditingController();
    final priceController = TextEditingController();
    String category = 'Others';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Product Manually', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name')),
              TextField(controller: brandController, decoration: const InputDecoration(labelText: 'Brand')),
              TextField(controller: qtyController, decoration: const InputDecoration(labelText: 'Quantity')),
              TextField(controller: priceController, decoration: const InputDecoration(labelText: 'Price'), keyboardType: TextInputType.number),
              TextField(controller: mfdController, decoration: const InputDecoration(labelText: 'MFD (DD/MM/YYYY)')),
              TextField(controller: expController, decoration: const InputDecoration(labelText: 'EXP (DD/MM/YYYY)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: category,
                items: ['Dairy', 'Grains', 'Snacks', 'Beverages', 'Household', 'Others'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => category = v!,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    addProduct(Product(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text,
                      brand: brandController.text,
                      quantity: qtyController.text,
                      mfd: mfdController.text,
                      exp: expController.text,
                      category: category,
                      addedDate: DateTime.now(),
                      price: double.tryParse(priceController.text) ?? 0.0,
                    ));
                    Navigator.pop(context);
                  }
                },
                child: const Text('ADD TO PANTRY'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _OCRScannerPageState extends State<OCRScannerPage> with WidgetsBindingObserver {
  CameraController? controller;
  final TextRecognizer textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool isProcessing = false;
  String fullOcrText = '';
  FlashMode flashMode = FlashMode.off;

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
    } else if (!widget.isActive && oldWidget.isActive) {
      controller?.pausePreview();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (controller == null || !controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      initializeCamera();
    }
  }

  Future<void> initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    final camera = widget.cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => widget.cameras.first);
    controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
    await controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> scanProduct() async {
    if (controller == null || !controller!.value.isInitialized || isProcessing) return;
    setState(() => isProcessing = true);

    try {
      final XFile image = await controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      fullOcrText = recognizedText.text;
      if (!mounted) return;
      if (fullOcrText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No text detected. Try again.')));
        return;
      }

      final details = OCRService.extractDetails(fullOcrText);
      if (!mounted) return;
      _showConfirmationScreen(details);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showConfirmationScreen(Map<String, String> details) {
    final nameController = TextEditingController(text: details['name']);
    final brandController = TextEditingController(text: details['brand']);
    final qtyController = TextEditingController(text: details['quantity']);
    final mfdController = TextEditingController(text: details['mfd']);
    final expController = TextEditingController(text: details['exp']);
    final priceController = TextEditingController(text: '0.00');
    String category = details['category'] ?? 'Others';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Text('Confirm Product Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              const SizedBox(height: 10),
              ExpansionTile(
                title: const Text('Show Raw OCR Text', style: TextStyle(fontSize: 12, color: Colors.blue)),
                children: [Text(fullOcrText, style: const TextStyle(fontSize: 10, color: Colors.grey))],
              ),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name')),
              TextField(controller: brandController, decoration: const InputDecoration(labelText: 'Brand')),
              TextField(controller: qtyController, decoration: const InputDecoration(labelText: 'Quantity')),
              TextField(controller: priceController, decoration: const InputDecoration(labelText: 'Price'), keyboardType: TextInputType.number),
              TextField(controller: mfdController, decoration: const InputDecoration(labelText: 'MFD (DD/MM/YYYY)')),
              TextField(controller: expController, decoration: const InputDecoration(labelText: 'EXP (DD/MM/YYYY)')),
              DropdownButtonFormField<String>(
                value: category,
                items: ['Dairy', 'Grains', 'Snacks', 'Beverages', 'Household', 'Others'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => category = v!,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('RETAKE'))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(onPressed: () {
                    widget.onProductAdded(Product(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text,
                      brand: brandController.text,
                      quantity: qtyController.text,
                      mfd: mfdController.text,
                      exp: expController.text,
                      category: category,
                      addedDate: DateTime.now(),
                      price: double.tryParse(priceController.text) ?? 0.0,
                    ));
                    Navigator.pop(context);
                  }, child: const Text('ADD TO PANTRY'))),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
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
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(child: CameraPreview(controller!)),
          // Scanning Overlay
          Center(
            child: Container(
              width: 300, height: 250,
              decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.5), width: 2), borderRadius: BorderRadius.circular(20)),
            ),
          ),
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Column(
              children: [
                const Text('Align product label inside the frame', style: TextStyle(color: Colors.white, backgroundColor: Colors.black45)),
                const SizedBox(height: 20),
                FloatingActionButton.large(
                  onPressed: isProcessing ? null : scanProduct,
                  backgroundColor: Colors.green,
                  child: isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.camera_alt, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 20),
                IconButton(
                  icon: Icon(flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      flashMode = flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
                    });
                    controller?.setFlashMode(flashMode);
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Scaffold.of(context).openDrawer()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
