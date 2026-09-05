import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'progress.dart';

/// The one thing the game sells.
///
/// Must match the in-app product id created in Play Console exactly. Changing it
/// after release orphans every purchase already made.
const kFullGameId = 'hexcape.full';

/// Buying the full campaign.
///
/// Three rules, and the first outranks the other two:
///
/// 1. **The free game never depends on this.** Billing is unavailable on some
///    devices, fails on others, and is simply absent offline. Levels 1–20 and
///    everything around them must behave exactly as they did before this file
///    existed. The store is additive; nothing waits on it.
/// 2. **Google's purchase stream is the record**, and [Progress.ownsFullGame] is
///    a cache so a player who has paid can still play on a plane. The stream is
///    consulted on every launch, so the cache is never the thing that decides a
///    *new* entitlement.
/// 3. **Every purchase is completed.** An uncompleted one is redelivered
///    forever and is eventually auto-refunded by Google, which turns a sale into
///    a support problem.
class Store extends ChangeNotifier {
  Store(this._progress);

  final Progress _progress;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Null until the product has been fetched, which may be never — on a device
  /// without Play services it stays null and the paywall says so rather than
  /// showing a Buy button that cannot work.
  ProductDetails? product;

  bool _available = false;
  bool _busy = false;
  String? _error;

  /// Whether billing is usable at all on this device.
  bool get available => _available;

  /// A purchase or restore is in flight.
  bool get busy => _busy;

  /// The last thing that went wrong, for the paywall to show. Cleared on the
  /// next attempt.
  String? get error => _error;

  bool get owned => _progress.ownsFullGame;

  /// The localised price. Never hardcode this — Play returns it in the user's
  /// own currency and it differs by region.
  String get price => product?.price ?? '';

  Future<void> start() async {
    // Wrapped whole: a plugin that throws during setup must not take the game
    // down with it, because the game works perfectly well without a store.
    try {
      _available = await _iap.isAvailable();
      if (!_available) {
        notifyListeners();
        return;
      }
      _subscription = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => _fail('$e'),
      );
      final response = await _iap.queryProductDetails({kFullGameId});
      if (response.productDetails.isNotEmpty) {
        product = response.productDetails.first;
      }
      // Catches a reinstall, a new device, and a purchase made on another one.
      await _iap.restorePurchases();
    } catch (e) {
      _available = false;
      _error = '$e';
    }
    notifyListeners();
  }

  Future<void> buy() async {
    final details = product;
    if (details == null || _busy) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      // Deliberately not awaited to completion here: the result arrives on the
      // purchase stream, including when the player finishes paying minutes
      // later or on a different screen.
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> restore() async {
    if (_busy) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _fail('$e');
    }
    _busy = false;
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != kFullGameId) {
        // Still has to be completed, or it comes back on every launch.
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _busy = true;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _busy = false;
          _error = null;
          await _progress.setOwnsFullGame(true);
        case PurchaseStatus.error:
          _busy = false;
          _error = purchase.error?.message ?? 'The purchase did not go through.';
        case PurchaseStatus.canceled:
          // Not an error. Someone changing their mind should not be shown a
          // failure message for it.
          _busy = false;
          _error = null;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  void _fail(String message) {
    _busy = false;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
