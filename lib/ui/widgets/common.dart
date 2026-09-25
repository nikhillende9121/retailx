import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../core/errors.dart';
import '../../core/formatters.dart';
import '../theme.dart';

export '../theme.dart' show kTouchTarget, kRadiusCard, kRadiusButton, kCardGap;

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Failure state with the code-appropriate copy and a retry only where
/// retrying could actually help.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.compact = false});

  final AppError error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (error.code) {
      ErrorCodes.network => Icons.wifi_off_rounded,
      ErrorCodes.permissionDenied => Icons.lock_outline_rounded,
      ErrorCodes.featureNotEnabled => Icons.workspace_premium_outlined,
      ErrorCodes.notFound => Icons.search_off_rounded,
      _ => Icons.error_outline_rounded,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 32 : 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              error.uiMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (error.isValidation && error.fieldErrors.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final entry in error.fieldErrors.entries)
                Text(
                  '${entry.key}: ${entry.value}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.error),
                ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.dense = false,
    this.label,
  });

  final String? status;
  final bool dense;

  /// Overrides the text without touching the colour or icon.
  ///
  /// Used where the storage word isn't the word the store uses — a DRAFT
  /// purchase is an "Indent" on the shop floor, but it's still the same state.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = statusColor(scheme, status);
    // Full pill shape is reserved for status — it's what distinguishes a state
    // indicator from something tappable.
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(30), scheme.surfaceContainerLowest),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: dense ? 10 : 14, color: color),
          SizedBox(width: dense ? 3 : 4),
          Text(
            label ?? humanizeCode(status),
            style: TextStyle(
              color: color,
              fontSize: dense ? 10 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label/value row used across every detail screen.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: emphasize
                  ? theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: valueColor)
                  : theme.textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined surface used instead of [Card] so the look is pinned here rather
/// than depending on which Flutter version's card theming is in play.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.statusEdge,
    this.dimmed = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// 4px colour bar down the leading edge, used on document lists so status is
  /// readable from the very edge of the row without reading the pill.
  final Color? statusEdge;

  /// Terminal states (cancelled, fully received) recede rather than compete.
  final bool dimmed;

  /// Overridden for exception states — e.g. a red hairline on low stock.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Level 1 tonal surface: white card, 1px border, no shadow.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusCard),
      side: BorderSide(color: borderColor ?? scheme.outlineVariant),
    );
    final edge = statusEdge;

    // The status edge is drawn as a positioned bar inside a Stack rather than a
    // stretched Row. CrossAxisAlignment.stretch needs a bounded cross-axis
    // extent, which a card inside a ListView does not have — that combination
    // asserts during layout. A Positioned with top+bottom set stretches without
    // demanding bounds, and Border with a thick left side can't be combined
    // with a borderRadius at all.
    Widget content = Padding(
      padding: edge == null
          ? padding
          : padding.add(const EdgeInsets.only(left: 6)),
      child: child,
    );

    if (edge != null) {
      content = Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: edge),
          ),
          content,
        ],
      );
    }

    return Opacity(
      opacity: dimmed ? 0.62 : 1,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// +/- stepper. Deliberately large: this is the control a cashier uses most.
class QuantityStepper extends StatefulWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.step = 1,
    this.editable = false,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double? max;
  final double step;

  /// Lets the number itself be typed, not just tapped up/down by [step] —
  /// worthwhile once a line can plausibly need a quantity far from 1 (a
  /// transfer request for 60 units shouldn't take 60 taps).
  final bool editable;

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late final _controller = TextEditingController(text: qty(widget.value));
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Don't stomp on what's mid-typing — only resync from outside changes
    // (the +/- buttons, or a parent clamping the value) while unfocused.
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = qty(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _controller.text = qty(widget.value);
      return;
    }
    final min = widget.min;
    final max = widget.max;
    final clamped = max == null
        ? (parsed < min ? min : parsed)
        : parsed.clamp(min, max);
    widget.onChanged(clamped);
    _controller.text = qty(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.value;
    final step = widget.step;
    final canDecrease = value - step >= widget.min - 0.0001;
    final maxValue = widget.max;
    final canIncrease = maxValue == null || value + step <= maxValue + 0.0001;

    // Pill-shaped, 48dp tall: '−' and '+' flank a large centred number.
    return Container(
      height: kTouchTarget,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLowest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove_rounded,
            onPressed: canDecrease ? () => widget.onChanged(value - step) : null,
            tooltip: 'Decrease',
          ),
          if (widget.editable)
            SizedBox(
              width: 44,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: _submit,
                onTapOutside: (_) => _submit(_controller.text),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 32),
              child: Text(
                qty(value),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          _StepperButton(
            icon: Icons.add_rounded,
            onPressed: canIncrease ? () => widget.onChanged(value + step) : null,
            tooltip: 'Increase',
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: kTouchTarget,
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null ? scheme.outline : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Debounced search field — one request per pause, not per keystroke.
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.autofocus = false,
    this.initialValue,
    this.debounce = const Duration(milliseconds: 350),
    this.trailing,
    this.action,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final bool autofocus;
  final String? initialValue;
  final Duration debounce;

  /// Icon inside the field, right of the text — e.g. a barcode scanner.
  final Widget? trailing;

  /// Separate square button beside the field — e.g. a filter sheet.
  final Widget? action;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

OutlineInputBorder _pill(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: color, width: width),
    );

class _SearchBoxState extends State<SearchBox> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(value.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 56dp: the search field is a primary target on almost every screen, and on
    // a counter-mounted tablet it gets hit at arm's length.
    final field = SizedBox(
      height: kSearchHeight,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: (value) {
          _timer?.cancel();
          widget.onChanged(value.trim());
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          // Fully round, unlike the app's other inputs: search is the one field
          // that reads as a control rather than a form, and the till mockup draws
          // it as a pill.
          border: _pill(scheme.outlineVariant),
          enabledBorder: _pill(scheme.outlineVariant),
          focusedBorder: _pill(scheme.primary, width: 1.6),
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    _onChanged('');
                    widget.onChanged('');
                  },
                )
              : widget.trailing,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );

    final action = widget.action;
    if (action == null) return field;

    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 10),
        Container(
          width: kSearchHeight,
          height: kSearchHeight,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: action,
        ),
      ],
    );
  }
}

