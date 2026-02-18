import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  final bool showRegister;
  const LoginScreen({super.key, this.showRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isRegister;
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _isRegister = widget.showRegister;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();

    if (_isRegister) {
      try {
        await auth.register(
          email: _emailCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
          displayName: _displayNameCtrl.text.trim().isEmpty ? null : _displayNameCtrl.text.trim(),
        );
        setState(() {
          _successMsg = 'Account created! Check your email to verify, then log in.';
          _isRegister = false;
        });
      } catch (_) {}
    } else {
      try {
        await auth.login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
        if (mounted) context.go('/');
      } catch (_) {}
    }
  }

  Future<void> _signInWithGoogle() async {
    final uri = Uri.parse('${ZippConfig.serverUrl}/connect/google');
    if (kIsWeb) {
      // On web the page navigates away → OAuth → redirects back → app reloads logged in
      await launchUrl(uri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_self');
    } else {
      // On desktop the browser handles it but the app's cookie jar won't receive the cookie
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Google sign-in is fully supported in the web app. On desktop, use email/password.'),
          duration: Duration(seconds: 5),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: ZippTheme.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    ShaderMask(
                      shaderCallback: (b) => ZippTheme.accentGradient.createShader(b),
                      child: const Text(
                        'Zipp',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -2,
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .slideY(begin: -0.2, end: 0, curve: Curves.easeOut),
                    const SizedBox(height: 8),
                    Text(
                      'Private encrypted messaging',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ZippTheme.textSecondary,
                          ),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 48),

                    if (_successMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ZippTheme.online.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ZippTheme.online.withAlpha(80)),
                        ),
                        child: Text(_successMsg!, style: const TextStyle(color: ZippTheme.online)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (auth.error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ZippTheme.error.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ZippTheme.error.withAlpha(80)),
                        ),
                        child: Text(auth.error!, style: const TextStyle(color: ZippTheme.error)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                          ),
                          if (_isRegister) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _usernameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                              validator: (v) => v == null || v.length < 3 ? 'Min 3 characters' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _displayNameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Display name (optional)',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => _isRegister && (v == null || v.length < 8)
                                ? 'Min 8 characters'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: auth.loading
                                ? const Center(child: CircularProgressIndicator())
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: ZippTheme.accentGradient,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: _submit,
                                      child: Text(
                                        _isRegister ? 'Create Account' : 'Sign In',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: ZippTheme.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or', style: TextStyle(color: ZippTheme.textSecondary, fontSize: 13)),
                        ),
                        const Expanded(child: Divider(color: ZippTheme.border)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: ZippTheme.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'G',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Continue with Google',
                              style: TextStyle(color: ZippTheme.textPrimary, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _isRegister = !_isRegister;
                        _successMsg = null;
                      }),
                      child: Text(
                        _isRegister
                            ? 'Already have an account? Sign in'
                            : "Don't have an account? Register",
                        style: const TextStyle(color: ZippTheme.accent2),
                      ),
                    ),
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
