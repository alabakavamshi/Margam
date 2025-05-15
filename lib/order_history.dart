import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_builder/responsive_builder.dart';


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
  List<DocumentSnapshot> _orders = [];

  @override
  void initState() {
    super.initState();
    _initializeStream();
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
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _initializeStream();
    });
  }

  void _loadMore() {
    if (!_hasMore || _lastDocument == null) return;

    setState(() {
      _ordersStream = FirebaseFirestore.instance
          .collection('orders')
          .where('managerCode', isEqualTo: widget.managerCode)
          .where('customerId', isEqualTo: widget.customerId)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize)
          .snapshots();
    });
  }

  bool _isValidCustomerId(String id) {
    final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
    return uuidPattern.hasMatch(id);
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
        if (snapshot.connectionState == ConnectionState.waiting) {
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

        final newOrders = snapshot.data?.docs ?? [];
        debugPrint('Found ${newOrders.length} orders for customerId: ${widget.customerId}');
        if (newOrders.isNotEmpty) {
          _orders.addAll(newOrders);
          _lastDocument = newOrders.last;
          _hasMore = newOrders.length == _pageSize;
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
              'No orders found for this phone number.',
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _orders.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _orders.length && _hasMore) {
                    _loadMore();
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
                  final createdAt = (order['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final stallName = order['stallName'] as String? ?? 'Unknown';

                  Color statusColor;
                  switch (status) {
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
                                      'Order #${(order['orderId'] as String?)?.substring(0, 8) ?? 'N/A'} ($stallName)',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
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
                              ...items.map((item) => ListTile(
                                    contentPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 0, vertical: 2),
                                    title: Text(
                                      item['itemName'] as String? ?? 'Unknown Item',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: fontSize - 2,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item['quantity'] ?? 1} x \$${((item['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey.shade400,
                                        fontSize: fontSize - 4,
                                      ),
                                    ),
                                    trailing: Text(
                                      '\$${(((item['price'] as num?)?.toDouble() ?? 0.0) * (item['quantity'] as num? ?? 1)).toStringAsFixed(2)}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.teal.shade400,
                                        fontSize: fontSize - 2,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  )),
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
                                    '\$${total.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.teal.shade400,
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
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