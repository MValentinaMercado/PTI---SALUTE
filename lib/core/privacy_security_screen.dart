import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/auth/auth_error_handler.dart';
import 'package:saluteapp/core/app_navigator.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/password_policy.dart';
import 'package:saluteapp/legal/terms_screen.dart';

const _danger = Color(0xFFE74C3C);

/// Configuración > Privacidad y Seguridad: contraseña, recuperación,
/// cuentas vinculadas, documentos legales y eliminación de cuenta.
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final _auth = AuthService.instance;
  bool _busy = false;

  void _msg(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (ok != null && mounted) _msg(ok);
    } catch (e, st) {
      final text = userMessageFor(e, st, window: 'Privacidad y Seguridad');
      if (mounted) _msg(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReset() async {
    final email = _auth.currentUser?.email;
    if (email == null) {
      _msg('Tu cuenta no tiene un correo asociado.');
      return;
    }
    await _run(() => _auth.sendPasswordReset(email), ok: 'Te enviamos un enlace a $email.');
  }

  Future<void> _confirmUnlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desvincular Google'),
        content: const Text('Vas a poder seguir entrando con tu email y contraseña.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desvincular')),
        ],
      ),
    );
    if (ok == true) await _run(_auth.unlinkGoogle, ok: 'Google desvinculado.');
  }

  Future<void> _showProblem(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: _danger, size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }

  /// Eliminar cuenta, con el mismo recorrido que "Cerrar sesión":
  ///  1. Se confirma y se verifica identidad acá (rápido; los errores como
  ///     "contraseña incorrecta" se ven en esta pantalla).
  ///  2. Recién entonces se vuelve a la raíz y AuthGate muestra "Eliminando tu
  ///     cuenta…" mientras se borra todo; al terminar cae directo en el login.
  ///     Así no hay que quedarse mirando Configuración ni volver para atrás.
  Future<void> _deleteAccount() async {
    final hasPassword = _auth.hasPasswordProvider;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteAccountDialog(hasPassword: hasPassword),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _auth.verifyBeforeDeletion(password: hasPassword ? result : null);
    } catch (e, st) {
      final text = userMessageFor(
        e,
        st,
        window: 'Eliminar cuenta',
        fallback: 'No pudimos eliminar tu cuenta. Intentá de nuevo en unos minutos.',
      );
      if (mounted) {
        setState(() => _busy = false);
        // Es un motivo que el usuario tiene que poder leer con calma (ej. "sos
        // el admin de una familia con integrantes"): va en un diálogo, no en un
        // SnackBar que desaparece.
        await _showProblem('No se pudo eliminar la cuenta', text);
      }
      return;
    }
    if (!mounted) return;

    // Desde acá no hay vuelta atrás. Se activa la pantalla de "Eliminando…" y
    // se sacan todas las pantallas apiladas; el borrado sigue sin depender de
    // este widget.
    _auth.deletingAccount.value = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    _runAccountDeletion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'Privacidad y Seguridad', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: StreamBuilder<User?>(
                stream: _auth.userChanges,
                initialData: _auth.currentUser,
                builder: (context, snap) {
                  final hasPassword = _auth.hasPasswordProvider;
                  final hasGoogle = _auth.hasGoogleProvider;
                  final email = snap.data?.email ?? '';
                  return AbsorbPointer(
                    absorbing: _busy,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                        if (_busy) const LinearProgressIndicator(color: SaluteColors.primaryGreen),
                        const _Title('Contraseña'),
                        _Tile(
                          icon: Icons.lock_outline,
                          title: hasPassword ? 'Cambiar contraseña' : 'Crear contraseña',
                          subtitle: hasPassword
                              ? 'Actualizá la contraseña de tu cuenta'
                              : 'Tu cuenta entra solo con Google. Creá una para tener otra forma de acceso.',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ChangePasswordScreen(hasPassword: hasPassword)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Tile(
                          icon: Icons.mark_email_unread_outlined,
                          title: 'Recuperar contraseña por correo',
                          subtitle: email.isEmpty ? 'Sin correo asociado' : 'Te enviamos un enlace a $email',
                          onTap: _sendReset,
                        ),
                        const SizedBox(height: 26),
                        const _Title('Cuentas vinculadas'),
                        _Tile(
                          icon: Icons.mail_outline,
                          title: 'Email y contraseña',
                          subtitle: hasPassword ? 'Vinculado · $email' : 'No configurado',
                        ),
                        const SizedBox(height: 10),
                        _Tile(
                          icon: Icons.g_mobiledata_rounded,
                          title: 'Google',
                          subtitle: hasGoogle ? 'Vinculado' : 'No vinculado',
                          trailingLabel: hasGoogle ? 'Desvincular' : 'Vincular',
                          onTap: hasGoogle
                              ? _confirmUnlink
                              : () => _run(_auth.linkGoogle, ok: 'Cuenta de Google vinculada.'),
                        ),
                        const SizedBox(height: 26),
                        const _Title('Legal'),
                        _Tile(
                          icon: Icons.description_outlined,
                          title: 'Términos y Privacidad',
                          subtitle: 'Cómo cuidamos tus datos de salud',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TermsScreen()),
                          ),
                        ),
                        const SizedBox(height: 26),
                        const _Title('Zona de peligro', color: _danger),
                        _Tile(
                          icon: Icons.delete_forever_outlined,
                          title: 'Eliminar mi cuenta',
                          subtitle: 'Borra tu cuenta y todos tus datos. No se puede deshacer.',
                          color: _danger,
                          onTap: _deleteAccount,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cambiar / crear contraseña (diseño "Crear nueva contraseña")
// ─────────────────────────────────────────────────────────────────────────────

class ChangePasswordScreen extends StatefulWidget {
  /// `false` = la cuenta no tiene contraseña todavía (entró con Google).
  final bool hasPassword;
  const ChangePasswordScreen({super.key, required this.hasPassword});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _new.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _okLength => PasswordPolicy.hasMinLength(_new.text);
  bool get _okUpper => PasswordPolicy.hasUppercase(_new.text);
  bool get _okNumber => PasswordPolicy.hasNumber(_new.text);

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!PasswordPolicy.isValid(_new.text)) {
      messenger.showSnackBar(const SnackBar(content: Text('La contraseña no cumple los requisitos.')));
      return;
    }
    if (_new.text != _confirm.text) {
      messenger.showSnackBar(const SnackBar(content: Text('Las contraseñas no coinciden.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthService.instance.changePassword(
        currentPassword: widget.hasPassword ? _current.text : null,
        newPassword: _new.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Contraseña actualizada.')));
      Navigator.of(context).pop();
    } catch (e, st) {
      final text = userMessageFor(
        e,
        st,
        window: 'Cambiar contraseña',
        fallback: 'No pudimos cambiar la contraseña. Intentá de nuevo.',
      );
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.hasPassword ? 'Cambiar contraseña' : 'Crear contraseña';
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'SALUTE', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  children: [
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: SaluteColors.primaryGreen)),
                    const SizedBox(height: 10),
                    Text(
                      'Protegé tu cuenta con una contraseña fuerte y segura.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.hasPassword) ...[
                            const _FieldLabel('CONTRASEÑA ACTUAL'),
                            _PasswordField(controller: _current, obscure: _obscure, onToggle: () => setState(() => _obscure = !_obscure)),
                            const SizedBox(height: 18),
                          ],
                          const _FieldLabel('NUEVA CONTRASEÑA'),
                          _PasswordField(controller: _new, obscure: _obscure, onToggle: () => setState(() => _obscure = !_obscure)),
                          const SizedBox(height: 18),
                          const _FieldLabel('CONFIRMAR CONTRASEÑA'),
                          _PasswordField(controller: _confirm, obscure: _obscure, onToggle: () => setState(() => _obscure = !_obscure)),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('REQUISITOS DE SEGURIDAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 10),
                                _Req('Al menos ${PasswordPolicy.minLength} caracteres', _okLength),
                                _Req('Una letra mayúscula', _okUpper),
                                _Req('Al menos un número', _okNumber),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: SaluteColors.primaryGreen,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _saving
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                  : Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ),
                          ),
                        ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de eliminación
// ─────────────────────────────────────────────────────────────────────────────

class _DeleteAccountDialog extends StatefulWidget {
  final bool hasPassword;
  const _DeleteAccountDialog({required this.hasPassword});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmText = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _confirmText.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmText.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      _confirmText.text.trim().toUpperCase() == 'ELIMINAR' && (!widget.hasPassword || _password.text.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Eliminar cuenta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrarán tu cuenta y todos los perfiles, historial, medicación, agenda, '
                  'signos vitales, diario y botiquín que administrás, además de los archivos '
                  'guardados en este dispositivo. No se puede deshacer.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (widget.hasPassword) ...[
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Tu contraseña'),
              ),
              const SizedBox(height: 12),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Te vamos a pedir que confirmes con Google.', style: TextStyle(fontSize: 13)),
              ),
            TextField(
              controller: _confirmText,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Escribí ELIMINAR para confirmar'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: _ready ? () => Navigator.pop(context, _password.text) : null,
          style: TextButton.styleFrom(foregroundColor: _danger),
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets chicos
// ─────────────────────────────────────────────────────────────────────────────

class _Title extends StatelessWidget {
  final String text;
  final Color color;
  const _Title(this.text, {this.color = SaluteColors.primaryGreen});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 12),
    child: Semantics(
      header: true,
      child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
    ),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final String? trailingLabel;
  final VoidCallback? onTap;
  final Color color;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailingLabel,
    this.onTap,
    this.color = SaluteColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color == _danger ? _danger : Colors.black87)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (trailingLabel != null)
                Text(trailingLabel!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen))
              else if (onTap != null)
                Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
  );
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF2F2F2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _Req extends StatelessWidget {
  final String text;
  final bool ok;
  const _Req(this.text, this.ok);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18, color: ok ? SaluteColors.primaryGreen : Colors.grey),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: ok ? SaluteColors.primaryGreen : Colors.grey[700])),
      ],
    ),
  );
}

/// Ejecuta el borrado (sin depender de ninguna pantalla). Si falla, vuelve a
/// la app y lo explica en un diálogo; si sale bien, AuthGate cae en el login.
Future<void> _runAccountDeletion() async {
  final auth = AuthService.instance;
  try {
    await auth.deleteAccountNow();
    auth.deletingAccount.value = false;
  } catch (e, st) {
    final text = userMessageFor(
      e,
      st,
      window: 'Eliminar cuenta',
      fallback: 'No pudimos eliminar tu cuenta. Intentá de nuevo en unos minutos.',
    );
    auth.deletingAccount.value = false;
    final ctx = appNavigatorKey.currentState?.overlay?.context;
    if (ctx != null && ctx.mounted) {
      await showDialog<void>(
        context: ctx,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: _danger, size: 32),
          title: const Text('No se pudo eliminar la cuenta', textAlign: TextAlign.center),
          content: Text(text, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Entendido'))],
        ),
      );
    }
  }
}
