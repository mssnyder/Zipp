import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  final _setPwCtrl = TextEditingController();
  final _setPwConfirmCtrl = TextEditingController();
  bool _saving = false;
  bool _changingPw = false;
  bool _settingPw = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _obscureSetPw = true;
  bool _obscureSetPwConfirm = true;
  String? _profileError;
  String? _pwError;
  String? _setPwError;
  Timer? _linkPollTimer;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _displayNameCtrl.text = user?.displayName ?? '';
    _usernameCtrl.text = user?.username ?? '';
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _setPwCtrl.dispose();
    _setPwConfirmCtrl.dispose();
    _linkPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _profileError = null; });
    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthProvider>();
      final updated = await api.updateMe(
        displayName: _displayNameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
      );
      auth.updateUser(updated);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')));
    } on ApiException catch (e) {
      setState(() => _profileError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (xfile == null) return;

    setState(() => _saving = true);
    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthProvider>();
      final bytes = await xfile.readAsBytes();
      final updated = await api.uploadAvatar(bytes, xfile.name);
      auth.updateUser(updated);
    } on ApiException catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final newPw = _newPwCtrl.text;
    final confirmPw = _confirmPwCtrl.text;
    if (newPw != confirmPw) {
      setState(() => _pwError = 'New passwords do not match');
      return;
    }
    if (newPw.length < 8) {
      setState(() => _pwError = 'Password must be at least 8 characters');
      return;
    }

    setState(() { _changingPw = true; _pwError = null; });
    try {
      final auth = context.read<AuthProvider>();
      String? encPriv, kSalt, kNonce;
      // Re-encrypt private key backup with the new password
      if (auth.keyPair != null) {
        final privBytes = await auth.keyPair!.extractPrivateKeyBytes();
        final backup = await CryptoService.encryptPrivateKey(privBytes, newPw);
        encPriv = backup.encryptedPrivateKey;
        kSalt = backup.keySalt;
        kNonce = backup.keyNonce;
      }
      await context.read<ApiService>().changePassword(
        current: _currentPwCtrl.text,
        newPass: newPw,
        encryptedPrivateKey: encPriv,
        keySalt: kSalt,
        keyNonce: kNonce,
      );
      _currentPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated')));
    } on ApiException catch (e) {
      setState(() => _pwError = e.message);
    } finally {
      if (mounted) setState(() => _changingPw = false);
    }
  }

  Future<void> _setPassword() async {
    final pw = _setPwCtrl.text;
    final confirm = _setPwConfirmCtrl.text;
    if (pw != confirm) {
      setState(() => _setPwError = 'Passwords do not match');
      return;
    }
    if (pw.length < 8) {
      setState(() => _setPwError = 'Password must be at least 8 characters');
      return;
    }

    setState(() { _settingPw = true; _setPwError = null; });
    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthProvider>();
      await api.setPassword(pw);

      // Encrypt and upload private key backup with the new password
      if (auth.keyPair != null) {
        final privBytes = await auth.keyPair!.extractPrivateKeyBytes();
        final backup = await CryptoService.encryptPrivateKey(privBytes, pw);
        final localPub = await CryptoService.getPublicKeyBase64(auth.keyPair!);
        await api.uploadPublicKey(
          localPub,
          encryptedPrivateKey: backup.encryptedPrivateKey,
          keySalt: backup.keySalt,
          keyNonce: backup.keyNonce,
        );
      }

      // Refresh user to reflect hasPassword = true
      final updated = await api.getMe();
      auth.updateUser(updated);

      _setPwCtrl.clear();
      _setPwConfirmCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Encryption password set')));
    } on ApiException catch (e) {
      setState(() => _setPwError = e.message);
    } finally {
      if (mounted) setState(() => _settingPw = false);
    }
  }

  Future<void> _unlinkAccount(String provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZippTheme.surface,
        title: const Text('Unlink account'),
        content: Text('Remove your $provider login?'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Remove', style: TextStyle(color: ZippTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthProvider>();
      await api.unlinkAccount(provider);
      final updated = await api.getMe();
      auth.updateUser(updated);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$provider unlinked')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: ZippTheme.error));
    }
  }

  Future<void> _linkGoogle() async {
    try {
      final api = context.read<ApiService>();
      final result = await api.getLinkToken();
      final url = Uri.parse(result['url']!);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open browser');
      }
      _startLinkPoll();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: ZippTheme.error));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: ZippTheme.error));
    }
  }

  void _startLinkPoll() {
    _linkPollTimer?.cancel();
    final initialCount = context.read<AuthProvider>().user?.linkedProviders.length ?? 0;
    int attempts = 0;
    _linkPollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      attempts++;
      if (attempts > 20) { t.cancel(); return; }
      if (!mounted) { t.cancel(); return; }
      try {
        final api = context.read<ApiService>();
        final auth = context.read<AuthProvider>();
        final updated = await api.getMe();
        if (updated.linkedProviders.length > initialCount) {
          t.cancel();
          auth.updateUser(updated);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google account linked')));
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      backgroundColor: ZippTheme.background,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Avatar ──────────────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: ZippTheme.surfaceVariant,
                          backgroundImage: user.avatarUrl != null
                              ? NetworkImage(context.read<ApiService>().resolveUrl(user.avatarUrl!))
                              : null,
                          child: user.avatarUrl == null
                              ? Text(
                                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 40, color: ZippTheme.accent1),
                                )
                              : null,
                        ),
                        if (!kIsWeb)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: ZippTheme.accent1,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: Text(user.email, style: Theme.of(context).textTheme.bodySmall)),
                const SizedBox(height: 32),

                // ── Profile fields ──────────────────────────────────────────
                if (_profileError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_profileError!, style: const TextStyle(color: ZippTheme.error)),
                  ),
                TextFormField(
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: _saving
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(onPressed: _save, child: const Text('Save changes')),
                ),

                const SizedBox(height: 32),
                const Divider(),

                // ── Set encryption password (for OAuth-only accounts) ─────────
                if (!user.hasPassword) ...[
                  const SizedBox(height: 24),
                  Text('Set encryption password', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'A password is required to encrypt your private key so messages can be decrypted on other devices.',
                    style: TextStyle(fontSize: 13, color: ZippTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (_setPwError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_setPwError!, style: const TextStyle(color: ZippTheme.error)),
                    ),
                  TextFormField(
                    controller: _setPwCtrl,
                    obscureText: _obscureSetPw,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSetPw
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureSetPw = !_obscureSetPw),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _setPwConfirmCtrl,
                    obscureText: _obscureSetPwConfirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _setPassword(),
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSetPwConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureSetPwConfirm = !_obscureSetPwConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: _settingPw
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _setPassword,
                            child: const Text('Set password'),
                          ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                ],

                // ── Change password (only for accounts with a password) ──────
                if (user.hasPassword) ...[
                  const SizedBox(height: 24),
                  Text('Change password', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  if (_pwError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_pwError!, style: const TextStyle(color: ZippTheme.error)),
                    ),
                  TextFormField(
                    controller: _currentPwCtrl,
                    obscureText: _obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureCurrent
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPwCtrl,
                    obscureText: _obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPwCtrl,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _changePassword(),
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: _changingPw
                        ? const Center(child: CircularProgressIndicator())
                        : OutlinedButton(
                            onPressed: _changePassword,
                            child: const Text('Update password'),
                          ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                ],

                // ── Linked accounts ─────────────────────────────────────────
                const SizedBox(height: 24),
                Text('Linked accounts', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _LinkedAccountRow(
                  provider: 'google',
                  label: 'Google',
                  icon: Icons.g_mobiledata,
                  isLinked: user.linkedProviders.contains('google'),
                  canUnlink: user.hasPassword || user.linkedProviders.length > 1,
                  onLink: _linkGoogle,
                  onUnlink: () => _unlinkAccount('google'),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkedAccountRow extends StatelessWidget {
  final String provider;
  final String label;
  final IconData icon;
  final bool isLinked;
  final bool canUnlink;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  const _LinkedAccountRow({
    required this.provider,
    required this.label,
    required this.icon,
    required this.isLinked,
    required this.canUnlink,
    required this.onLink,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ZippTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZippTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: isLinked ? ZippTheme.accent2 : ZippTheme.textSecondary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  isLinked ? 'Connected' : 'Not connected',
                  style: TextStyle(
                    fontSize: 12,
                    color: isLinked ? ZippTheme.online : ZippTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isLinked && canUnlink)
            TextButton(
              onPressed: onUnlink,
              child: const Text('Unlink', style: TextStyle(color: ZippTheme.error)),
            )
          else if (!isLinked)
            TextButton(
              onPressed: onLink,
              child: const Text('Link', style: TextStyle(color: ZippTheme.accent2)),
            ),
        ],
      ),
    );
  }
}
