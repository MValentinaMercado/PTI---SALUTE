import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/auth/auth_error_handler.dart';
import 'package:saluteapp/components/inline_error.dart';

/// Pantalla intermedia para recuperar la contraseña: el usuario escribe su
/// email (viene precargado si ya lo había tipeado en el login) y le
/// mandamos el enlace de restablecimiento.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  bool _loading = false;
  bool _sent = false;
  String? _error; // debajo del campo email
  String? _generalError; // aviso arriba del botón

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Ingresá un email válido.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _generalError = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) setState(() => _sent = true);
    } catch (e, st) {
      final r = handleAuthError(e, st, window: 'Recuperar contraseña');
      if (mounted) {
        setState(() {
          _error = r.email;
          _generalError = r.general ?? r.password;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'Recuperar contraseña', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: _sent ? _buildSent() : _buildForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildForm() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Te enviaremos un enlace a tu email para que puedas crear una contraseña nueva.',
            style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 22),
          const Text(
            'EMAIL',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SaluteColors.primaryGreen,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_error != null || _generalError != null) setState(() => _error = _generalError = null);
            },
            onSubmitted: (_) => _send(),
            style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'tu@email.com',
              hintStyle: TextStyle(color: SaluteColors.textMuted, fontSize: 15),
              errorText: _error,
              errorMaxLines: 3,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: SaluteColors.primaryGreen, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          InlineErrorBanner(message: _generalError, onDismiss: () => setState(() => _generalError = null)),
          ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: FilledButton(
              onPressed: _loading ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: SaluteColors.primaryGreen,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                  : const Text(
                      'Enviar enlace',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return _card(
      child: Column(
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 56, color: SaluteColors.primaryGreen),
          const SizedBox(height: 16),
          const Text(
            '¡Revisá tu correo!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: SaluteColors.primaryGreen),
          ),
          const SizedBox(height: 10),
          Text(
            'Si ${_emailController.text.trim()} tiene una cuenta, te enviamos un enlace para restablecer tu contraseña. '
            'Si no lo ves, revisá la carpeta de spam.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 22),
          ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 52), child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: SaluteColors.primaryGreen,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Volver a iniciar sesión',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _sent = false),
            child: const Text('Usar otro email', style: TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
