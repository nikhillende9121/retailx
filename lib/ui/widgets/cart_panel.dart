import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/models/catalog.dart';
import '../../state/cart.dart';
import '../theme.dart';
import 'common.dart';

/// Product image, or initials on a tonal panel when there isn't one.
///
/// `images` comes back empty for most products today, so the initials path is
/// the common case — but it occupies exactly the space a photo would, which is
/// what keeps the grid from looking broken either way. A URL that 404s falls
/// back to initials rather than showing a broken-image glyph.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.name,
    this.imageUrl,
    this.size,
    this.radius = kRadiusCard,
  });

  final String name;
  final String? imageUrl;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;

    final placeholder = Center(
      child: Text(
        initials(name),
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: (size ?? 48) < 56 ? 14 : 20,
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: url == null
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (context, _, __) => placeholder,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
            ),
    );
  }
}

/// Product tile for the till grid: photo on top, name, then price on the left
/// with a −/+ stepper on the right. Tapping the card adds one.
///
/// The stepper is on the tile itself, not only in the cart sheet: "two of those"
/// is the most common thing a customer says, and making the cashier open a sheet
/// to say it twice is the difference between keeping up with the queue and not.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    this.onTap,
    this.stock,
    this.inCart = 0,
    this.onAdd,
    this.onRemove,
  });

  final Product product;

  /// Null disables the tile — used for a product with nothing on the shelf.
  final VoidCallback? onTap;
  final double? stock;
  final double inCart;

  /// Stepper handlers. When both are null the tile has no stepper — the picker
  /// sheets reuse this widget purely to display a product.
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final outOfStock = stock != null && stock! <= 0;
    final lowStock = stock != null && stock! > 0 && stock! <= 5;
    final selected = inCart > 0;
    final hasStepper = onAdd != null || onRemove != null;

    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusTile),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : outOfStock
                  ? scheme.error.withAlpha(90)
                  : scheme.outlineVariant,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ProductThumb(
                        name: product.name,
                        imageUrl: product.imageUrl,
                        radius: kRadiusCard,
                      ),
                    ),
                    // A round tick, not a "2 in cart" pill: the count already
                    // shows in the stepper below, so the badge only has to answer
                    // "is this one of mine?" from across the counter.
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(40),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            '${qty(inCart)} in cart',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    if (stock != null)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest.withAlpha(235),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            outOfStock
                                ? 'Out of stock'
                                : '${qty(stock)} left',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: outOfStock
                                  ? scheme.error
                                  : lowStock
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      product.defaultPrice == null
                          ? '—'
                          : money(product.defaultPrice),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  if (hasStepper)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer.withAlpha(160)
                            : scheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected) ...[
                            _TileStep(
                              icon: Icons.remove_rounded,
                              onTap: onRemove,
                              filled: false,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                qty(inCart),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                          _TileStep(
                            icon: Icons.add_rounded,
                            onTap: outOfStock ? null : onAdd,
                            filled: true,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One −/+ button on a product tile.
///
/// 26dp rather than the app's usual 48dp minimum: it sits inside a grid cell
/// that's ~160dp wide next to a price, and the whole card is also a "+1" target,
/// so a miss costs nothing.
class _TileStep extends StatelessWidget {
  const _TileStep({required this.icon, required this.onTap, required this.filled});

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final background = filled
        ? (enabled ? scheme.primary : scheme.surfaceContainerHigh)
        : Colors.transparent;
    final foreground = filled
        ? (enabled ? scheme.onPrimary : scheme.outline)
        // Not outlineVariant when disabled: that's a divider tint, 1.3:1 on a
        // white tile, so the "−" simply wasn't there.
        : (enabled ? scheme.onSurfaceVariant : scheme.outline);

    return Semantics(
      button: true,
      label: filled ? 'Add one' : 'Remove one',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: filled
                ? null
                : Border.all(
                    color: enabled ? scheme.outlineVariant : Colors.transparent,
                  ),
          ),
          child: Icon(icon, size: 16, color: foreground),
        ),
      ),
    );
  }
}

/// Responsive tile grid — more columns on a tablet at the counter.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(kScreenMargin),
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    // The grid's own available width, not the device's — once a side rail
    // or cart panel sits next to it, those two stop being the same number,
    // and sizing off the device width left cards too big for what was
    // actually left over on a tablet.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 6
            : width >= 900
                ? 5
                : width >= 700
                    ? 4
                    : width >= 460
                        ? 3
                        : 2;

        return GridView.count(
          controller: controller,
          padding: padding,
          crossAxisCount: columns,
          mainAxisSpacing: kCardGap,
          crossAxisSpacing: kCardGap,
          childAspectRatio: 0.88,
          children: children,
        );
      },
    );
  }
}

/// One editable line: thumbnail, name and SKU, signed amount, quantity pill.
class CartLineTile extends StatefulWidget {
  const CartLineTile({
    super.key,
    required this.line,
    required this.onQuantityChanged,
    required this.onRemove,
    this.onPriceChanged,
    this.onDiscountChanged,
    this.maxQuantity,
    this.signed = false,
  });