/// A single headline number with its label — the "Today's Sales / Orders" pair
/// at the top of a list, or the two stats on the store card.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // onSurface, not bodySmall's onSurfaceVariant: this tile sits on the
          // warm tint, where the variant grey drops to 4.4:1.
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: priceDisplayStyle(context, color: valueColor),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Bold section label above a list — "Recent Transactions".
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Numbered step marker for multi-part flows (exchange: returns, then new
/// items). Filled while the step is the current focus, tonal once it isn't.
class StepHeading extends StatelessWidget {
  const StepHeading({
    super.key,
    required this.step,
    required this.title,
    this.active = true,
  });

  final int step;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? scheme.primary : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$step',
              style: TextStyle(
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ],
      ),
    );
  }
}

/// From → to, drawn as a connected pair so the direction of a transfer is
/// readable without parsing the labels.
class RouteTrail extends StatelessWidget {
  const RouteTrail({
    super.key,
    required this.from,
    required this.to,
    this.highlightTo = true,
    this.completed = false,
  });

  final String from;
  final String to;

  /// Emphasises the destination — used when this store is the receiver.
  final bool highlightTo;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final endColor = completed
        ? successColor(scheme.brightness)
        : (highlightTo ? scheme.primary : scheme.onSurfaceVariant);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(width: 2, height: 18, color: scheme.outlineVariant),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: completed ? endColor : Colors.transparent,
                  border: Border.all(color: endColor, width: 2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 10),
              Text(
                to,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-width banner for a settlement outcome. Orange when the customer owes,
/// green when money goes back — the two states a cashier must not misread.
class SettlementBanner extends StatelessWidget {
  const SettlementBanner({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// Explicit "Load More" instead of silent infinite scroll, so the end of the
/// loaded set is obvious and paging is a deliberate act.
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({super.key, required this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded),
          label: Text(busy ? 'Loading…' : 'Load More'),
        ),
      ),
    );
  }
}

/// Banner shown when the plan or the role hides everything in a section.
class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key, required this.what});

  final String what;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.lock_outline_rounded,
      title: '$what not available',
      message: "Your role or your tenant's plan doesn't include this. "
          'Ask an administrator if you need it.',
    );
  }
}

