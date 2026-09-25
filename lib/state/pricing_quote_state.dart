import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/pricing_quote.dart';
import '../data/repositories/pricing_repository.dart';
import '../data/repositories/sales_repository.dart' show ChargeInput;
import 'cart.dart';
import 'providers.dart';

/// Immutable snapshot of everything the quote endpoint needs. Building a new
/// instance on every input change and comparing with `==` is how we debounce:
/// if the request we're about to fire matches the one already in flight (or
/// already answered), skip it.
class QuoteInput {
  const QuoteInput({
    required this.warehouseId,
    required this.lines,
    this.customerId,
    this.couponCode,
    this.discountAmount = 0,
    this.discountPercent,
    this.charges,
  });

  final String warehouseId;
  final List<CartLine> lines;
  final String? customerId;
  final String? couponCode;
  final double discountAmount;
  final double? discountPercent;
  final List<ChargeInput>? charges;
}

/// Debounced pricing quote controller.
///
/// Call [request] whenever the checkout state changes (cart, customer, coupon,
/// discount, charges). It debounces for [_debounceDuration], then fires
/// `POST /pricing/quote` and publishes the result as an `AsyncValue`. Stale
/// responses (from an earlier sequence) are silently discarded.
class QuoteController extends StateNotifier<AsyncValue<PricingQuote?>> {
  QuoteController(this._pricing) : super(const AsyncData(null));

  final PricingRepository _pricing;

  static const _debounceDuration = Duration(milliseconds: 500);

  Timer? _debounce;
  int _seq = 0;

  /// The coupon code the currently-published [state] was actually computed
  /// for — *not* necessarily the coupon code showing in the UI right now.
  ///
  /// `request()` only debounces the *next* call; it can't cancel a request
  /// that's already left for the server. So a slow response fired before a
  /// coupon was typed in can still land after the coupon-bearing request has
  /// been scheduled but hasn't started yet (still waiting out its own
  /// debounce) — `seq` doesn't catch this, since it only advances when a
  /// request *starts*, not when one is merely queued. That stale response
  /// legitimately carries `coupon: null` (it was never sent one), and would
  /// otherwise be misread as "the server rejected the coupon". Comparing
  /// this against the screen's `_couponCode` before drawing that conclusion
  /// is what tells a real rejection apart from a stale, coupon-less answer.
  String? lastCouponCode;

  /// Trigger a (debounced) quote. Safe to call on every keystroke or cart
  /// mutation — only the last call within the debounce window actually fires.
  void request(QuoteInput input) {
    _debounce?.cancel();

    // Nothing to quote — clear immediately, no API call.
    if (input.lines.isEmpty) {
      _seq++;
      lastCouponCode = input.couponCode;
      state = const AsyncData(null);
      return;
    }

    _debounce = Timer(_debounceDuration, () => _fire(input));
  }

  /// Clear any in-flight request and reset to null.
  void clear() {
    _debounce?.cancel();
    _seq++;
    lastCouponCode = null;
    state = const AsyncData(null);
  }

  Future<void> _fire(QuoteInput input) async {
    final seq = ++_seq;

    // Show loading while keeping the previous value visible (prevents flicker).
    state = const AsyncLoading();

    try {
      final quote = await _pricing.quote(
        warehouseId: input.warehouseId,
        lines: input.lines.map((l) => l.toInput()).toList(),
        customerId: input.customerId,
        couponCode: input.couponCode,
        discountAmount: input.discountAmount,
        discountPercent: input.discountPercent,
        charges: input.charges,
      );
      if (!mounted || seq != _seq) return; // stale
      // Set together with `state`, never separately — a build that reacts
      // to the new state must see the coupon code it was computed for.
      lastCouponCode = input.couponCode;
      state = AsyncData(quote);
    } catch (error, stack) {
      if (!mounted || seq != _seq) return; // stale
      lastCouponCode = input.couponCode;
      state = AsyncError(error, stack);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Keyed so the checkout cart and an exchange's replacement cart each get their
/// own independent quote stream.
final quoteProvider = StateNotifierProvider.family<QuoteController,
    AsyncValue<PricingQuote?>, String>(
  (ref, key) => QuoteController(ref.watch(pricingRepositoryProvider)),
);
