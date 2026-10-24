import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ----------------- Brand & App Constants -----------------
class AppConstants {
  static const String appsScriptUrl = "https://script.google.com/macros/s/AKfycbySampleUrlHere/exec";
  static const String shopUpiId = "dhanalakshmipathirakadai@upi";
  static const String shopName = "Dhanalakshmi Patthirakadai";
}

class AppColors {
  static const Color primary = Color(0xFF8D4925); // Deep Copper Bronze
  static const Color primaryLight = Color(0xFFAA5B32);
  static const Color primaryDark = Color(0xFF5A2A11);
  static const Color primaryContainer = Color(0xFFFDEEE6);
  static const Color accentGreen = Color(0xFF2E7D32);
  static const Color bgSurface = Color(0xFFF9F6F0);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF231810);
  static const Color textMuted = Color(0xFF756A63);

  // Warning & Alert Colors
  static const Color criticalRed = Color(0xFFD32F2F);
  static const Color alertOrange = Color(0xFFE65100);
}

// ----------------- SQLite Database -----------------
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dhanalakshmi_store.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        tamilName TEXT NOT NULL,
        category TEXT NOT NULL,
        imageUrl TEXT NOT NULL,
        stock INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        billId TEXT PRIMARY KEY,
        dateTime TEXT NOT NULL,
        itemNames TEXT NOT NULL,
        amount REAL NOT NULL,
        paymentMode TEXT NOT NULL,
        customerPhone TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        imagePath TEXT,
        createdDate TEXT NOT NULL
      )
    ''');

    for (var item in defaultCatalog) {
      await db.insert('products', item.toMap());
    }
  }

  Future<List<ProductItem>> getAllProducts() async {
    final db = await instance.database;
    final result = await db.query('products');
    return result.map((json) => ProductItem.fromMap(json)).toList();
  }

  Future<int> insertProduct(ProductItem item) async {
    final db = await instance.database;
    return await db.insert('products', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateProduct(ProductItem item) async {
    final db = await instance.database;
    return await db.update('products', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteProduct(String id) async {
    final db = await instance.database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSale(SaleRecord sale) async {
    final db = await instance.database;
    return await db.insert('sales', sale.toMap());
  }

  Future<List<SaleRecord>> getAllSales() async {
    final db = await instance.database;
    final result = await db.query('sales', orderBy: 'dateTime DESC');
    return result.map((json) => SaleRecord.fromMap(json)).toList();
  }

  Future<List<String>> getAllUniqueCustomerPhones() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT DISTINCT customerPhone FROM sales WHERE customerPhone IS NOT NULL AND customerPhone != '' AND LENGTH(customerPhone) >= 10",
    );
    return result.map((r) => r['customerPhone'] as String).toList();
  }

  Future<int> saveAd(String message, String? imagePath) async {
    final db = await instance.database;
    return await db.insert('ads', {
      'message': message,
      'imagePath': imagePath,
      'createdDate': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getLatestAd() async {
    final db = await instance.database;
    final result = await db.query('ads', orderBy: 'id DESC', limit: 1);
    if (result.isNotEmpty) return result.first;
    return null;
  }
}

// ----------------- Models -----------------
class ProductItem {
  final String id;
  String tamilName;
  String category;
  String imageUrl;
  int stock;

  ProductItem({
    required this.id,
    required this.tamilName,
    required this.category,
    required this.imageUrl,
    required this.stock,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'tamilName': tamilName,
        'category': category,
        'imageUrl': imageUrl,
        'stock': stock,
      };

  factory ProductItem.fromMap(Map<String, dynamic> map) => ProductItem(
        id: map['id'],
        tamilName: map['tamilName'],
        category: map['category'],
        imageUrl: map['imageUrl'],
        stock: map['stock'],
      );
}

class SaleRecord {
  final String billId;
  final DateTime dateTime;
  final List<String> itemNames;
  final double amount;
  final String paymentMode;
  final String? customerPhone;

  SaleRecord({
    required this.billId,
    required this.dateTime,
    required this.itemNames,
    required this.amount,
    required this.paymentMode,
    this.customerPhone,
  });

  Map<String, dynamic> toMap() => {
        'billId': billId,
        'dateTime': dateTime.toIso8601String(),
        'itemNames': itemNames.join(', '),
        'amount': amount,
        'paymentMode': paymentMode,
        'customerPhone': customerPhone ?? '',
      };

  factory SaleRecord.fromMap(Map<String, dynamic> map) => SaleRecord(
        billId: map['billId'],
        dateTime: DateTime.parse(map['dateTime']),
        itemNames: (map['itemNames'] as String).split(', '),
        amount: (map['amount'] as num).toDouble(),
        paymentMode: map['paymentMode'],
        customerPhone: map['customerPhone'],
      );
}

final List<ProductItem> defaultCatalog = [
  ProductItem(id: 'b1', tamilName: 'பித்தளை டம்ளர் செட்', category: 'பித்தளை', imageUrl: 'assets/images/b1.jpg', stock: 40),
  ProductItem(id: 'b2', tamilName: 'பித்தளை தட்டு', category: 'பித்தளை', imageUrl: 'assets/images/b2.jpg', stock: 8), // Alert
  ProductItem(id: 'b3', tamilName: 'பித்தளை சமையல் பாத்திரம்', category: 'பித்தளை', imageUrl: 'assets/images/b3.jpg', stock: 3), // Critical
  ProductItem(id: 'b4', tamilName: 'பித்தளை கரண்டி செட்', category: 'பித்தளை', imageUrl: 'assets/images/b4.jpg', stock: 50),
  ProductItem(id: 'a1', tamilName: 'அலுமினியம் டம்ளர் செட்', category: 'அலுமினியம்', imageUrl: 'assets/images/a1.jpg', stock: 50),
  ProductItem(id: 'a2', tamilName: 'அலுமினியம் தட்டு', category: 'அலுமினியம்', imageUrl: 'assets/images/a2.jpg', stock: 6), // Alert
  ProductItem(id: 'a3', tamilName: 'அலுமினியம் சமையல் பாத்திரம்', category: 'அலுமினியம்', imageUrl: 'assets/images/a3.jpg', stock: 2), // Critical
  ProductItem(id: 'a4', tamilName: 'அலுமினியம் கரண்டி செட்', category: 'அலுமினியம்', imageUrl: 'assets/images/a4.jpg', stock: 75),
  ProductItem(id: 's1', tamilName: 'சில்வர் டம்ளர் செட்', category: 'எவர்சில்வர்', imageUrl: 'assets/images/s1.jpg', stock: 80),
  ProductItem(id: 's2', tamilName: 'சில்வர் தட்டு', category: 'எவர்சில்வர்', imageUrl: 'assets/images/s2.jpg', stock: 70),
  ProductItem(id: 's3', tamilName: 'சில்வர் சமையல் பாத்திரம்', category: 'எவர்சில்வர்', imageUrl: 'assets/images/s3.jpg', stock: 4), // Critical
  ProductItem(id: 's4', tamilName: 'சில்வர் கரண்டி செட்', category: 'எவர்சில்வர்', imageUrl: 'assets/images/s4.jpg', stock: 90),
  ProductItem(id: 'g1', tamilName: 'பிரஷர் குக்கர் (Pressure Cooker)', category: 'பிற பொருட்கள்', imageUrl: 'assets/images/g1.jpg', stock: 9), // Alert
  ProductItem(id: 'g2', tamilName: 'மிக்ஸி ஜார் (Mixer Jar)', category: 'பிற பொருட்கள்', imageUrl: 'assets/images/g2.jpg', stock: 15),
  ProductItem(id: 'g3', tamilName: 'நான்-ஸ்டிக் தவா (Non-stick Pan)', category: 'பிற பொருட்கள்', imageUrl: 'assets/images/g3.jpg', stock: 25),
];

// ----------------- Notifications -----------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> initNotificationService() async {
  tz.initializeTimeZones();
  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(const InitializationSettings(android: androidSettings));
  await scheduleSunday9PmNotification();
}

Future<void> scheduleSunday9PmNotification() async {
  final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
  tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
  while (scheduledDate.weekday != DateTime.sunday || scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sunday_ads_channel',
    'ஞாயிறு விளம்பரங்கள்',
    importance: Importance.max,
    priority: Priority.high,
  );

  await flutterLocalNotificationsPlugin.zonedSchedule(
    101,
    'தனலட்சுமி பாத்திரக்கடை - வார விளம்பரம்',
    'ஞாயிறு இரவு 9 மணி: பதிவுசெய்த வாடிக்கையாளர்களுக்கு விளம்பர படத்தை அனுப்பவும்!',
    scheduledDate,
    const NotificationDetails(android: androidDetails),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initNotificationService();
  } catch (_) {}
  runApp(const DhanalakshmiApp());
}

class DhanalakshmiApp extends StatelessWidget {
  const DhanalakshmiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:'தனலட்சுமி பாத்திரக்கடை',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgSurface,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary),
      ),
      home: const MainDashboardScreen(),
    );
  }
}

// ----------------- 1. முகப்புத் திரை & Hero Banner -----------------
class MainDashboardScreen extends StatelessWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: AppColors.primaryDark.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8)),
                  ],
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A1E08), AppColors.primary, Color(0xFFB56535)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFFFFD1A4), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.auto_awesome, color: Color(0xFFFFD54F), size: 20),
                          SizedBox(width: 8),
                          Text('• பாரம்பரியம் மற்றும் தரம் •', style: TextStyle(color: Color(0xFFFFE082), fontSize: 13, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.auto_awesome, color: Color(0xFFFFD54F), size: 20),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'தனலட்சுமி பாத்திரக்கடை',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.black45, offset: Offset(0, 2), blurRadius: 4)],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                        child: const Text(
                          'பித்தளை • அலுமினியம் • எவர்சில்வர் • சமையலறை உபகரணங்கள்',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.05,
                  children: [
                    _buildNavCard(
                      context,
                      title: 'புதிய விற்பனை',
                      sub: 'New Sale',
                      icon: Icons.point_of_sale_rounded,
                      color: AppColors.primary,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleScreen())),
                    ),
                    _buildNavCard(
                      context,
                      title: 'இன்றைய விற்பனை',
                      sub: 'Today Sales',
                      icon: Icons.calendar_today_rounded,
                      color: Colors.teal.shade700,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesViewScreen(viewType: 'today'))),
                    ),
                    _buildNavCard(
                      context,
                      title: 'வார விற்பனை',
                      sub: 'Weekend Review',
                      icon: Icons.date_range_rounded,
                      color: Colors.blue.shade800,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesViewScreen(viewType: 'week'))),
                    ),
                    _buildNavCard(
                      context,
                      title: 'மாத அறிக்கை',
                      sub: 'Month End Summary',
                      icon: Icons.bar_chart_rounded,
                      color: Colors.purple.shade700,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonthEndScreen())),
                    ),
                    _buildNavCard(
                      context,
                      title: 'இருப்பு மேலாண்மை',
                      sub: 'Stock Management',
                      icon: Icons.inventory_2_rounded,
                      color: const Color(0xFFC65D23),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockManagementScreen())),
                    ),
                    _buildNavCard(
                      context,
                      title: 'விளம்பரம் சேர்த்தல்',
                      sub: 'Weekly Broadcast',
                      icon: Icons.campaign_rounded,
                      color: const Color(0xFFAD1457),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvertisementScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavCard(
    BuildContext context, {
    required String title,
    required String sub,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.18), width: 1.2),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 10),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------- 2. புதிய விற்பனை (New Sale) -----------------
class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  List<ProductItem> products = [];
  final Set<ProductItem> selectedProducts = {};
  String selectedCategory = 'அனைத்தும்';
  bool isLoading = true;

  final List<String> categories = ['அனைத்தும்', 'பித்தளை', 'அலுமினியம்', 'எவர்சில்வர்', 'பிற பொருட்கள்'];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final list = await DatabaseService.instance.getAllProducts();
    setState(() {
      products = list;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = selectedCategory == 'அனைத்தும்'
        ? products
        : products.where((p) => p.category == selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('பொருட்கள் தேர்வு'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: AppColors.cardBg,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: categories.map((cat) {
                        final isSel = selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSel,
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryContainer,
                            labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textDark, fontWeight: FontWeight.bold),
                            showCheckmark: false,
                            onSelected: (_) => setState(() => selectedCategory = cat),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isPicked = selectedProducts.contains(item);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isPicked) {
                              selectedProducts.remove(item);
                            } else {
                              selectedProducts.add(item);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isPicked ? AppColors.primary : Colors.black12,
                              width: isPicked ? 2.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _renderProductImage(item.imageUrl),
                                      if (isPicked)
                                        Container(
                                          color: AppColors.primary.withOpacity(0.35),
                                          child: const Center(
                                            child: CircleAvatar(
                                              backgroundColor: Colors.white,
                                              child: Icon(Icons.check, color: AppColors.primary),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  children: [
                                    Text(
                                      item.tamilName,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    _buildStockBadge(item.stock),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: AppColors.cardBg,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: selectedProducts.isEmpty
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillingScreen(selectedItems: selectedProducts.toList()),
                    ),
                  ),
          child: Text('பணம் செலுத்துதல் (${selectedProducts.length} பொருட்கள்)'),
        ),
      ),
    );
  }

  Widget _buildStockBadge(int stock) {
    if (stock < 5) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppColors.criticalRed.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.criticalRed, size: 13),
            const SizedBox(width: 4),
            Text('இருப்பு: $stock (எச்சரிக்கை!)', style: const TextStyle(color: AppColors.criticalRed, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (stock < 10) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppColors.alertOrange.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: AppColors.alertOrange, size: 13),
            const SizedBox(width: 4),
            Text('இருப்பு: $stock (கவனிக்கவும்)', style: const TextStyle(color: AppColors.alertOrange, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else {
      return Text('இருப்பு: $stock', style: const TextStyle(color: AppColors.textMuted, fontSize: 11));
    }
  }

  Widget _renderProductImage(String path) {
    if (path.startsWith('assets/')) {
      return Image.asset(path, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.kitchen, size: 40));
    } else {
      return Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.kitchen, size: 40));
    }
  }
}

// ----------------- 3. பணம் & ரசீது திரை (Dual Checkout) -----------------
class BillingScreen extends StatefulWidget {
  final List<ProductItem> selectedItems;
  const BillingScreen({super.key, required this.selectedItems});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  String paymentMode = 'ரொக்கம்';
  bool isSyncing = false;

  String get upiUrl {
    final amt = amountController.text.trim();
    return "upi://pay?pa=${AppConstants.shopUpiId}&pn=${AppConstants.shopName}&am=$amt&cu=INR";
  }

  Future<void> _processSale({required bool sendWhatsApp}) async {
    final amt = double.tryParse(amountController.text) ?? 0.0;
    final phone = phoneController.text.trim();

    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('சரியான தொகையை உள்ளிடவும்!')));
      return;
    }

    if (sendWhatsApp && phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('வாட்ஸ்அப் ரசீது அனுப்ப 10 இலக்க எண் அவசியம்!')));
      return;
    }

    setState(() => isSyncing = true);

    for (var item in widget.selectedItems) {
      item.stock = (item.stock > 0) ? item.stock - 1 : 0;
      await DatabaseService.instance.updateProduct(item);
    }

    final billNo = "BILL-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    final sale = SaleRecord(
      billId: billNo,
      dateTime: DateTime.now(),
      itemNames: widget.selectedItems.map((e) => e.tamilName).toList(),
      amount: amt,
      paymentMode: paymentMode,
      customerPhone: phone.isNotEmpty ? phone : null,
    );
    await DatabaseService.instance.insertSale(sale);

    _syncToOwnerGoogleDrive(sale);

    if (sendWhatsApp && phone.isNotEmpty) {
      final itemsText = widget.selectedItems.map((e) => "• ${e.tamilName}").join("\n");
      final message = '''
