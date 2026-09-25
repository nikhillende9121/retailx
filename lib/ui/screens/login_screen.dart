import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/api_client.dart';
import '../../data/demo_backend.dart';
import '../../data/token_store.dart' show normalizeBaseUrl;
import '../../state/providers.dart';
import '../widgets/app_icon_glyph.dart';
import 'more/request_log_screen.dart';

/// Tenant code + email + password. The tenant code is required because email is
/// only unique within a tenant, so the server can't tell which tenant to check
/// without it.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// One-off message, e.g. after a forced sign-out.
  final String? notice;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final TextEditingController _password = TextEditingController();
  late final TextEditingController _server;

  bool _busy = false;
  bool _obscure = true;
  bool _showServer = true;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider.notifier);
    _email = TextEditingController(text: session.lastEmail ?? '');
    _server = TextEditingController(text: session.baseUrl);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // A real sign-in always leaves demo mode, even if the last session was one.
    DemoBackend.enabled = false;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _email.text,
            password: _password.text,
            serverUrl: _server.text,
          );
      // On success the gate swaps this screen out; nothing else to do.
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not sign in.',
        );
        _busy = false;
      });
    }
  }

  // Signs in against the in-memory demo backend instead of the network, so
  // the whole app can be walked through with realistic data and no server.
  // Only used by the demo-mode button, hidden below — kept commented
  // alongside it rather than deleted.
  // Future<void> _enterDemo() async {
  //   setState(() {
  //     _busy = true;
  //     _error = null;
  //   });
  //   DemoBackend.enabled = true;
  //   try {
  //     await ref.read(sessionProvider.notifier).login(
  //           email: 'demo@store.test',
  //           password: 'demo',
  //         );
  //   } on AppError catch (error) {
  //     DemoBackend.enabled = false;
  //     if (!mounted) return;
  //     setState(() {
  //       _error = error;
  //       _busy = false;
  //     });
  //   } catch (_) {
  //     DemoBackend.enabled = false;
  //     if (!mounted) return;
  //     setState(() {
  //       _error = const AppError(
  //         code: ErrorCodes.unknown,
  //         message: 'Could not start demo mode.',
  //       );
  //       _busy = false;
  //     });
  //   }
  // }

  // Sends one real request to the configured server and shows the raw
  // result. Only used by the server-settings UI, hidden below — kept
  // commented alongside it rather than deleted.
  Future<void> _testConnection() async {
    setState(() => _busy = true);
    final result = await probeServer(_server.text);
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connection test'),
        content: SingleChildScrollView(
          child: SelectableText(
            result,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String? _fieldError(String field) => _error?.fieldErrors[field];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mirrors the launcher icon's glyph (drawn from
                    // ic_launcher_foreground.xml's path data, not the
                    // Material "shopping bag" icon, which is a different
                    // shape) — no background tile, just the mark itself.
                    //
                    // Wrapped in Align: the Column's stretch cross-alignment
                    // would otherwise force this box to the full row width,
                    // and since the painter scales x/y independently to fill
                    // its box, that stretch smeared the glyph sideways.
                    Align(
                      child: AppIconGlyph(height: 53, color: scheme.primary),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'RetailX',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to run your store',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 26),
                    if (widget.notice != null && error == null)
                      _Banner(
                        message: widget.notice!,
                        color: scheme.secondaryContainer,
                        textColor: scheme.onSecondaryContainer,
                        icon: Icons.info_outline_rounded,
                      ),
                    if (error != null)
                      _Banner(
                        message: error.uiMessage,
                        color: scheme.errorContainer,
                        textColor: scheme.onErrorContainer,
                        icon: Icons.error_outline_rounded,
                      ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        errorText: _fieldError('email'),
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Email is required'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        errorText: _fieldError('password'),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Password is required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    // Server-settings toggle (base URL input + test-connection)
                    // hidden from the sign-in screen — the cashier never needs
                    // to change it. Kept commented rather than deleted.
                    Row(
                      children: [
                        Flexible(
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => _showServer = !_showServer),
                            icon: Icon(_showServer
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded),
                            label: const Text(
                              'Server settings',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (kDebugMode)
                          IconButton(
                            tooltip: 'Request log',
                            icon: const Icon(Icons.wifi_tethering_rounded,
                                size: 20),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const Scaffold(
                                  body: SafeArea(child: RequestLogScreen()),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_showServer) ...[
                      TextFormField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'API base URL',
                          helperText: 'Must end at /api/v1',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Server address is required';
                          }
                          final uri = Uri.tryParse(normalizeBaseUrl(value));
                          if (uri == null || uri.host.isEmpty) {
                            return 'That does not look like a URL';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _testConnection,
                        icon: const Icon(Icons.network_check_rounded, size: 18),
                        label: const Text('Test connection'),
                      ),
                      const SizedBox(height: 14),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your session stays signed in for up to 7 days.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    // Demo mode entry point — hidden from the sign-in screen.
                    // Kept commented rather than deleted.
                    // const SizedBox(height: 22),
                    // Row(
                    //   children: [
                    //     Expanded(child: Divider(color: scheme.outlineVariant)),
                    //     Padding(
                    //       padding: const EdgeInsets.symmetric(horizontal: 10),
                    //       child: Text(
                    //         'or',
                    //         style: TextStyle(color: scheme.onSurfaceVariant),
                    //       ),
                    //     ),
                    //     Expanded(child: Divider(color: scheme.outlineVariant)),
                    //   ],
                    // ),
                    // const SizedBox(height: 14),
                    // OutlinedButton.icon(
                    //   onPressed: _busy ? null : _enterDemo,
                    //   icon: const Icon(Icons.play_circle_outline_rounded),
                    //   label: const Text('Explore in demo mode'),
                    // ),
                    // const SizedBox(height: 6),
                    // Text(
                    //   'No server needed — sample products, sales, purchases and '
                    //   'stock, all held in memory. Stock really moves when you '
                    //   'charge a sale or receive a purchase.',
                    //   textAlign: TextAlign.center,
                    //   style: Theme.of(context)
                    //       .textTheme
                    //       .bodySmall
                    //       ?.copyWith(color: scheme.onSurfaceVariant),
                    // ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.textColor,
    required this.icon,
  });

  final String message;
  final Color color;
  final Color textColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }
}