  final CartLine line;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback onRemove;

  /// Null where the server resolves the price itself and ignores whatever a
  /// client sends (a sale exchange's replacement items — see
  /// `sale-exchange.schema.ts`'s `newItems`: `productId`/`quantity` only,
  /// same as a normal Sale). Editing it there would let a cashier type a
  /// number the server silently discards, so the field renders read-only
  /// instead — the assigned price is still shown, just not editable.
  final ValueChanged<double>? onPriceChanged;

  /// Omitted where a per-line discount makes no sense (exchange replacements,
  /// purchase order lines).
  final ValueChanged<double>? onDiscountChanged;
  final double? maxQuantity;

  /// Shows the amount with a leading '+' — used where a line adds to what the
  /// customer owes, against return lines that subtract.
  final bool signed;

  @override
  State<CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<CartLineTile> {
  late final TextEditingController _price = TextEditingController(
    text: widget.line.price > 0 ? widget.line.price.toStringAsFixed(2) : '',
  );
  late final TextEditingController _discount = TextEditingController(
    text: widget.line.discount > 0
        ? widget.line.discount.toStringAsFixed(2)
        : '',
  );
  final FocusNode _focus = FocusNode();
  final FocusNode _discountFocus = FocusNode();

  @override
  void didUpdateWidget(CartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only push external changes into the field while the cashier isn't typing.
    if (!_focus.hasFocus && widget.line.price != oldWidget.line.price) {
      _price.text =
          widget.line.price > 0 ? widget.line.price.toStringAsFixed(2) : '';
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _discount.dispose();
    _focus.dispose();
    _discountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = widget.line;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumb(
                name: line.product.name,
                imageUrl: line.product.imageUrl,
                size: 52,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (line.product.sku != null)
                      Text(
                        'SKU: ${line.product.sku}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 4),
                    // Wrap: the column is already narrowed by the thumbnail,
                    // stepper and Remove button, so a discounted line's two
                    // money strings won't always fit on one line. Money is never
                    // ellipsised — it wraps.
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (line.isDiscounted)
                          Text(
                            money(line.gross),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                ),
                          ),
                        Text(
                          '${widget.signed ? '+' : ''}${money(line.total)}',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: line.isDiscounted
                                        ? successColor(scheme.brightness)
                                        : null,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  QuantityStepper(
                    value: line.quantity,
                    min: 0,
                    max: widget.maxQuantity,
                    onChanged: widget.onQuantityChanged,
                  ),
                  TextButton.icon(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Omitted entirely — not even read-only — when neither is
          // editable in this context (a sale exchange's replacement items:
          // the server resolves the price itself and there's no per-line
          // discount concept, so there's nothing here worth a field for,
          // disabled-looking or otherwise). The line's total is already
          // shown above regardless.
          if (widget.onPriceChanged != null ||
              widget.onDiscountChanged != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: widget.onPriceChanged != null
                      ? TextField(
                          controller: _price,
                          focusNode: _focus,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (value) => widget.onPriceChanged!(
                              double.tryParse(value.trim()) ?? 0),
                          decoration: InputDecoration(
                            prefixText: '₹ ',
                            labelText: 'Price each',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            errorText: line.isPriced ? null : 'Required',
                            errorStyle:
                                TextStyle(color: scheme.error, fontSize: 11),
                          ),
                        )
                      // Read-only: same field chrome as the editable version
                      // so the layout doesn't jump between contexts, but
                      // nothing to tap — the assigned price, shown only
                      // because a discount field is being shown next to it.
                      : InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Price each',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          child: Text(money(line.price)),
                        ),
                ),
                if (widget.onDiscountChanged != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _discount,
                      focusNode: _discountFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (value) => widget.onDiscountChanged!(
                          double.tryParse(value.trim()) ?? 0),
                      decoration: const InputDecoration(
                        prefixText: '− ₹ ',
                        labelText: 'Line discount',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The docked bar at the bottom of the till: how many items, what it comes to,
/// and the one button that finishes the sale.
///
/// Shaped like a card that has slid up over the grid — rounded top corners, a
/// shadow, and a chevron that opens the full cart. The amount lives on the left
/// and the button says only what it does, because a label like
/// "Charge ₹1,24,500.00" is the string that overflows on a small phone.
class CartSummaryBar extends StatelessWidget {
  const CartSummaryBar({
    super.key,
    required this.lines,
    required this.actionLabel,
    required this.onAction,
    required this.onEdit,
    required this.total,
    this.busy = false,
    this.blocker,
    this.breakdown,
  });

  final List<CartLine> lines;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onEdit;

  /// What the customer actually pays — shown large on the left.
  final double total;
  final bool busy;

  /// Totals shown above the action — the "was", the discount, the net.
  final Widget? breakdown;

  /// Why the action is unavailable, shown in place of the item count.
  final String? blocker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final units = cartUnits(lines);
    final ready = lines.isNotEmpty && blocker == null && !busy;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kRadiusSheet),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF231A14).withAlpha(28),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // The chevron is the cart handle — the mockup's affordance for
                  // "there's a list under here".
                  IconButton(
                    tooltip: 'Open the cart',
                    onPressed: lines.isEmpty ? null : onEdit,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerLow,
                      minimumSize: const Size(36, 36),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lines.isEmpty
                              ? 'Cart is empty'
                              : '${qty(units)} item${units == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          money(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: priceDisplayStyle(context).copyWith(
                            fontSize: 22,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    // Room for "Charge" or "Settle" and a spinner, no more: the
                    // amount is already on the left, so this never has to grow.
                    constraints: const BoxConstraints(minWidth: 116, maxWidth: 170),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: const StadiumBorder(),
                        // While busy the button is disabled but still the most
                        // important thing on screen, so it keeps its own colours
                        // and just swaps the label for a spinner.
                        disabledBackgroundColor: busy
                            ? scheme.primary
                            : scheme.surfaceContainerHigh,
                        disabledForegroundColor:
                            busy ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                      onPressed: ready ? onAction : null,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              if (breakdown != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: breakdown!),
              ],
              if (blocker != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        blocker!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full cart, opened from Edit. Kept off the till screen so the grid stays the
/// whole surface until the cashier actually needs to change a line.
Future<void> showCartSheet({
  required BuildContext context,
  required List<CartLine> lines,
  required void Function(CartLine line, double quantity) onQuantityChanged,
  required void Function(CartLine line) onRemove,
  // Null on the POS till: `POST /sales` resolves price server-side and has
  // no per-line discount concept at all (see `CartLineTile.onPriceChanged`'s
  // doc comment), so there's nothing here for a cashier to edit — same
  // reasoning that already dropped both fields from the sale-exchange
  // replacement-items cart.
  void Function(CartLine line, double price)? onPriceChanged,
  void Function(CartLine line, double discount)? onDiscountChanged,
  String title = 'Cart',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _CartSheet(
      title: title,
      initialLines: lines,
      onQuantityChanged: onQuantityChanged,
      onPriceChanged: onPriceChanged,
      onRemove: onRemove,
      onDiscountChanged: onDiscountChanged,
    ),
  );
}

class _CartSheet extends StatefulWidget {
  const _CartSheet({
    required this.title,
    required this.initialLines,
    required this.onQuantityChanged,
    required this.onRemove,
    this.onPriceChanged,
    this.onDiscountChanged,
  });

  final String title;
  final List<CartLine> initialLines;
  final void Function(CartLine line, double quantity) onQuantityChanged;
  final void Function(CartLine line) onRemove;
  final void Function(CartLine line, double price)? onPriceChanged;
  final void Function(CartLine line, double discount)? onDiscountChanged;

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  late List<CartLine> _lines = List.of(widget.initialLines);

  /// Mutations address a line by product id, never by list index.
  ///
  /// An index captured in an `itemBuilder` closure goes stale the moment any
  /// other line is removed — two events in one frame (a fast double-tap on
  /// Remove, or Remove plus a stepper hitting zero) applied the second one to an
  /// already-shortened list, deleting the wrong line or throwing RangeError.
  int _indexOf(CartLine line) =>
      _lines.indexWhere((existing) => existing.product.id == line.product.id);

  void _removeLine(CartLine line) {
    final index = _indexOf(line);
    if (index >= 0) _lines.removeAt(index);
  }

  void _replaceLine(CartLine line, CartLine updated) {
    final index = _indexOf(line);
    if (index >= 0) _lines[index] = updated;
  }

  void _apply(void Function() mutate) {
    mutate();
    // The sheet keeps its own copy so it can redraw immediately; the parent
    // provider is the source of truth and is updated through the callbacks.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kScreenMargin, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    money(cartSubtotal(_lines)),
                    style: priceDisplayStyle(context),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: kScreenMargin, vertical: 8),
                itemCount: _lines.length,
                separatorBuilder: (context, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return CartLineTile(
                    key: ValueKey(line.product.id),
                    line: line,
                    onQuantityChanged: (value) => _apply(() {
                      widget.onQuantityChanged(line, value);
                      if (value <= 0) {
                        _removeLine(line);
                      } else {
                        _replaceLine(line, line.copyWith(quantity: value));
                      }
                    }),
                    onPriceChanged: widget.onPriceChanged == null
                        ? null
                        : (value) => _apply(() {
                              widget.onPriceChanged!(line, value);
                              _replaceLine(line, line.copyWith(price: value));
                            }),
                    onDiscountChanged: widget.onDiscountChanged == null
                        ? null
                        : (value) => _apply(() {
                              widget.onDiscountChanged!(line, value);
                              _replaceLine(line, line.copyWith(discount: value));
                            }),
                    onRemove: () => _apply(() {
                      widget.onRemove(line);
                      _removeLine(line);
                    }),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(kScreenMargin),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Close this sheet to charge the sale.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
