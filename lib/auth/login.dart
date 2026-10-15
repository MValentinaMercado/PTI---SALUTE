import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/biometric_service.dart';
import 'package:saluteapp/core/secure_credentials_service.dart';
import 'package:saluteapp/auth/social_auth_widgets.dart';
import 'package:saluteapp/auth/signin.dart';
import 'package:saluteapp/auth/forgot_password_screen.dart';
import 'package:saluteapp/auth/auth_error_handler.dart';
import 'package:saluteapp/components/inline_error.dart';

/// Pantalla de inicio de sesión. Se muestra desde [AuthGate] cuando no hay
/// sesión activa (ver main.dart).
///
/// Permite entrar con email/contraseña, con Google, o -si el usuario activó
/// el login rápido antes- con huella/Face ID usando las credenciales
/// guardadas en [SecureCredentialsService].
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  // Errores, cada uno en el lugar que corresponde.
  String? _emailError; // debajo del campo email
  String? _passwordError; // debajo del campo contraseña
  String? _error; // aviso arriba del botón "Ingresar" (credenciales, huella)
  String? _googleError; // aviso debajo del botón de Google

  bool _quickLoginAvailable = false;
  bool _checkingQuickLogin = true;

  @override
  void initState() {
    super.initState();
    _checkQuickLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkQuickLogin() async {
    final hasSaved = await SecureCredentialsService.instance.hasAnySavedCredentials();
    final supported = hasSaved ? await BiometricService.instance.isDeviceSupported() : false;
    if (!mounted) return;
    setState(() {
      _quickLoginAvailable = hasSaved && supported;
      _checkingQuickLogin = false;
    });
  }

  void _clearErrors() {
    _emailError = null;
    _passwordError = null;
    _error = null;
    _googleError = null;
  }

  /// Aplica el resultado de [handleAuthError]. [google] decide si el aviso
  /// general va debajo del botón de Google o arriba de "Ingresar".
  void _applyError(Object e, StackTrace st, {bool google = false}) {
    final r = handleAuthError(e, st, window: 'Iniciar sesión');
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

  Future<void> _quickLogin() async {
    if (_loading) return;
    setState(() {
      _clearErrors();
      _loading = true;
    });
    try {
      final ok = await BiometricService.instance.authenticate(
        reason: 'Confirmá tu huella para iniciar sesión',
      );
      if (!ok) {
        if (mounted) setState(() => _error = 'No pudimos verificar tu huella. Probá de nuevo.');
        return;
      }
      final creds = await SecureCredentialsService.instance.read();
      if (creds == null) {
        if (mounted) {
          setState(() {
            _error = 'No hay una sesión guardada en este equipo. Ingresá con tu email y contraseña.';
            _quickLoginAvailable = false;
          });
        }
        return;
      }
      await AuthService.instance.signIn(email: creds.email, password: creds.password);
      // El StreamBuilder de AuthGate en main.dart detecta la sesión y navega solo.
    } catch (e, st) {
      _applyError(e, st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Validación local: cada mensaje aparece debajo de su campo.
    final emailError = email.isEmpty ? 'Ingresá tu email.' : null;
    final passwordError = password.isEmpty ? 'Ingresá tu contraseña.' : null;
    if (emailError != null || passwordError != null) {
      setState(() {
        _clearErrors();
        _emailError = emailError;
        _passwordError = passwordError;
      });
      return;
    }

    setState(() {
      _clearErrors();
      _loading = true;
    });
    try {
      await AuthService.instance.signIn(email: email, password: password);
      // El StreamBuilder de AuthGate en main.dart detecta la sesión nueva y navega solo.
    } catch (e, st) {
      _applyError(e, st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_loading) return;
    setState(() {
      _clearErrors();
      _loading = true;
    });
    try {
      await AuthService.instance.signInWithGoogle(isRegister: false);
      // El StreamBuilder de AuthGate en main.dart detecta la sesión y navega solo.
    } catch (e, st) {
      _applyError(e, st, google: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Abre la pantalla de recuperación con el email que ya se haya escrito.
  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
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
              const SizedBox(height: 36),
              _buildLogo(),
              const SizedBox(height: 28),
              _buildHeadline(),
              const SizedBox(height: 28),
              _buildFormCard(),
              const SizedBox(height: 24),
              _buildRegisterLink(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Salute',
        style: TextStyle(
          color: SaluteColors.primaryGreen,
          fontSize: DsFontSize.h4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildHeadline() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Iniciar sesión',
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
          const _FieldLabel('EMAIL'),
          const SizedBox(height: 10),
          _textField(
            _emailController,
            hint: 'tu@email.com',
            keyboardType: TextInputType.emailAddress,
            errorText: _emailError,
            onChanged: () => setState(() {
              _emailError = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('CONTRASEÑA'),
          const SizedBox(height: 10),
          _textField(
            _passwordController,
            hint: '••••••••',
            obscure: _obscurePassword,
            errorText: _passwordError,
            onChanged: () => setState(() {
              _passwordError = null;
              _error = null;
            }),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.grey[500],
                size: 22,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _forgotPassword,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
              child: const Text(
                '¿Olvidaste tu contraseña?',
                style: TextStyle(color: SaluteColors.primaryGreen, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
          InlineErrorBanner(message: _error, onDismiss: () => setState(() => _error = null)),
          _buildLoginButton(),
          if (!_checkingQuickLogin && _quickLoginAvailable) ...[
            const SizedBox(height: 14),
            _buildQuickLoginButton(),
          ],
          const SizedBox(height: 26),
          const AuthDivider(label: 'O INGRESA CON'),
          const SizedBox(height: 22),
          GoogleAuthButton(onTap: _loginWithGoogle, loading: _loading),
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

  Widget _buildLoginButton() {
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
          onPressed: _loading ? null : _login,
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
            'Ingresar',
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

  Widget _buildQuickLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _quickLogin,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: SaluteColors.primaryGreen, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.fingerprint, color: SaluteColors.primaryGreen),
        label: const Text(
          'Ingresar con huella',
          style: TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildRegisterLink() {
    return Center(
      child: TextButton(
        onPressed: _loading ? null : _goToRegister,
        child: RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: '¿No tenés cuenta? ',
                style: TextStyle(color: Colors.black54, fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
              TextSpan(
                text: 'Registrate ahora',
                style: TextStyle(color: SaluteColors.primaryGreen, fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
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