import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Spacing and shape constants.
///
/// Softer than the original Precision POS spec: the till mockup the shop asked
/// for is rounded and warm, and a 6px card next to an 18px product tile reads as
/// two different apps. Everything moves together so it doesn't.
const double kTouchTarget = 48;
const double kRadiusCard = 14;
const double kRadiusButton = 14;
const double kRadiusInput = 14;

/// Product tiles and the cart sheet — the roundest things on screen.
const double kRadiusTile = 18;
const double kRadiusSheet = 24;
const double kScreenMargin = 16;
const double kCardGap = 12;
const double kListRowHeight = 64;
const double kSearchHeight = 56;

/// "Slate Blue" palette — neutral, corporate, high-contrast: comfortable to
/// read through a long shift, glanceable during a fast checkout.
///
/// Success green and error red are reserved strictly for payment/validation
/// outcomes — approved, declined, invalid — and nothing else in the app
/// borrows them; the brand blue never stands in for either.
const Color kPrimary = Color(0xFF2563EB);
const Color kDark = Color(0xFF1E293B);
const Color kAccentBlue = Color(0xFF0EA5E9);
const Color kSurfaceTint = Color(0xFFF1F5F9);
const Color kSuccess = Color(0xFF15803D);
const Color kError = Color(0xFFDC2626);

/// Brighter steps of the same two hues.
///
/// [kSuccess] and [kError] are dark enough that white text on them still
/// clears 4.5:1 (5.0:1 and 4.8:1) — but read the other way, as *text on a
/// dark surface*, the arithmetic flips against them: contrast against a
/// background is capped at `(L_fg + 0.05) / 0.05`, and both tones' own
/// luminance already puts that ceiling under 4.5:1 no matter how dark the
/// background gets. So a dark surface gets the brighter step of the same hue
/// instead — see [successColor] and [statusColor].
const Color kSuccessBright = Color(0xFF4ADE80);
const Color kErrorBright = Color(0xFFF87171);

/// [kPrimary] as plain text directly on a bare dark surface.
///
/// Buttons keep the literal brand blue in both themes — white on #2563EB is
/// ~5.2:1 regardless of what's around the button. But that same blue as text
/// sitting on the dark theme's bare background is only ~3.4:1, so TextButtons,
/// links and focus rings use this lighter step in dark mode instead.
const Color kPrimaryOnDark = Color(0xFF60A5FA);

/// AA-safe success tone for the given brightness — see [kSuccessBright].
Color successColor(Brightness brightness) =>
    brightness == Brightness.dark ? kSuccessBright : kSuccess;

const ColorScheme _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: kPrimary,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDBEAFE),
  onPrimaryContainer: Color(0xFF1E3A8A),
  secondary: kAccentBlue,
  // Not white: white on the accent sky-blue is 2.8:1. Dark clears 5.3:1.
  onSecondary: kDark,
  secondaryContainer: Color(0xFFE0F2FE),
  onSecondaryContainer: Color(0xFF0C4A6E),
  // Neutral slate, not a third blue — "in progress" is a status, not a brand
  // moment, and it shouldn't compete with the primary action for the eye.
  tertiary: kDark,
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFE2E8F0),
  onTertiaryContainer: Color(0xFF0F172A),
  error: kError,
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFEE2E2),
  onErrorContainer: Color(0xFF7F1D1D),
  // Screen background, cards and list rows all live in this one neutral tone;
  // cards lift off it the way surfaceContainerLowest always has, by going
  // brighter still rather than by switching hue.
  surface: kSurfaceTint,
  onSurface: kDark,
  onSurfaceVariant: Color(0xFF334155),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF8FAFC),
  surfaceContainer: kSurfaceTint,
  surfaceContainerHigh: Color(0xFFE2E8F0),
  surfaceContainerHighest: Color(0xFFCBD5E1),
  outline: Color(0xFF94A3B8),
  outlineVariant: Color(0xFFE2E8F0),
  inverseSurface: kDark,
  onInverseSurface: Color(0xFFFFFFFF),
  inversePrimary: Color(0xFF93C5FD),
);

