import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand.dart';
import 'auth_controller.dart';

enum _Step { email, code, appPassword }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _appPassword = TextEditingController();
  late final _server = TextEditingController(text: ref.read(settingsProvider).serverUrl);
  var _step = _Step.email;
  var _busy = false;
  var _showServer = false;
  String? _error;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _appPassword.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    ref.read(settingsProvider.notifier).setServerUrl(_server.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    if (!_email.text.contains('@')) throw 'Enter your email address';
    final sent = await ref.read(authProvider.notifier).sendCode(_email.text);
    setState(() {
      _sentTo = sent;
      _step = _Step.code;
    });
  });

  Future<void> _verify() => _run(() async {
    if (_code.text.trim().length < 4) throw 'Enter the code from your email';
    await ref.read(authProvider.notifier).verifyCode(_email.text, _code.text);
  });

  Future<void> _useAppPassword() => _run(() async {
    if (!_appPassword.text.trim().startsWith('emeapp.')) throw 'Application passwords start with "emeapp."';
    await ref.read(authProvider.notifier).useAppPassword(_appPassword.text);
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.shell,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandMark(size: 44)),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(switch (_step) {
                            _Step.email => 'Sign in',
                            _Step.code => 'Check your email',
                            _Step.appPassword => 'Application password',
                          }, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(switch (_step) {
                            _Step.email => 'We will email you a 6 digit sign-in code.',
                            _Step.code => 'Enter the code we sent to ${_sentTo ?? _email.text}.',
                            _Step.appPassword => 'Paste an application password created in EME.',
                          }, style: TextStyle(color: c.muted)),
                          const SizedBox(height: 20),
                          ..._fields(),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!, style: TextStyle(color: context.scheme.error)),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : switch (_step) {
                                    _Step.email => _sendCode,
                                    _Step.code => _verify,
                                    _Step.appPassword => _useAppPassword,
                                  },
                            child: _busy
                                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(switch (_step) {
                                    _Step.email => 'Send code',
                                    _Step.code => 'Sign in',
                                    _Step.appPassword => 'Sign in',
                                  }),
                          ),
                          const SizedBox(height: 8),
                          if (_step != _Step.email)
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _step = _Step.email),
                              child: const Text('Back'),
                            )
                          else
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _step = _Step.appPassword),
                              child: const Text('Use an application password'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => setState(() => _showServer = !_showServer),
                  icon: const Icon(Ph.hardDrives, size: 14),
                  label: Text(_showServer ? 'Hide server' : 'Server: ${ref.watch(settingsProvider).serverUrl}'),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                ),
                if (_showServer)
                  TextField(
                    controller: _server,
                    decoration: const InputDecoration(labelText: 'Server address', hintText: defaultServerUrl),
                    onSubmitted: (v) => ref.read(settingsProvider.notifier).setServerUrl(v),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() => switch (_step) {
    _Step.email => [
      TextField(
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Ph.envelopeSimple, size: 16)),
        onSubmitted: (_) => _sendCode(),
      ),
    ],
    _Step.code => [
      TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(hintText: '••••••'),
        onSubmitted: (_) => _verify(),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Send a new code')),
      ),
    ],
    _Step.appPassword => [
      TextField(
        controller: _appPassword,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'emeapp.…', prefixIcon: Icon(Ph.key, size: 16)),
        onSubmitted: (_) => _useAppPassword(),
      ),
    ],
  };
}
