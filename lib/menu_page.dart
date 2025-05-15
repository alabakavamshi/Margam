
// ignore_for_file: use_build_context_synchronously, avoid_types_as_parameter_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:menu_web/order_history.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MenuPage extends StatefulWidget {
  final String managerCode;

  const MenuPage({super.key, required this.managerCode});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String? _managerId;
  Map<String, dynamic>? _stallsData;
  String? _errorMessage;
  final Map<String, Map<String, dynamic>> _cart = {};
  String? _lastOrderId;
  String? _customerName;
  String? _customerPhone;
  String? _customerId;
  int? _selectedTable;
  bool _isLoadingManager = true;
  bool _hasManagerError = false;
  bool _isPaymentLoading = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static final String _razorpayKeyId = 'rzp_test_p9V24bWT3a35ky';

  @override
  void initState() {
    super.initState();
    _showCustomerInfoDialog();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _getItemName(Map<String, dynamic> item, String context) {
    final name = item['itemName']?.toString() ?? 'Unknown Item';
    if (name.isEmpty || name.toLowerCase() == 'unknown item') {
      debugPrint('Invalid itemName in $context: $item');
      return 'Unknown Item';
    }
    return name;
  }

  Future<String?> _getCustomerIdByPhone(String phone) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('customers')
          .where('phone', isEqualTo: phone)
          .where('managerCode', isEqualTo: widget.managerCode)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        if (doc['name'] != _nameController.text.trim()) {
          await FirebaseFirestore.instance
              .collection('customers')
              .doc(doc.id)
              .update({'name': _nameController.text.trim()});
        }
        return doc.id;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching customer by phone: $e');
      _showError('Failed to check existing customer: $e');
      return null;
    }
  }

  void _showCustomerInfoDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Enter Your Details',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade700,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(color: Colors.white),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade700,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (!RegExp(r'^\d{10}$').hasMatch(value)) {
                      return 'Phone number must be exactly 10 digits (e.g., 9876543210)';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final phone = _phoneController.text.trim();
                  final name = _nameController.text.trim();
                  String? existingCustomerId = await _getCustomerIdByPhone(phone);
                  try {
                    if (existingCustomerId != null) {
                      setState(() {
                        _customerId = existingCustomerId;
                        _customerName = name;
                        _customerPhone = phone;
                      });
                      debugPrint('Existing customer found: ID=$_customerId');
                    } else {
                      final newCustomerId = const Uuid().v4();
                      await FirebaseFirestore.instance
                          .collection('customers')
                          .doc(newCustomerId)
                          .set({
                        'customerId': newCustomerId,
                        'name': name,
                        'phone': phone,
                        'createdAt': Timestamp.now(),
                        'managerCode': widget.managerCode,
                      });
                      setState(() {
                        _customerId = newCustomerId;
                        _customerName = name;
                        _customerPhone = phone;
                      });
                      debugPrint('New customer saved: ID=$_customerId, Name=$_customerName, Phone=$_customerPhone');
                    }
                    Navigator.pop(context);
                    await _fetchManagerData();
                  } catch (e) {
                    _showError('Failed to save customer details: $e');
                    debugPrint('Error saving customer: $e');
                  }
                }
              },
              child: Text(
                'Submit',
                style: GoogleFonts.poppins(
                  color: Colors.teal.shade400,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _fetchManagerData() async {
    setState(() {
      _isLoadingManager = true;
      _hasManagerError = false;
      _errorMessage = null;
    });
    try {
      debugPrint('Querying managers for managerCode: ${widget.managerCode}');
      final query = await FirebaseFirestore.instance
          .collection('managers')
          .where('managerCode', isEqualTo: widget.managerCode)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        setState(() {
          _managerId = doc.id;
          _stallsData = doc['stalls'] as Map<String, dynamic>? ?? {};
          _isLoadingManager = false;
        });
        debugPrint('Manager found: ID=$_managerId, Stalls=$_stallsData');
      } else {
        setState(() {
          _errorMessage = 'No manager found for code: ${widget.managerCode}';
          _isLoadingManager = false;
          _hasManagerError = true;
        });
        _showError(_errorMessage!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching manager: $e';
        _isLoadingManager = false;
        _hasManagerError = true;
      });
      _showError(_errorMessage!);
      debugPrint('Error fetching manager: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
          ),
          backgroundColor: Colors.red.shade500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
          ),
          backgroundColor: Colors.teal.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showBill(String orderId, bool isDesktop) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.grey.shade800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: isDesktop ? 600 : double.infinity,
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('orderId', isEqualTo: orderId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.teal)));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error loading bill: ${snapshot.error}',
                    style: GoogleFonts.poppins(color: Colors.red.shade500, fontSize: 16),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text(
                    'Order not found.',
                    style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 16),
                  ),
                );
              }
              final orders = snapshot.data!.docs;
              double grandTotal = 0;
              List<Widget> billItems = [];
              for (var order in orders) {
                final data = order.data() as Map<String, dynamic>;
                final items = data['items'] as List<dynamic>;
                final total = (data['total'] as num?)?.toDouble() ?? 0.0;
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                final customerName = data['customerName'] as String?;
                final customerPhone = data['customerPhone'] as String?;
                final table = data['table'] as int?;
                final stallName = data['stallName'] as String?;
                grandTotal += total;
                billItems.add(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order for ${stallName ?? 'Unknown Stall'}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (createdAt != null)
                        Text(
                          'Placed on: ${createdAt.toString().substring(0, 16)}',
                          style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                        ),
                      if (table != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Table: $table',
                            style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                          ),
                        ),
                      if (customerName != null && customerPhone != null) ...[
                        Text(
                          'Name: $customerName',
                          style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                        ),
                        Text(
                          'Phone: $customerPhone',
                          style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ...items.map((item) {
                        final itemNameStr = _getItemName(item, 'bill_items');
                        final quantity = item['quantity'] as int? ?? 1;
                        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                        final itemTotal = price * quantity;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                          title: Text(
                            itemNameStr,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            '$quantity x ₹${price.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 12),
                          ),
                          trailing: Text(
                            '₹${itemTotal.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.teal.shade400,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }),
                      const Divider(color: Colors.grey),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Subtotal:',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${total.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.teal.shade400,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bill for Order #$orderId',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...billItems,
                    const Divider(color: Colors.grey),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Grand Total:',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '₹${grandTotal.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.teal.shade400,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _lastOrderId = null;
                        });
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Close',
                        style: GoogleFonts.poppins(
                          color: Colors.teal.shade400,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _addToCart(Map<String, dynamic> item) {
    setState(() {
      final itemId = item['id'] as String? ?? '';
      final itemNameStr = _getItemName(item, 'add_to_cart');
      final stallName = item['stallName']?.toString() ?? 'Unknown Stall';
      if (itemId.isEmpty) {
        _showError('Cannot add item: Missing item ID');
        debugPrint('Error: Attempted to add item with empty ID: $item');
        return;
      }
      if (itemNameStr == 'Unknown Item') {
        _showError('Cannot add item: Invalid item name');
        debugPrint('Error: Invalid itemName in addToCart: $item');
        return;
      }
      final cartItem = {
        'id': itemId,
        'itemName': itemNameStr,
        'stallName': stallName,
        'price': (item['price'] as num?)?.toDouble() ?? 0.0,
        'description': item['description']?.toString() ?? '',
        'isAvailable': item['isAvailable'] as bool? ?? false,
        'managerCode': item['managerCode']?.toString() ?? '',
        'quantity': 1,
      };
      if (_cart.containsKey(itemId)) {
        _cart[itemId]!['quantity'] += 1;
      } else {
        _cart[itemId] = cartItem;
      }
      debugPrint('Added to cart: $itemNameStr (ID: $itemId, Stall: $stallName)');
    });
    _showSuccess('Added to cart');
  }

  void _removeFromCart(String itemId) {
    setState(() {
      if (_cart.containsKey(itemId)) {
        _cart[itemId]!['quantity'] -= 1;
        if (_cart[itemId]!['quantity'] <= 0) {
          _cart.remove(itemId);
        }
        debugPrint('Removed from cart: ID=$itemId, New quantity=${_cart[itemId]?['quantity'] ?? 0}');
      }
    });
  }

  Future<void> _initiatePaymentForOrder(String orderId, double amount) async {
    if (_customerId == null || _customerPhone == null) {
      _showError('Customer details missing. Please re-enter your details.');
      return;
    }
    if (_razorpayKeyId == 'YOUR_RAZORPAY_KEY_ID') {
      _showError('Razorpay Key ID is not configured. Contact support.');
      return;
    }
    setState(() {
      _isPaymentLoading = true;
    });
    try {
      // Show WebView with Razorpay checkout
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          child: SizedBox(
            width: 600,
            height: 500,
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Razorpay Payment</title>
</head>
<body>
    <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
    <script>
        var options = {
            "key": "$_razorpayKeyId",
            "amount": ${(amount * 100).toInt()},
            "currency": "INR",
            "name": "Margam's Kitchen",
            "description": "Payment for order #$orderId",
            "handler": function (response) {
                // Post message to Flutter
                window.flutter_inappwebview.callHandler('paymentSuccess', {
                    payment_id: response.razorpay_payment_id,
                    order_id: response.razorpay_order_id,
                    signature: response.razorpay_signature
                });
            },
            "prefill": {
                "contact": "$_customerPhone",
                "email": "customer@example.com"
            },
            "notes": {
                "orderId": "$orderId",
                "customerId": "$_customerId",
                "managerCode": "${widget.managerCode}"
            },
            "theme": {
                "color": "#26A69A"
            },
            "modal": {
                "ondismiss": function() {
                    window.flutter_inappwebview.callHandler('paymentCancelled');
                }
            }
        };
        var rzp = new Razorpay(options);
        rzp.on('payment.failed', function (response) {
            window.flutter_inappwebview.callHandler('paymentError', {
                code: response.error.code,
                message: response.error.description
            });
        });
        rzp.open();
    </script>
</body>
</html>
                ''',
              ),
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'paymentSuccess',
                  callback: (args) {
                    final response = args[0] as Map<String, dynamic>;
                    _handlePaymentSuccess(
                      response['payment_id'],
                      response['order_id'],
                      response['signature'],
                    );
                    Navigator.pop(dialogContext);
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: 'paymentError',
                  callback: (args) {
                    final response = args[0] as Map<String, dynamic>;
                    _handlePaymentError(response['message']);
                    Navigator.pop(dialogContext);
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: 'paymentCancelled',
                  callback: (args) {
                    _handlePaymentError('Payment cancelled by user');
                    Navigator.pop(dialogContext);
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isPaymentLoading = false;
      });
      _showError('Failed to initiate payment: $e');
      debugPrint('Payment initiation error: $e');
    }
  }

  void _handlePaymentSuccess(String? paymentId, String? orderId, String? signature) {
    setState(() {
      _isPaymentLoading = false;
    });
    debugPrint('Payment success: PaymentID=$paymentId, OrderID=$orderId');
    _placeOrderAfterPayment(orderId, paymentId, signature);
    _showSuccess('Payment successful! View your bill.');
  }

  void _handlePaymentError(String message) {
    setState(() {
      _isPaymentLoading = false;
    });
    _showError('Payment failed: $message');
    debugPrint('Payment error: $message');
  }

  Future<void> _placeOrderAfterPayment(String? razorpayOrderId, String? paymentId, String? signature) async {
    if (_lastOrderId == null) {
      _showError('No order to process payment for.');
      debugPrint('Error: No lastOrderId set during payment');
      return;
    }
    try {
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('orderId', isEqualTo: _lastOrderId)
          .get();
      if (ordersSnapshot.docs.isEmpty) {
        _showError('Order not found.');
        debugPrint('Error: No orders found for orderId: $_lastOrderId');
        return;
      }
      for (var doc in ordersSnapshot.docs) {
        await doc.reference.update({
          'paymentStatus': 'completed',
          'razorpayPaymentId': paymentId,
          'razorpayOrderId': razorpayOrderId,
          'razorpaySignature': signature,
          'updatedAt': Timestamp.now(),
        });
        debugPrint('Updated order ${doc.id} with payment details: PaymentID=$paymentId');
      }
      setState(() {
        _isPaymentLoading = false;
      });
      debugPrint('Payment completed for order: $_lastOrderId');
    } catch (e) {
      setState(() {
        _isPaymentLoading = false;
      });
      _showError('Failed to update order with payment: $e');
      debugPrint('Error updating order with payment: $e');
    }
  }

  Future<void> _placeOrder(BuildContext modalContext, bool isDesktop) async {
    if (_customerId == null || _customerPhone == null || _selectedTable == null) {
      _showError('Please complete customer details and select a table');
      return;
    }
    final total = _cart.values.fold<double>(
      0,
      (sum, item) => sum + (item['price'] * item['quantity']),
    );
    if (total <= 0) {
      _showError('Cart total is invalid');
      debugPrint('Error: Invalid cart total: $total');
      return;
    }
    try {
      final orderIdGenerated = const Uuid().v4();
      final Map<String, List<Map<String, dynamic>>> itemsByStall = {};
      for (var item in _cart.values) {
        final stallName = item['stallName']?.toString() ?? 'Unknown Stall';
        final itemNameStr = _getItemName(item, 'place_order');
        if (stallName.isEmpty || stallName.toLowerCase() == 'unknown stall') {
          _showError('Invalid stall for item: $itemNameStr');
          debugPrint('Error: Invalid stallName for item: $item');
          return;
        }
        if (itemNameStr == 'Unknown Item') {
          _showError('Invalid item name: $itemNameStr');
          debugPrint('Error: Invalid itemName in placeOrder: $item');
          return;
        }
        if (!itemsByStall.containsKey(stallName)) {
          itemsByStall[stallName] = [];
        }
        itemsByStall[stallName]!.add({
          'itemId': item['id']?.toString() ?? '',
          'itemName': itemNameStr,
          'stallName': stallName,
          'price': (item['price'] as num?)?.toDouble() ?? 0.0,
          'quantity': item['quantity'] as int? ?? 1,
        });
      }
      if (itemsByStall.isEmpty) {
        _showError('No valid items in cart');
        debugPrint('Error: Empty itemsByStall');
        return;
      }
      for (var stallEntry in itemsByStall.entries) {
        final stallName = stallEntry.key;
        final stallItems = stallEntry.value;
        final cookQuery = await FirebaseFirestore.instance
            .collection('staff')
            .where('role', isEqualTo: 'Cook')
            .where('stallName', isEqualTo: stallName)
            .where('managerCode', isEqualTo: widget.managerCode)
            .limit(1)
            .get();
        if (cookQuery.docs.isEmpty) {
          _showError('No cook available for $stallName');
          debugPrint('Error: No cook found for stall: $stallName');
          return;
        }
        final cook = cookQuery.docs.first;
        final cookId = cook.id;
        final orderData = {
          'orderId': orderIdGenerated,
          'managerCode': widget.managerCode,
          'customerId': _customerId,
          'customerName': _customerName,
          'customerPhone': _customerPhone,
          'items': stallItems,
          'total': stallItems.fold<double>(
            0,
            (sum, item) => sum + (item['price'] * item['quantity']),
          ),
          'createdAt': Timestamp.now(),
          'status': 'pending',
          'cookId': cookId,
          'stallName': stallName,
          'table': _selectedTable,
          'paymentStatus': 'pending',
        };
        await FirebaseFirestore.instance
            .collection('orders')
            .doc('$orderIdGenerated-$stallName')
            .set(orderData);
        debugPrint('Order placed for $stallName: ID=$orderIdGenerated-$stallName, CookID=$cookId');
      }
      setState(() {
        _cart.clear();
        _lastOrderId = orderIdGenerated;
        _selectedTable = null;
      });
      Navigator.pop(modalContext);
      _showSuccess('Order submitted! You’ll be prompted to pay after preparation.');
      debugPrint('Order submitted: ID=$orderIdGenerated, Cart cleared');
    } catch (e) {
      _showError('Failed to submit order: $e');
      debugPrint('Error submitting order: $e');
    }
  }

  void _showCart(BuildContext context, bool isDesktop) {
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.grey.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(16),
            child: _buildCartContent(dialogContext, isDesktop),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.grey.shade800,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(16),
            child: _buildCartContent(modalContext, isDesktop, scrollController: scrollController),
          ),
        ),
      );
    }
  }

  Widget _buildCartContent(BuildContext modalContext, bool isDesktop, {ScrollController? scrollController}) {
    final total = _cart.values.fold<double>(
      0,
      (sum, item) => sum + (item['price'] * item['quantity']),
    );
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your Cart',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _cart.isEmpty
                  ? Center(
                      child: Text(
                        'Your cart is empty.',
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade400,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart.values.elementAt(index);
                        final itemNameStr = _getItemName(item, 'cart_content');
                        final itemId = item['id'] as String;
                        return ListTile(
                          key: ValueKey(itemId),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          title: Text(
                            itemNameStr,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${item['quantity']} x ₹${item['price'].toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, color: Colors.teal, size: 20),
                                onPressed: () => _removeFromCart(itemId),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${item['quantity']}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, color: Colors.teal, size: 20),
                                onPressed: () => _addToCart(item),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(color: Colors.grey),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total:',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      color: Colors.teal.shade400,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'Select Table',
                labelStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade700,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              value: _selectedTable,
              items: List.generate(
                10,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text(
                    'Table ${index + 1}',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedTable = value;
                });
                setModalState(() {});
              },
              dropdownColor: Colors.grey.shade800,
              style: GoogleFonts.poppins(color: Colors.white),
              validator: (value) => value == null ? 'Please select a table' : null,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _cart.isEmpty || _selectedTable == null
                      ? null
                      : () async {
                          await _placeOrder(modalContext, isDesktop);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Submit Order',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade900, Colors.blue.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: ResponsiveBuilder(
            builder: (context, sizingInformation) {
              final isDesktop = sizingInformation.deviceScreenType == DeviceScreenType.desktop;
              final padding = isDesktop ? 48.0 : 24.0;
              final fontSize = isDesktop ? 16.0 : 14.0;
              return Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: padding),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade300,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.restaurant,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Margam\'s Kitchen Menu',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: isDesktop ? 28 : 24,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton(
                                onPressed: _customerId == null
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => OrderHistoryPage(
                                              managerCode: widget.managerCode,
                                              customerId: _customerId!,
                                            ),
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade400,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  'Order History',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_customerPhone != null)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8.0),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Logged in with $_customerPhone',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: fontSize - 2,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 1200),
                              child: _customerName == null || _customerPhone == null || _customerId == null
                                  ? Container(
                                      padding: const EdgeInsets.all(16),
                                      margin: EdgeInsets.symmetric(horizontal: padding),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade800,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue.shade900.withOpacity(0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        'Please enter your details to continue.',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: fontSize,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : _isLoadingManager
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation(Colors.teal),
                                          ),
                                        )
                                      : _hasManagerError
                                          ? Container(
                                              padding: const EdgeInsets.all(16),
                                              margin: EdgeInsets.symmetric(horizontal: padding),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade800,
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.blue.shade900.withOpacity(0.2),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _errorMessage ?? 'An error occurred while loading the menu.',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.red.shade500,
                                                      fontSize: fontSize,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  ElevatedButton(
                                                    onPressed: _fetchManagerData,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.teal.shade400,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'Retry',
                                                      style: GoogleFonts.poppins(
                                                        color: Colors.white,
                                                        fontSize: fontSize - 2,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : _buildMenuList(fontSize, padding),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_cart.isNotEmpty)
                          FloatingActionButton(
                            onPressed: () => _showCart(context, isDesktop),
                            backgroundColor: Colors.teal.shade400,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.shopping_cart, color: Colors.white),
                                if (_cart.isNotEmpty)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${_cart.length}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_lastOrderId != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('orders')
                            .where('orderId', isEqualTo: _lastOrderId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final orders = snapshot.data!.docs;
                          bool allPrepared = orders.every((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return data['status'] == 'prepared';
                          });
                          bool allPaid = orders.every((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return data['paymentStatus'] == 'completed';
                          });
                          if (allPrepared && !allPaid) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final total = orders.fold<double>(
                                0,
                                (sum, doc) => sum + ((doc.data() as Map<String, dynamic>)['total'] as num).toDouble(),
                              );
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: Colors.grey.shade800,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: Text(
                                    'Order Prepared - Pay Now',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  content: Text(
                                    'Your order is ready! Please pay ₹${total.toStringAsFixed(2)} to complete.',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey.shade400,
                                      fontSize: 16,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        setState(() {
                                          _lastOrderId = null;
                                        });
                                      },
                                      child: Text(
                                        'Cancel',
                                        style: GoogleFonts.poppins(
                                          color: Colors.red.shade400,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: _isPaymentLoading
                                          ? null
                                          : () async {
                                              await _initiatePaymentForOrder(_lastOrderId!, total);
                                              if (!_isPaymentLoading) {
                                                Navigator.pop(dialogContext);
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal.shade400,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: _isPaymentLoading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              'Pay Now',
                                              style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            });
                          } else if (allPrepared && allPaid) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _showBill(_lastOrderId!, isDesktop);
                            });
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuList(double fontSize, double padding) {
    final onlineStalls = _stallsData!.entries
        .where((entry) => entry.value['isOpen'] == true)
        .map((entry) => entry.key)
        .toList();
    if (onlineStalls.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: EdgeInsets.symmetric(horizontal: padding),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade900.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          'No online stalls available.',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    debugPrint('Online stalls: $onlineStalls');
    return StreamBuilder<QuerySnapshot>(
      stream: onlineStalls.isEmpty
          ? null
          : FirebaseFirestore.instance
              .collection('menuItems')
              .where('managerCode', isEqualTo: widget.managerCode)
              .where('isAvailable', isEqualTo: true)
              .where('stallName', whereIn: onlineStalls)
              .snapshots(),
      builder: (context, menuSnapshot) {
        if (onlineStalls.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            margin: EdgeInsets.symmetric(horizontal: padding),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'No online stalls available.',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (menuSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.teal)));
        }
        if (menuSnapshot.hasError) {
          _showError('Error loading menu: ${menuSnapshot.error}');
          return Container(
            padding: const EdgeInsets.all(16),
            margin: EdgeInsets.symmetric(horizontal: padding),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Error loading menu: ${menuSnapshot.error}',
                  style: GoogleFonts.poppins(
                    color: Colors.red.shade500,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _fetchManagerData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade400,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: fontSize - 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final menuItems = menuSnapshot.data?.docs ?? [];
        debugPrint('Menu items found: ${menuItems.length}');
        if (menuItems.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            margin: EdgeInsets.symmetric(horizontal: padding),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'No menu items available.',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }
        Map<String, List<Map<String, dynamic>>> groupedItems = {};
        for (var doc in menuItems) {
          var item = doc.data() as Map<String, dynamic>;
          String stallName = item['stallName']?.toString() ?? '';
          String itemNameStr = _getItemName(item, 'menu_list');
          if (stallName.isEmpty || itemNameStr == 'Unknown Item') {
            debugPrint('Skipping invalid menu item: $item');
            continue;
          }
          if (!groupedItems.containsKey(stallName)) {
            groupedItems[stallName] = [];
          }
          groupedItems[stallName]!.add({
            'id': doc.id,
            'itemName': itemNameStr,
            'price': (item['price'] as num?)?.toDouble() ?? 0.0,
            'description': item['description']?.toString() ?? '',
            'stallName': stallName,
            'isAvailable': item['isAvailable'] as bool? ?? false,
            'managerCode': item['managerCode']?.toString() ?? '',
          });
        }
        if (groupedItems.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            margin: EdgeInsets.symmetric(horizontal: padding),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'No valid menu items available.',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }
        return Container(
          margin: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade900.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimationLimiter(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: groupedItems.keys.length,
              itemBuilder: (context, index) {
                String stallName = groupedItems.keys.elementAt(index);
                List<Map<String, dynamic>> items = groupedItems[stallName]!;
                return AnimationConfiguration.staggeredList(
                  position: index,
                  duration: const Duration(milliseconds: 400),
                  child: SlideAnimation(
                    verticalOffset: 50.0,
                    child: FadeInAnimation(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                            child: Text(
                              stallName,
                              style: GoogleFonts.poppins(
                                color: Colors.blue.shade300,
                                fontWeight: FontWeight.w700,
                                fontSize: fontSize + 4,
                              ),
                            ),
                          ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            itemBuilder: (context, itemIndex) {
                              var item = items[itemIndex];
                              final itemId = item['id'];
                              final quantity = _cart[itemId]?['quantity'] ?? 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade900.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade700,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.fastfood,
                                      color: Colors.teal,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    _getItemName(item, 'menu_list_item'),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: fontSize,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '₹${item['price'].toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.teal.shade400,
                                          fontWeight: FontWeight.w500,
                                          fontSize: fontSize - 2,
                                        ),
                                      ),
                                      if (item['description']?.toString().isNotEmpty ?? false)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Text(
                                            item['description'].toString(),
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey.shade400,
                                              fontSize: fontSize - 4,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove, color: Colors.teal, size: 20),
                                        onPressed: quantity > 0 ? () => _removeFromCart(itemId) : null,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(
                                          '$quantity',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: fontSize,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add, color: Colors.teal, size: 20),
                                        onPressed: () => _addToCart(item),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}