*தனலட்சுமி பாத்திரக்கடை*
ரசீது எண்: $billNo
தேதி: ${DateFormat('dd-MM-yyyy hh:mm a').format(sale.dateTime)}
----------------------------
வாங்கிய பொருட்கள்:
$itemsText
----------------------------
கட்டண முறை: $paymentMode
*மொத்த தொகை: ₹$amt*
----------------------------
நன்றி! மீண்டும் வருக!
''';
      final cleanPhone = phone.startsWith('91') ? phone : '91$phone';
      final uri = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}");
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    setState(() => isSyncing = false);
    if (mounted) {
      Navigator.popUntil(context, (r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('விற்பனை வெற்றிகரமாக பதிவு செய்யப்பட்டது!')),
      );
    }
  }

  void _syncToOwnerGoogleDrive(SaleRecord sale) async {
    try {
      if (AppConstants.appsScriptUrl.contains("SampleUrlHere")) return;
      await http.post(
        Uri.parse(AppConstants.appsScriptUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "billId": sale.billId,
          "dateTime": DateFormat('dd-MM-yyyy HH:mm:ss').format(sale.dateTime),
          "items": sale.itemNames.join(", "),
          "amount": sale.amount,
          "paymentMode": sale.paymentMode,
          "customerPhone": sale.customerPhone,
        }),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('தொகை & ரசீது'), backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryContainer),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('தேர்ந்தெடுக்கப்பட்ட பொருட்கள்:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const SizedBox(height: 6),
                  ...widget.selectedItems.map((e) => Text('✔ ${e.tamilName}')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'மொத்த தொகை (₹)',
                prefixIcon: Icon(Icons.currency_rupee, color: AppColors.primary),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'வாடிக்கையாளர் வாட்ஸ்அப் எண் (விருப்பப்பட்டால் மட்டும்)',
                hintText: '9876543210',
                prefixIcon: Icon(Icons.phone, color: AppColors.primary),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('ரொக்கம் (Cash)')),
                    selected: paymentMode == 'ரொக்கம்',
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(color: paymentMode == 'ரொக்கம்' ? Colors.white : AppColors.textDark, fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => paymentMode = 'ரொக்கம்'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('யு.பி.ஐ QR (Scanner)')),
                    selected: paymentMode == 'யு.பி.ஐ QR',
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(color: paymentMode == 'யு.பி.ஐ QR' ? Colors.white : AppColors.textDark, fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => paymentMode = 'யு.பி.ஐ QR'),
                  ),
                ),
              ],
            ),
            if (paymentMode == 'யு.பி.ஐ QR') ...[
              const SizedBox(height: 14),
              Center(
                child: (amountController.text.isNotEmpty && (double.tryParse(amountController.text) ?? 0) > 0)
                    ? QrImageView(data: upiUrl, size: 180)
                    : const Text('QR உருவாக்க தொகையை உள்ளிடவும்', style: TextStyle(color: Colors.red)),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('வாட்ஸ்அப்பில் ரசீது அனுப்பி முடிக்க'),
              onPressed: isSyncing ? null : () => _processSale(sendWhatsApp: true),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.save_rounded),
              label: const Text('கடையின் கணக்கில் மட்டும் சேமித்து முடிக்க'),
              onPressed: isSyncing ? null : () => _processSale(sendWhatsApp: false),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------- 4. இருப்பு மேலாண்மை (Stock Management With 2-Tier Warnings) -----------------
class StockManagementScreen extends StatefulWidget {
  const StockManagementScreen({super.key});

  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen> {
  List<ProductItem> stockList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStocks();
  }

  Future<void> _fetchStocks() async {
    final data = await DatabaseService.instance.getAllProducts();
    setState(() {
      stockList = data;
      isLoading = false;
    });
  }

  void _confirmDelete(ProductItem item) {
    showDialog(
      context: context,
      builder: (ctx1) => AlertDialog(
        title: const Text('எச்சரிக்கை! (Warning)'),
        content: const Text('இப்பொருளின் விவரங்கள் நீக்கப்பட்டால் மீண்டும் பெற முடியாது!\n(The records will not be restored if deleted)'),
        actions: [
          TextButton(child: const Text('ரத்து செய்'), onPressed: () => Navigator.pop(ctx1)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
            child: const Text('சரிபார்க்கவும் (Check before deleting)'),
            onPressed: () {
              Navigator.pop(ctx1);
              showDialog(
                context: context,
                builder: (ctx2) => AlertDialog(
                  title: const Text('உறுதிப்படுத்தவும்'),
                  content: Text('நீங்கள் "${item.tamilName}" பொருளை நிரந்தரமாக நீக்க விரும்புகிறீர்களா?'),
                  actions: [
                    TextButton(child: const Text('வேண்டாம்'), onPressed: () => Navigator.pop(ctx2)),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      child: const Text('அழிக்க தொடரவும் (Proceed)'),
                      onPressed: () async {
                        await DatabaseService.instance.deleteProduct(item.id);
                        Navigator.pop(ctx2);
                        _fetchStocks();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAddEditProductDialog([ProductItem? existing]) {
    final nameController = TextEditingController(text: existing?.tamilName ?? '');
    final stockController = TextEditingController(text: existing != null ? existing.stock.toString() : '10');
    String selectedCat = existing?.category ?? 'பித்தளை';
    String imagePath = existing?.imageUrl ?? 'assets/images/b1.jpg';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? 'புதிய பாத்திரம் சேர்க்க' : 'இருப்பு திருத்துதல்',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'பொருளின் தமிழ் பெயர்', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCat,
                  decoration: const InputDecoration(labelText: 'பிரிவு (Category)', border: OutlineInputBorder()),
                  items: ['பித்தளை', 'அலுமினியம்', 'எவர்சில்வர்', 'பிற பொருட்கள்']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setModalState(() => selectedCat = val!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'இருப்பு எண்ணிக்கை (Stock Count)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('படத்தை மாற்ற / சேர்க்க (Gallery)'),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      setModalState(() => imagePath = picked.path);
                    }
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(existing == null ? 'சேமிக்க' : 'புதுப்பிக்க'),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final st = int.tryParse(stockController.text) ?? 0;
                    if (name.isEmpty) return;

                    final item = ProductItem(
                      id: existing?.id ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
                      tamilName: name,
                      category: selectedCat,
                      imageUrl: imagePath,
                      stock: st,
                    );

                    if (existing == null) {
                      await DatabaseService.instance.insertProduct(item);
                    } else {
                      await DatabaseService.instance.updateProduct(item);
                    }
                    Navigator.pop(ctx);
                    _fetchStocks();
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('இருப்பு மேலாண்மை (Stock Suite)'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('புதிய பாத்திரம்'),
        onPressed: () => _openAddEditProductDialog(),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: stockList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = stockList[index];
                return Card(
                  color: AppColors.cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryContainer,
                            child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ),
                          title: Text(item.tamilName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('பிரிவு: ${item.category}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _openAddEditProductDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.red),
                                onPressed: () => _confirmDelete(item),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 8),
                        // Dual Warning Indicators
                        _buildWarningBanner(item.stock),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildWarningBanner(int stock) {
    if (stock < 5) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.criticalRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.warning, color: AppColors.criticalRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'அவசர இருப்பு எச்சரிக்கை! ($stock மட்டுமே உள்ளது - உடனே ஆர்டர் செய்யவும்)',
                style: const TextStyle(color: AppColors.criticalRed, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    } else if (stock < 10) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.alertOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.notifications_active, color: AppColors.alertOrange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'கவனிக்கவும்! இருப்பு 10-க்கும் குறைவாக உள்ளது ($stock மீதம்)',
                style: const TextStyle(color: AppColors.alertOrange, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    } else {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 6),
          Text('போதுமான இருப்பு உள்ளது: $stock', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      );
    }
  }
}

// ----------------- 5. விளம்பரம் சேர்த்தல் (Upload Image & Text Ads) -----------------
class AdvertisementScreen extends StatefulWidget {
  const AdvertisementScreen({super.key});

  @override
  State<AdvertisementScreen> createState() => _AdvertisementScreenState();
}

class _AdvertisementScreenState extends State<AdvertisementScreen> {
  final messageController = TextEditingController(
    text: "வணக்கம்! தனலட்சுமி பாத்திரக்கடையின் சிறப்பு வார தள்ளுபடி சலுகைகள் இப்போது ஆரம்பம்! நேரில் வந்து பயன்பெறுங்கள்!",
  );
  String? selectedImagePath;
  List<String> customerPhones = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final list = await DatabaseService.instance.getAllUniqueCustomerPhones();
    final latestAd = await DatabaseService.instance.getLatestAd();
    setState(() {
      customerPhones = list;
      if (latestAd != null) {
        messageController.text = latestAd['message'];
        selectedImagePath = latestAd['imagePath'];
      }
      isLoading = false;
    });
  }

  Future<void> _pickAdImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => selectedImagePath = picked.path);
      await DatabaseService.instance.saveAd(messageController.text, picked.path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('விளம்பர படம் சேமிக்கப்பட்டது!')));
    }
  }

  // Broadcasts image + text to customer via WhatsApp
  void _broadcastAd(String phone) async {
    final msg = messageController.text.trim();

    if (selectedImagePath != null && File(selectedImagePath!).existsSync()) {
      // Direct share with image and text
      await Share.shareXFiles(
        [XFile(selectedImagePath!)],
        text: "*தனலட்சுமி பாத்திரக்கடை*\n$msg",
      );
    } else {
      // Fallback text message via WhatsApp Direct
      final clean = phone.startsWith('91') ? phone : '91$phone';
      final text = Uri.encodeComponent("*தனலட்சுமி பாத்திரக்கடை*\n$msg");
      final uri = Uri.parse("https://wa.me/$clean?text=$text");
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('விளம்பரம் சேர்த்தல் (Weekly Ads)'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: const Color(0xFFFCE4EC),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        '💡 ஒவ்வொரு ஞாயிறு இரவு 9:00 மணிக்கு மொபைல் திரையில் நினைவூட்டல் தோன்றும். இங்கு வாடிக்கையாளர்களுக்கு விளம்பர படம் மற்றும் செய்தியை 1-க்ளிக் மூலம் பகிரலாம்.',
                        style: TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Image Upload Area
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryContainer, width: 2),
                    ),
                    child: selectedImagePath != null && File(selectedImagePath!).existsSync()
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(File(selectedImagePath!), fit: BoxFit.cover),
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  child: IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white),
                                    onPressed: _pickAdImage,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_photo_alternate_rounded, size: 50, color: AppColors.primary),
                              const SizedBox(height: 8),
                              const Text('விளம்பர போஸ்டர் படம் சேர்க்க', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                                onPressed: _pickAdImage,
                                child: const Text('படத்தை தேர்ந்தெடுக்க (Gallery)'),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'விளம்பர செய்தி (Offer Message)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      DatabaseService.instance.saveAd(val, selectedImagePath);
                    },
                  ),
                  const SizedBox(height: 18),

                  Text(
                    'பதிவுசெய்த வாடிக்கையாளர்கள் (${customerPhones.length} எண்கள்):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),

                  if (customerPhones.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('இன்னும் வாடிக்கையாளர் எண்கள் சேகரிக்கப்படவில்லை.', style: TextStyle(color: Colors.grey)),
                    ),

                  ...customerPhones.map((ph) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.phone_android, color: AppColors.accentGreen),
                          title: Text(ph, style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('பகிர் (WhatsApp)'),
                            onPressed: () => _broadcastAd(ph),
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}

// ----------------- 6. விற்பனை அறிக்கைகள் -----------------
class SalesViewScreen extends StatelessWidget {
  final String viewType;
  const SalesViewScreen({super.key, required this.viewType});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(viewType == 'today' ? 'இன்றைய விற்பனை' : 'வார விற்பனை அறிக்கை'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<SaleRecord>>(
        future: DatabaseService.instance.getAllSales(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final all = snapshot.data!;
          final filtered = viewType == 'today'
              ? all.where((s) => s.dateTime.year == now.year && s.dateTime.month == now.month && s.dateTime.day == now.day).toList()
              : all.where((s) => s.dateTime.isAfter(now.subtract(const Duration(days: 7)))).toList();

          final total = filtered.fold<double>(0, (sum, i) => sum + i.amount);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.primaryContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('மொத்த ரசீதுகள்: ${filtered.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('மொத்த வரவு: ₹$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('விற்பனைகள் இல்லை.'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final s = filtered[idx];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text('${s.billId} • ₹${s.amount}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${s.itemNames.join(", ")}\nமுறை: ${s.paymentMode} | எண்: ${s.customerPhone ?? "இல்லை"}'),
                              trailing: Text(DateFormat('dd/MM hh:mm a').format(s.dateTime), style: const TextStyle(fontSize: 11)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MonthEndScreen extends StatelessWidget {
  const MonthEndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('மாத இறுதி அறிக்கை & இருப்பு'), backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      body: FutureBuilder(
        future: Future.wait([
          DatabaseService.instance.getAllSales(),
          DatabaseService.instance.getAllProducts(),
        ]),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final sales = (snapshot.data![0] as List<SaleRecord>)
              .where((s) => s.dateTime.year == now.year && s.dateTime.month == now.month)
              .toList();
          final products = snapshot.data![1] as List<ProductItem>;
          final monthTotal = sales.fold<double>(0, (sum, i) => sum + i.amount);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: AppColors.primaryDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('இந்த மாத மொத்த வரவு', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text('₹ $monthTotal', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                        Text('மொத்த பில்கள்: ${sales.length}', style: const TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('கடை நேரடி இருப்பு நிலை (Stock):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...products.map((item) => Card(
                      child: ListTile(
                        title: Text(item.tamilName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('பிரிவு: ${item.category}'),
                        trailing: Text(
                          'இருப்பு: ${item.stock}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: item.stock < 5
                                ? AppColors.criticalRed
                                : (item.stock < 10 ? AppColors.alertOrange : AppColors.primary),
                          ),
                        ),
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}