const ColorScheme _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  // Literal brand blue, unchanged — see [kPrimaryOnDark] for the one place
  // (plain text on the bare dark surface) that needs the lighter step.
  primary: kPrimary,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF1E40AF),
  onPrimaryContainer: Color(0xFFDBEAFE),
  secondary: kAccentBlue,
  onSecondary: kDark,
  secondaryContainer: Color(0xFF075985),
  onSecondaryContainer: Color(0xFFE0F2FE),
  tertiary: Color(0xFF94A3B8),
  onTertiary: Color(0xFF0F172A),
  tertiaryContainer: Color(0xFF334155),
  onTertiaryContainer: Color(0xFFE2E8F0),
  // kError itself can't clear 4.5:1 as text on a dark surface — see the doc
  // comment on kSuccessBright/kErrorBright.
  error: kErrorBright,
  onError: Color(0xFF7F1D1D),
  errorContainer: Color(0xFF7F1D1D),
  onErrorContainer: Color(0xFFFEE2E2),
  surface: Color(0xFF0F172A),
  // The light theme's Surface tone, reused as dark-mode text.
  onSurface: kSurfaceTint,
  onSurfaceVariant: Color(0xFF94A3B8),
  surfaceContainerLowest: Color(0xFF020617),
  surfaceContainerLow: Color(0xFF0F172A),
  surfaceContainer: kDark,
  surfaceContainerHigh: Color(0xFF334155),
  surfaceContainerHighest: Color(0xFF475569),
  outline: Color(0xFF475569),
  outlineVariant: Color(0xFF334155),
  inverseSurface: kSurfaceTint,
  onInverseSurface: kDark,
  inversePrimary: Color(0xFF1D4ED8),
);

ThemeData buildTheme(Brightness brightness) {
  final scheme =
      brightness == Brightness.dark ? _darkScheme : _lightScheme;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    textTheme: _textTheme(scheme),
    // Every primary tap target is forced to 48dp minimum — fast, imprecise
    // touch is the normal case at a till, not the exception.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, kTouchTarget),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusButton)),
        // 17/700 rather than 16/600: white on the brand blue is ~5.2:1, and the
        // extra size and weight is what keeps a filled button's label crisp at
        // that ratio during a fast glance.
        textStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        // Material's default disabled pair is onSurface at 38% on onSurface at
        // 12%, which is 2.3:1 — and these buttons spend their disabled time
        // showing "Working…", which is text the user is meant to read.
        disabledBackgroundColor: scheme.surfaceContainerHigh,
        disabledForegroundColor: scheme.onSurfaceVariant,
      ),
    ),
    // Solid #2563EB with white text (FilledButton's own default reads
    // colorScheme.primary/onPrimary, which are pinned to that pair in both
    // themes) — outlined in the same blue is the secondary form, so the two
    // read as one family of action, not two different colours competing.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, kTouchTarget),
        side: BorderSide(color: kPrimary),
        foregroundColor: brightness == Brightness.dark ? kPrimaryOnDark : kPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusButton)),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: brightness == Brightness.dark ? kPrimaryOnDark : kPrimary,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInput),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInput),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInput),
        borderSide: BorderSide(
          color: brightness == Brightness.dark ? kPrimaryOnDark : kPrimary,
          width: 1.6,
        ),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: GoogleFonts.inter(fontSize: 15, color: scheme.onSurfaceVariant),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 10,
      visualDensity: VisualDensity.standard,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outline),
      shape: const StadiumBorder(),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      selectedColor: scheme.surfaceContainerHighest,
      secondarySelectedColor: scheme.surfaceContainerHighest,
      backgroundColor: scheme.surfaceContainerLowest,
      showCheckmark: false,
      // These are filter options, not primary actions — small and out of the
      // way, not sized like a button.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 3,
      // No forced shape: every FAB in this app is `.extended()` (icon +
      // label) — a fixed CircleBorder squeezed the label into a shape with
      // no room for it. Material3's own default per-variant shape (a
      // rounded rectangle for extended, a circle for a plain icon FAB, if
      // one's ever added) already handles both correctly.
      extendedTextStyle:
          GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: scheme.surfaceContainerLowest,
      // Icon only — the active tab reads as active from the icon's own size
      // and weight, not a label underneath it.
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      // No pill, no border — see [_Tab] in shell_screen.dart for how the
      // active icon signals selection instead.
      indicatorColor: Colors.transparent,
      indicatorShape: const StadiumBorder(side: BorderSide.none),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Inter throughout, with weight carrying the hierarchy: SemiBold and Bold are
