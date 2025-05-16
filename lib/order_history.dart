// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'dart:js' as js;
import 'package:universal_html/html.dart' as html;
import 'dart:async';

class OrderHistoryPage extends StatefulWidget {
  final String managerCode;
  final String customerId;

  const OrderHistoryPage({super.key, required this.managerCode, required this.customerId});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  Stream<QuerySnapshot>? _ordersStream;
  DocumentSnapshot? _lastDocument;
  final int _pageSize = 10;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isPaymentLoading = false;
  List<DocumentSnapshot> _orders = [];
  final ScrollController _scrollController = ScrollController();
  static const String _razorpayKeyId = 'rzp_test_p9V24bWT3a35ky';

  @override
  void initState() {
    super.initState();
    _initializeStream();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore && _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeStream() {
    setState(() {
      _ordersStream = FirebaseFirestore.instance
          .collection('orders')
          .where('managerCode', isEqualTo: widget.managerCode)
          .where('customerId', isEqualTo: widget.customerId)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .snapshots();
      _lastDocument = null;
      _orders = [];
      _hasMore = true;
      _isLoadingMore = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _initializeStream();
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _lastDocument == null || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('managerCode', isEqualTo: widget.managerCode)
          .where('customerId', isEqualTo: widget.customerId)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        setState(() {
          _orders.addAll(querySnapshot.docs);
          _lastDocument = querySnapshot.docs.last;
          _hasMore = querySnapshot.docs.length == _pageSize;
        });
        debugPrint('Loaded ${querySnapshot.docs.length} more orders. Total: ${_orders.length}');
      } else {
        setState(() {
          _hasMore = false;
        });
        debugPrint('No more orders to load.');
      }
    } catch (e) {
      debugPrint('Error loading more orders: $e');
      _showError('Failed to load more orders: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  bool _isValidCustomerId(String id) {
    final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
    return uuidPattern.hasMatch(id);
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

  void _loadRazorpayScript() {
    if (html.document.getElementById('razorpay-checkout-js') == null) {
      final script = html.ScriptElement()
        ..id = 'razorpay-checkout-js'
        ..src = 'https://checkout.razorpay.com/v1/checkout.js'
        ..async = true;
      html.document.head?.append(script);
    }
  }

  Future<void> _initiatePaymentForOrder(String orderId, double amount, Map<String, dynamic> order) async {
    final customerPhone = order['customerPhone'] as String? ?? '';
    if (customerPhone.isEmpty) {
      _showError('Customer phone number missing. Please contact support.');
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
      _loadRazorpayScript();
      await Future.delayed(const Duration(seconds: 1));
      final completer = Completer<void>();
      js.context['flutterPaymentSuccess'] = (js.JsObject response) {
        final paymentId = response['razorpay_payment_id'] as String?;
        final razorpayOrderId = response['razorpay_order_id'] as String?;
        final signature = response['razorpay_signature'] as String?;
        _handlePaymentSuccess(paymentId, razorpayOrderId, signature, orderId);
        completer.complete();
      };
      js.context['flutterPaymentError'] = (js.JsObject error) {
        final message = error['description'] as String? ?? 'Unknown error';
        _handlePaymentError(message);
        completer.complete();
      };
      js.context['flutterPaymentCancelled'] = () {
        _handlePaymentError('Payment cancelled by user');
        completer.complete();
      };
      final options = js.JsObject.jsify({
        'key': _razorpayKeyId,
        'amount': (amount * 100).toInt(),
        'currency': 'INR',
        'name': "Margam's Kitchen",
        'description': 'Payment for order #$orderId',
        'handler': js.JsFunction.withThis((_, response) {
          js.context.callMethod('flutterPaymentSuccess', [response]);
        }),
        'prefill': {
          'contact': customerPhone,
          'email': 'customer@example.com',
        },
        'notes': {
          'orderId': orderId,
          'customerId': widget.customerId,
          'managerCode': widget.managerCode,
        },
        'theme': {
          'color': '#26A69A',
        },
        'modal': {
          'ondismiss': js.allowInterop(() {
            js.context.callMethod('flutterPaymentCancelled');
          }),
        },
        'method': {
          'netbanking': true,
          'card': true,
          'upi': true,
          'wallet': true,
        },
        '_': {
          'integration': 'flutter_web',
          'version': '1.0'
        }
      });
      final rzp = js.JsObject(js.context['Razorpay'], [options]);
      rzp.callMethod('on', [
        'payment.failed',
        js.allowInterop((error) {
          js.context.callMethod('flutterPaymentError', [error['error']]);
        }),
      ]);
      rzp.callMethod('open');
      await completer.future;
      setState(() {
        _isPaymentLoading = false;
      });
    } catch (e) {
      debugPrint('Payment initiation error: $e');
      _showError('Failed to initiate payment: $e');
      setState(() {
        _isPaymentLoading = false;
      });
    }
  }

  void _handlePaymentSuccess(String? paymentId, String? razorpayOrderId, String? signature, String orderId) {
    setState(() {
      _isPaymentLoading = false;
    });
    debugPrint('Payment success: PaymentID=$paymentId, OrderID=$orderId');
    _placeOrderAfterPayment(orderId, paymentId, razorpayOrderId, signature);
    _showSuccess('Payment successful! View your bill.');
  }

  void _handlePaymentError(String message) {
    setState(() {
      _isPaymentLoading = false;
    });
    _showError('Payment failed: $message');
    debugPrint('Payment error: $message');
  }

  Future<void> _placeOrderAfterPayment(String orderId, String? paymentId, String? razorpayOrderId, String? signature) async {
    try {
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('orderId', isEqualTo: orderId)
          .get();
      if (ordersSnapshot.docs.isEmpty) {
        _showError('Order not found.');
        debugPrint('Error: No orders found for orderId: $orderId');
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
        debugPrint(
            'Updated order ${doc.id} with payment details: PaymentID=$paymentId');
      }
      setState(() {
        _isPaymentLoading = false;
      });
      debugPrint('Payment completed for order: $orderId');
    } catch (e) {
      setState(() {
        _isPaymentLoading = false;
      });
      _showError('Failed to update order with payment: $e');
      debugPrint('Error updating order with payment: $e');
    }
  }

  void _showBillDialog(Map<String, dynamic> order, bool isDesktop) {
    final items = order['items'] as List<dynamic>? ?? [];
    final total = (order['total'] as num?)?.toDouble() ?? 0.0;
    final createdAt = (order['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final stallName = order['stallName'] as String? ?? 'Unknown';
    final orderId = order['orderId'] as String? ?? 'N/A';
    final customerName = order['customerName'] as String? ?? 'N/A';
    final customerPhone = order['customerPhone'] as String? ?? 'N/A';
    final table = order['table'] as int? ?? 0;

    showGeneralDialog(
      context: context,
      pageBuilder: (context, animation, secondaryAnimation) => Container(),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: isDesktop ? 600 : double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade900, Colors.blue.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade400.withOpacity(0.2),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long, color: Colors.white, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Margam\'s Kitchen Bill',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #$orderId',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Stall: $stallName',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Customer Info
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person, color: Colors.teal, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Name: $customerName',
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.phone, color: Colors.teal, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Phone: $customerPhone',
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                                if (table != 0) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.table_restaurant, color: Colors.teal, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Table: $table',
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, color: Colors.teal, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Date: ${createdAt.toString().substring(0, 16)}',
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Items Table
                          Table(
                            border: TableBorder.all(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(8)),
                            columnWidths: const {
                              0: FlexColumnWidth(3),
                              1: FlexColumnWidth(1),
                              2: FlexColumnWidth(1.5),
                              3: FlexColumnWidth(1.5),
                            },
                            children: [
                              TableRow(
                                decoration: BoxDecoration(color: Colors.teal.shade400.withOpacity(0.2)),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      'Item',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      'Qty',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      'Price',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      'Total',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                              ...items.map((item) {
                                final itemName = item['itemName'] as String? ?? 'Unknown Item';
                                final quantity = item['quantity'] as num? ?? 1;
                                final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                                final itemTotal = price * quantity;
                                return TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        itemName,
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '$quantity',
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '₹${price.toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '₹${itemTotal.toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(color: Colors.teal.shade400, fontSize: 14),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Total
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total:',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '₹${total.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  color: Colors.teal.shade400,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Thank You
                          Text(
                            'Thank you for dining with us!',
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // Close Button
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade400,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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

              return Column(
                children: [
                  _buildHeader(isDesktop, padding),
                  Expanded(child: _buildOrderList(isDesktop, padding, fontSize)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop, double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'Order History',
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
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message, double padding, double fontSize) {
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
            message,
            style: GoogleFonts.poppins(
              color: Colors.red.shade500,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _refresh,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildOrderList(bool isDesktop, double padding, double fontSize) {
    debugPrint('Querying orders for customerId: ${widget.customerId}, managerCode: ${widget.managerCode}');

    if (!_isValidCustomerId(widget.customerId)) {
      return _buildErrorCard(
        'Invalid customer ID format. Please ensure it is a valid ID.',
        padding,
        fontSize,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _orders.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.teal),
            ),
          );
        }
        if (snapshot.hasError) {
          debugPrint('Error fetching orders: ${snapshot.error}');
          String errorMessage = 'Error loading order history.';
          if (snapshot.error.toString().contains('permission-denied')) {
            errorMessage = 'You do not have permission to view order history.';
          } else if (snapshot.error.toString().contains('network')) {
            errorMessage = 'Network error. Please check your connection and try again.';
          }
          return _buildErrorCard(errorMessage, padding, fontSize);
        }

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          if (_orders.isEmpty || _lastDocument == null) {
            _orders = snapshot.data!.docs;
            _lastDocument = _orders.last;
            _hasMore = snapshot.data!.docs.length == _pageSize;
            debugPrint('Initial load: ${snapshot.data!.docs.length} orders');
          }
        }

        if (_orders.isEmpty) {
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
              'No orders found for this customer.',
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
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: Colors.teal,
            child: AnimationLimiter(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _orders.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _orders.length && _hasMore) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Colors.teal),
                        ),
                      ),
                    );
                  }

                  final order = _orders[index].data() as Map<String, dynamic>;
                  final items = order['items'] as List<dynamic>? ?? [];
                  final total = (order['total'] as num?)?.toDouble() ?? 0.0;
                  final status = order['status'] as String? ?? 'unknown';
                  final paymentStatus = order['paymentStatus'] as String? ?? 'pending';
                  final createdAt = (order['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final stallName = order['stallName'] as String? ?? 'Unknown';
                  final orderId = order['orderId'] as String? ?? 'N/A';

                  Color statusColor;
                  switch (status.toLowerCase()) {
                    case 'pending':
                      statusColor = Colors.yellow.shade600;
                      break;
                    case 'preparing':
                      statusColor = Colors.orange.shade600;
                      break;
                    case 'prepared':
                      statusColor = Colors.green.shade600;
                      break;
                    case 'delivered':
                      statusColor = Colors.blue.shade600;
                      break;
                    default:
                      statusColor = Colors.grey;
                  }

                  Color paymentStatusColor = paymentStatus.toLowerCase() == 'completed' ? Colors.green.shade600 : Colors.red.shade600;

                  return AnimationConfiguration.staggeredList(
                    position: index,
                    duration: const Duration(milliseconds: 400),
                    child: SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(isDesktop ? 20 : 16),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Order #${orderId.length > 8 ? orderId.substring(0, 8) : orderId} ($stallName)',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status,
                                          style: GoogleFonts.poppins(
                                            color: statusColor,
                                            fontSize: fontSize - 2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: paymentStatusColor.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          paymentStatus == 'completed' ? 'Paid' : 'Pending',
                                          style: GoogleFonts.poppins(
                                            color: paymentStatusColor,
                                            fontSize: fontSize - 2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Placed on: ${createdAt.toString().substring(0, 16)}',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey.shade400,
                                  fontSize: fontSize - 2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...items.map((item) {
                                final itemName = item['itemName'] as String? ?? 'Unknown Item';
                                final quantity = item['quantity'] as num? ?? 1;
                                final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                                final itemTotal = price * quantity;
                                return ListTile(
                                  contentPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 0, vertical: 2),
                                  title: Text(
                                    itemName,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: fontSize - 2,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$quantity x ₹${price.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey.shade400,
                                      fontSize: fontSize - 4,
                                    ),
                                  ),
                                  trailing: Text(
                                    '₹${itemTotal.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.teal.shade400,
                                      fontSize: fontSize - 2,
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
                                    'Total:',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '₹${total.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.teal.shade400,
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (status.toLowerCase() == 'prepared' && paymentStatus.toLowerCase() == 'pending') ...[
                                const SizedBox(height: 12),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: _isPaymentLoading
                                        ? null
                                        : () => _initiatePaymentForOrder(orderId, total, order),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal.shade400,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                              fontSize: fontSize - 2,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ] else if (paymentStatus.toLowerCase() == 'completed') ...[
                                const SizedBox(height: 12),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: () => _showBillDialog(order, isDesktop),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal.shade400,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                    child: Text(
                                      'View Bill',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: fontSize - 2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}