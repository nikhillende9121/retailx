import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/catalog.dart';
import '../data/repositories/sales_repository.dart';

/// One line in a running cart. Price is per-line and entered by the cashier:
/// the sale endpoint has no product price column and price-list resolution
/// isn't exposed to it, so the till captures the price the same way the web
/// checkout does.
class CartLine {
  const CartLine({
    required this.product,
    required this.quantity,
    required this.price,
    this.discount = 0,
  });

  final Product product;
  final double quantity;
  final double price;

  /// Money off this line, in rupees.
  final double discount;

  double get gross => quantity * price;

  /// Never below zero — a discount bigger than the line can't pay the customer.
  double get total {
    final net = gross - discount;
    return net < 0 ? 0 : net;
  }

  bool get isPriced => price > 0;

  bool get isDiscounted => discount > 0;

  CartLine copyWith({double? quantity, double? price, double? discount}) =>
      CartLine(
        product: product,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        discount: discount ?? this.discount,
      );

  LineInput toInput() => LineInput(
        productId: product.id,
        quantity: quantity,
        price: price,
        discount: discount,
      );
}

class CartController extends StateNotifier<List<CartLine>> {
  CartController() : super(const []);

  int _indexOf(String productId) =>
      state.indexWhere((line) => line.product.id == productId);

  /// Tapping a tile that's already in the cart bumps its quantity rather than
  /// adding a duplicate line.
  void add(Product product, {double quantity = 1}) {
    final index = _indexOf(product.id);
    if (index >= 0) {
      final existing = state[index];
      setQuantity(product.id, existing.quantity + quantity);
      return;
    }
    state = [
      ...state,
      CartLine(
        product: product,
        quantity: quantity,
        price: product.defaultPrice ?? 0,
      ),
    ];
  }

  void setQuantity(String productId, double quantity) {
    if (quantity <= 0) {
      remove(productId);
      return;
    }
    state = [
      for (final line in state)
        if (line.product.id == productId) line.copyWith(quantity: quantity) else line,
    ];
  }

  /// One fewer, dropping the line when it reaches zero.
  ///
  /// The counterpart to [add] for the −/+ stepper on a product tile: a no-op when
  /// the product isn't in the cart, so the button never has to be disabled to be
  /// safe.
  void decrement(String productId, {double quantity = 1}) {
    final index = _indexOf(productId);
    if (index < 0) return;
    setQuantity(productId, state[index].quantity - quantity);
  }

  void setPrice(String productId, double price) {
    state = [
      for (final line in state)
        if (line.product.id == productId)
          line.copyWith(price: price < 0 ? 0 : price)
        else
          line,
    ];
  }

  void setDiscount(String productId, double discount) {
    state = [
      for (final line in state)
        if (line.product.id == productId)
          line.copyWith(discount: discount < 0 ? 0 : discount)
        else
          line,
    ];
  }

  void remove(String productId) {
    state = state.where((line) => line.product.id != productId).toList();
  }

  void clear() => state = const [];

  double quantityOf(String productId) {
    final index = _indexOf(productId);
    return index < 0 ? 0 : state[index].quantity;
  }
}

/// Keyed so the checkout cart and an exchange's replacement cart coexist.
/// `keepAlive` isn't needed: the screens holding these stay mounted inside the
/// shell's IndexedStack, so a half-built cart survives a tab switch.
final cartProvider =
    StateNotifierProvider.family<CartController, List<CartLine>, String>(
  (ref, key) => CartController(),
);

const String kCheckoutCart = 'checkout';
const String kExchangeCart = 'exchange';

/// Line totals after any per-line discount.
double cartSubtotal(List<CartLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.total);

/// Before per-line discounts — the "was" figure.
double cartGross(List<CartLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.gross);

double cartLineDiscounts(List<CartLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.discount);

double cartUnits(List<CartLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.quantity);