/// used aggressively on data (SKUs, quantities, totals) so they separate from
/// their labels at a glance. Headlines tighten letter-spacing; small labels
/// loosen it, which keeps characters legible during fast movement.
TextTheme _textTheme(ColorScheme scheme) {
  final base = GoogleFonts.interTextTheme();
  return base.copyWith(
    // headline-lg (32/700) — screen titles on tablet.
    displaySmall: GoogleFonts.inter(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 40 / 32,
      letterSpacing: -0.64,
      color: scheme.onSurface,
    ),
    // The login screen's app-name wordmark. Left uncolored, this fell back
    // to Google Fonts' default near-black text and went unreadable on a
    // dark background.
    headlineMedium: GoogleFonts.inter(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 36 / 28,
      letterSpacing: -0.5,
      color: scheme.onSurface,
    ),
    // headline-lg-mobile (24/700) — the big screen title on a phone.
    headlineSmall: GoogleFonts.inter(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 32 / 24,
      letterSpacing: -0.3,
      color: scheme.onSurface,
    ),
    // headline-md (24/600) — section headings.
    titleLarge: GoogleFonts.inter(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 28 / 20,
      color: scheme.onSurface,
    ),
    // label-xl (20/600).
    titleMedium: GoogleFonts.inter(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 24 / 17,
      letterSpacing: 0.17,
      color: scheme.onSurface,
    ),
    // label-lg (14/600).
    titleSmall: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 20 / 14,
      letterSpacing: 0.1,
      color: scheme.onSurface,
    ),
    // body-lg (18/400).
    bodyLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 24 / 16,
      color: scheme.onSurface,
    ),
    // body-md (16/400).
    bodyMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 20 / 14,
      color: scheme.onSurface,
    ),
    // label-md (12/500).
    bodySmall: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 16 / 12,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: scheme.onSurface,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: scheme.onSurfaceVariant,
    ),
  );
}

/// price-display (28/700) — the most important number on a checkout screen.
TextStyle priceDisplayStyle(BuildContext context, {Color? color}) =>
    GoogleFonts.inter(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 32 / 26,
      letterSpacing: -0.26,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );

/// Icon that pairs with a status pill. Shape reinforces colour, so the state
/// survives a glance in bad lighting or on a washed-out screen.
IconData statusIcon(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'DRAFT':
      return Icons.edit_note_rounded;
    case 'CONFIRMED':
    case 'APPROVED':
      return Icons.check_circle_outline_rounded;
    case 'ORDERED':
      return Icons.local_shipping_outlined;
    case 'PENDING':
      return Icons.schedule_rounded;
    case 'PROCESSING':
      return Icons.sync_rounded;
    case 'PACKED':
      return Icons.inventory_2_outlined;
    case 'SHIPPED':
    case 'IN_TRANSIT':
      return Icons.local_shipping_rounded;
    case 'PARTIALLY_RECEIVED':
      return Icons.incomplete_circle_rounded;
    case 'DELIVERED':
    case 'COMPLETED':
    case 'RECEIVED':
      return Icons.check_circle_rounded;
    case 'CANCELLED':
    case 'REJECTED':
      return Icons.cancel_outlined;
    default:
      return Icons.circle_outlined;
  }
}

/// Semantic colour for a lifecycle status, so a glance at a list is enough.
Color statusColor(ColorScheme scheme, String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'DRAFT':
      return scheme.brightness == Brightness.dark
          ? scheme.onSurfaceVariant
          : const Color(0xFF475569);
    case 'CONFIRMED':
    case 'ORDERED':
    case 'PENDING':
    case 'APPROVED':
      // Neutral slate, not the brand blue — a lifecycle status pill shouldn't
      // read as if it were a button.
      return scheme.brightness == Brightness.dark
          ? const Color(0xFF94A3B8)
          : const Color(0xFF334155);
    case 'PROCESSING':
    case 'PACKED':
    case 'SHIPPED':
    case 'IN_TRANSIT':
    case 'PARTIALLY_RECEIVED':
      return scheme.tertiary;
    case 'DELIVERED':
    case 'COMPLETED':
    case 'RECEIVED':
      return successColor(scheme.brightness);
    case 'CANCELLED':
    case 'REJECTED':
      return scheme.error;
    default:
      // Not scheme.secondary: the accent sky-blue is 2.5:1 on its own tinted
      // pill, which fails the same AA bar every other status pill has to clear.
      return scheme.onSurfaceVariant;
  }
}
