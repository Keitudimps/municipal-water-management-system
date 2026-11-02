import 'package:flutter/material.dart';
import 'api.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';
import 'dashboard.dart';

class DashboardGate extends StatefulWidget {
  const DashboardGate({super.key});

  @override
  State<DashboardGate> createState() => _DashboardGateState();
}

class _DashboardGateState extends State<DashboardGate> {
  DashboardUser? _user;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.sessionExpired.addListener(_onSessionExpired);
    _restoreSession();
  }

  @override
  void dispose() {
    Api.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onSessionExpired() {
    if (!Api.sessionExpired.value || !mounted) return;
    setState(() {
      _user = null;
      _error = null;
      _loading = false;
    });
  }

  Future<void> _restoreSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await Api.restoreDashboardSession();
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    String? error;
    try {
      await Api.logout();
    } on ApiException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() => _user = null);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: ts(14, color: C.muted)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _restoreSession, child: const Text('Try again')),
          ]),
        ),
      );
    }
    final user = _user;
    if (user == null) {
      return _DashboardLogin(
        onLogin: (signedInUser) => setState(() => _user = signedInUser),
      );
    }
    return DashboardScreen(user: user, onLogout: _logout);
  }
}

class _DashboardLogin extends StatefulWidget {
  final ValueChanged<DashboardUser> onLogin;
  const _DashboardLogin({required this.onLogin});

  @override
  State<_DashboardLogin> createState() => _DashboardLoginState();
}

class _DashboardLoginState extends State<_DashboardLogin> {
  final _userNumber = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userNumber.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await Api.login(_userNumber.text.trim(), _password.text);
      if (mounted) widget.onLogin(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: cardDeco(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: Logo()),
                    const SizedBox(height: 20),
                    Text('Operations sign in',
                        textAlign: TextAlign.center,
                        style: ts(24, w: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Use your staff number and password to continue.',
                        textAlign: TextAlign.center,
                        style: ts(14, color: C.muted)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _userNumber,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Staff number',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: ts(13, color: C.red)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
