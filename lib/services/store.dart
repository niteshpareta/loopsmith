import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../game/economy.dart';

/// Why a purchase did not go through. The screens put this into words.
enum StoreError { unreachable, failed, notStarted, notRestored }

/// In-app purchases behind one interface.
abstract class StoreService extends ChangeNotifier {
  /// Called once for every purchase that should be granted, including
  /// restored ones.
  void Function(String productId)? onGranted;

  /// Whether purchases can be made on this device.
  bool get available;

  /// A purchase is in progress.
  bool get busy;

  /// Why the last purchase did not go through, if it did not.
  StoreError? get lastError;

  /// Localised price from the store, or null if the product is not loaded.
  String? price(String productId);

  Future<void> init();
  Future<void> buy(String productId);
  Future<void> restore();
}

/// No store: used on the web, on desktop, and in tests.
class NoStore extends StoreService {
  @override
  bool get available => false;
  @override
  bool get busy => false;
  @override
  StoreError? get lastError => null;
  @override
  String? price(String productId) => null;
  @override
  Future<void> init() async {}
  @override
  Future<void> buy(String productId) async {}
  @override
  Future<void> restore() async {}
}

/// App Store and Google Play billing through package:in_app_purchase.
///
/// Purchases are trusted on the device. Add server-side receipt validation
/// before relying on this for anything valuable.
class IapStore extends StoreService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<String, ProductDetails> _products = {};
  bool _available = false;
  bool _busy = false;
  StoreError? _error;

  static const _ids = {Economy.removeAdsId, Economy.starterKitId};

  @override
  bool get available => _available && _products.isNotEmpty;
  @override
  bool get busy => _busy;
  @override
  StoreError? get lastError => _error;
  @override
  String? price(String productId) => _products[productId]?.price;

  @override
  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) {
          _busy = false;
          _error = StoreError.unreachable;
          notifyListeners();
        },
      );
      final response = await _iap.queryProductDetails(_ids);
      for (final p in response.productDetails) {
        _products[p.id] = p;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Store unavailable: $e');
      _available = false;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _busy = true;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _busy = false;
          _error = null;
          onGranted?.call(p.productID);
        case PurchaseStatus.error:
          _busy = false;
          _error = StoreError.failed;
        case PurchaseStatus.canceled:
          _busy = false;
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    notifyListeners();
  }

  @override
  Future<void> buy(String productId) async {
    final product = _products[productId];
    if (product == null || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      _busy = false;
      _error = StoreError.notStarted;
      notifyListeners();
    }
  }

  @override
  Future<void> restore() async {
    if (!_available) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _error = StoreError.notRestored;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

StoreService createStore() {
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return mobile ? IapStore() : NoStore();
}