void showErrorSnack(BuildContext context, Object error) {
  final message = error is AppError ? error.uiMessage : 'Something went wrong.';
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // The background is overridden, so the foreground has to be too:
        // Material's default snackbar text colour is near-white, which on the
        // pale error container is 1.1:1 — a blank bar.
        content: Text(
          message,
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        backgroundColor: scheme.errorContainer,
        closeIconColor: scheme.onErrorContainer,
        showCloseIcon: true,
        duration: const Duration(seconds: 5),
      ),
    );
}

void showInfoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Loads once, rebuilds on retry/refresh. Used by every detail screen.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.builder,
    this.reloadToken,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, VoidCallback reload) builder;
  final Object? reloadToken;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  T? _value;
  AppError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(AsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.load();
      if (!mounted) return;
      setState(() {
        _value = value;
        _loading = false;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const AppError(
          code: ErrorCodes.unknown,
          message: 'Something went wrong.',
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final value = _value;
    if (_loading && value == null) return const LoadingView();
    if (error != null && value == null) {
      return ErrorView(error: error, onRetry: _run);
    }
    if (value == null) return const LoadingView();
    return RefreshIndicator(
      onRefresh: _run,
      child: widget.builder(context, value, _run),
    );
  }
}

/// One tab inside a [TabbedArea].
///
/// The child is built with whether it is the *visible* tab, because a Scaffold
/// inside a TabBarView keeps painting its floating action button while the
/// neighbouring tab is on screen — which is why "New return", "New exchange" and
/// "New transfer" appeared stacked on top of each other.
class AreaTab {
  const AreaTab({required this.label, this.icon, required this.builder});

  final String label;
  final IconData? icon;
  final Widget Function(bool active) builder;
}

/// A tab bar over a set of screens, where each screen knows if it's the one being
/// looked at.
///
/// Replaces the hand-rolled `DefaultTabController` + `TabBarView` in each merged
/// area, so the "only the active tab owns the FAB" rule is written once.
class TabbedArea extends StatefulWidget {
  const TabbedArea({super.key, required this.tabs, this.visible = true});

  final List<AreaTab> tabs;

  /// Whether the parent screen is the one currently on screen.
  ///
  /// The shell keeps visited bottom-nav tabs mounted in an [IndexedStack]; pass
  /// `false` when this area is off-screen so its floating action button is not
  /// painted on top of the active tab's.
  final bool visible;

  @override
  State<TabbedArea> createState() => _TabbedAreaState();
}

class _TabbedAreaState extends State<TabbedArea>
    with TickerProviderStateMixin {
  TabController? _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _rebuildController();
  }

  @override
  void didUpdateWidget(TabbedArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Permissions can reload and change how many tabs there are; a TabController
    // whose length no longer matches its TabBar throws.
    if (oldWidget.tabs.length != widget.tabs.length) _rebuildController();
  }

  void _rebuildController() {
    _controller?.dispose();
    _index = 0;
    _controller = TabController(length: widget.tabs.length, vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final controller = _controller;
    if (controller == null) return;
    // Fires repeatedly through the swipe animation, so only the settled index
    // matters — otherwise every frame is a setState.
    if (controller.indexIsChanging || controller.index == _index) return;
    setState(() => _index = controller.index);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTabChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const LoadingView();
    final tabs = widget.tabs;
    if (tabs.length == 1) return tabs.first.builder(widget.visible);

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: controller,
            // Set here rather than in a `tabBarTheme`: the type of that ThemeData
            // field changed between Flutter versions (TabBarTheme →
            // TabBarThemeData), and this is the app's only TabBar. Dark mode gets
            // the lighter step because the brand blue as text on the dark bare
            // surface is only ~3.4:1 — see kPrimaryOnDark.
            labelColor: Theme.of(context).brightness == Brightness.dark
                ? kPrimaryOnDark
                : kPrimary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            isScrollable: tabs.length > 3,
            tabAlignment:
                tabs.length > 3 ? TabAlignment.start : TabAlignment.fill,
            tabs: [
              for (final tab in tabs)
                Tab(
                  text: tab.label,
                  icon: tab.icon == null ? null : Icon(tab.icon, size: 20),
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              for (var i = 0; i < tabs.length; i++)
                tabs[i].builder(widget.visible && i == _index),
            ],
          ),
        ),
      ],
    );
  }
}
