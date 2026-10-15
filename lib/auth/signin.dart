import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/password_policy.dart';
import 'package:saluteapp/auth/social_auth_widgets.dart';
import 'package:saluteapp/auth/auth_error_handler.dart';
import 'package:saluteapp/components/inline_error.dart';
import 'package:saluteapp/legal/legal_content.dart';
import 'package:saluteapp/legal/terms_screen.dart';

/// Pantalla de registro (alta de cuenta). Se abre desde
/// "¿No tenés cuenta? Registrarse ahora" en LoginScreen.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _acceptedTerms = false;

  // Errores, cada uno en el lugar que corresponde.
  String? _nameError;
  String? _lastNameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _termsError; // debajo del checkbox de términos
  String? _error; // aviso arriba del botón "Crear cuenta"
  String? _googleError; // aviso debajo del botón de Google

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _nameError = null;
    _lastNameError = null;
    _emailError = null;
    _passwordError = null;
    _confirmError = null;
    _termsError = null;
    _error = null;
    _googleError = null;
  }

  /// Abre los Términos con el botón "Aceptar". Devuelve true si el usuario
  /// los aceptó (y deja el checkbox tildado).
  Future<bool> _openTerms() async {
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TermsScreen(showAcceptButton: true)),
    );
    if (accepted == true && mounted) {
      setState(() {
        _acceptedTerms = true;
        _termsError = null;
      });
      return true;
    }
    return false;
  }

  /// Aplica el resultado de [handleAuthError] en el lugar que corresponde.
  void _applyError(Object e, StackTrace st, {bool google = false}) {
    final r = handleAuthError(e, st, window: 'Registro');
    if (!mounted) return;
    setState(() {
      _emailError = r.email;
      _passwordError = r.password;
      if (google) {
        _googleError = r.general;
      } else {
        _error = r.general;
      }
    });
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    // Validación local: cada mensaje aparece debajo de su campo.
    final nameError = name.isEmpty ? 'Ingresá tu nombre.' : null;
    final lastNameError = lastName.isEmpty ? 'Ingresá tu apellido.' : null;
    final emailError = email.isEmpty
        ? 'Ingresá tu email.'
        : (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ? 'El email no tiene un formato válido.' : null);
    final passwordError = password.isEmpty ? 'Ingresá una contraseña.' : PasswordPolicy.validate(password);
    final confirmError = (password.isNotEmpty && confirm != password) ? 'Las contraseñas no coinciden.' : null;
    final termsError = _acceptedTerms ? null : 'Para registrarte tenés que aceptar los Términos y el Aviso de Privacidad.';

    if ([nameError, lastNameError, emailError, passwordError, confirmError, termsError].any((e) => e != null)) {
      setState(() {
        _clearErrors();
        _nameError = nameError;
        _lastNameError = lastNameError;
        _emailError = emailError;
        _passwordError = passwordError;
        _confirmError = confirmError;
        _termsError = termsError;
      });
      return;
    }

    setState(() {
      _clearErrors();
      _loading = true;
    });
    try {
      await AuthService.instance.register(
        name: name,
        lastName: lastName,
        email: email,
        password: password,
        termsVersion: kTermsVersion,
      );
      if (!mounted) return;
      // El StreamBuilder en main.dart detecta la sesión nueva
      // y navega solo al Shell principal.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, st) {
      _applyError(e, st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Registro con Google. Si todavía no aceptó los términos, se lo lleva a
  /// la pantalla de Términos ANTES de abrir el selector de cuentas: así la
  /// cuenta nunca se crea sin aceptación. Al aceptar, sigue solo con Google.
  Future<void> _registerWithGoogle() async {
    if (_loading) return;
    setState(_clearErrors);
    if (!_acceptedTerms) {
      final accepted = await _openTerms();
      // Volvió sin aceptar: no es un error, simplemente no continúa.
      if (!accepted || !mounted) return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithGoogle(isRegister: true, termsVersion: kTermsVersion);
      if (!mounted) return;
      // El StreamBuilder en main.dart detecta la sesión nueva
      // y navega solo al Shell principal.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, st) {
      _applyError(e, st, google: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(context),
              const SizedBox(height: 24),
              _buildHeadline(),
              const SizedBox(height: 28),
              _buildFormCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
          ),
          const Text(
            'Salute',
            style: TextStyle(
              color: SaluteColors.primaryGreen,
              fontSize: DsFontSize.h4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadline() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Crear cuenta',
        style: TextStyle(
          color: SaluteColors.primaryGreen,
          fontSize: DsFontSize.display,
          fontWeight: FontWeight.w900,
          height: 1.1,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('NOMBRE'),
          const SizedBox(height: 10),
          _textField(_nameController, hint: 'Tu nombre', errorText: _nameError, onChanged: () => setState(() => _nameError = null)),
          const SizedBox(height: 20),
          const _FieldLabel('APELLIDO'),
          const SizedBox(height: 10),
          _textField(_lastNameController, hint: 'Tu apellido', errorText: _lastNameError, onChanged: () => setState(() => _lastNameError = null)),
          const SizedBox(height: 20),
          const _FieldLabel('EMAIL'),
          const SizedBox(height: 10),
          _textField(
            _emailController,
            hint: 'tu@email.com',
            keyboardType: TextInputType.emailAddress,
            errorText: _emailError,
            onChanged: () => setState(() => _emailError = null),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('CONTRASEÑA'),
          const SizedBox(height: 10),
          _textField(
            _passwordController,
            hint: '••••••••',
            obscure: _obscurePassword,
            errorText: _passwordError,
            onChanged: () => setState(() => _passwordError = null),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.grey[500],
                size: 22,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 8),
          Text(PasswordPolicy.hint, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 20),
          const _FieldLabel('CONFIRMAR CONTRASEÑA'),
          const SizedBox(height: 10),
          _textField(
            _confirmController,
            hint: '••••••••',
            obscure: _obscurePassword,
            errorText: _confirmError,
            onChanged: () => setState(() => _confirmError = null),
          ),
          const SizedBox(height: 22),
          _buildTermsCheck(),
          const SizedBox(height: 22),
          InlineErrorBanner(message: _error, onDismiss: () => setState(() => _error = null)),
          _buildRegisterButton(),
          const SizedBox(height: 26),
          const AuthDivider(label: 'O REGISTRATE CON'),
          const SizedBox(height: 22),
          GoogleAuthButton(onTap: _registerWithGoogle, loading: _loading),
          if (_googleError != null) const SizedBox(height: 16),
          InlineErrorBanner(
            message: _googleError,
            margin: EdgeInsets.zero,
            onDismiss: () => setState(() => _googleError = null),
          ),
        ],
      ),
    );
  }

  Widget _textField(
      TextEditingController controller, {
        required String hint,
        bool obscure = false,
        TextInputType? keyboardType,
        Widget? suffixIcon,
        String? errorText,
        VoidCallback? onChanged,
      }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
        errorText: errorText,
        errorMaxLines: 3,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SaluteColors.primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD64535), width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD64535), width: 2),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildTermsCheck() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acceptedTerms,
              activeColor: SaluteColors.primaryGreen,
              onChanged: _loading
                  ? null
                  : (v) => setState(() {
                        _acceptedTerms = v ?? false;
                        if (_acceptedTerms) _termsError = null;
                      }),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Leí y acepto los Términos de Servicio y el Aviso de Privacidad.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ],
        ),
        if (_termsError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
            child: Text(
              _termsError!,
              style: const TextStyle(fontSize: 12.5, height: 1.3, color: Color(0xFFD64535), fontWeight: FontWeight.w600),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: TextButton(
            onPressed: _loading ? null : _openTerms,
            style: TextButton.styleFrom(foregroundColor: SaluteColors.primaryGreen, padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: const Text('Leer documento completo', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: SaluteColors.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: _loading ? null : _register,
          style: FilledButton.styleFrom(
            backgroundColor: SaluteColors.primaryGreen,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _loading
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
              : const Text(
            'Crear cuenta',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
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
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: SaluteColors.primaryGreen,
        letterSpacing: 1,
      ),
    );
  }
}