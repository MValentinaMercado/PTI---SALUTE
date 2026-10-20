import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/insurance_picker.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/biometric_service.dart';
import 'package:saluteapp/core/secure_credentials_service.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/privacy_security_screen.dart';
import 'package:saluteapp/core/services/app_settings_service.dart';
import 'package:saluteapp/core/services/local_alarm_service.dart';
import 'package:saluteapp/core/sharing_settings_screen.dart';
import 'package:saluteapp/legal/terms_screen.dart';
import 'package:saluteapp/onboarding/onboarding_tour_screen.dart';
import 'package:saluteapp/profile/accessibility_screen.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/profile/profile_form_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onBackToDashboard;

  const SettingsScreen({super.key, this.onBackToDashboard});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  // Notificaciones y ubicación viven en AppSettingsService (persistidas y
  // respetadas por el resto de la app), no en variables locales.
  final _settings = AppSettingsService.instance;

  /// Estado REAL del permiso del sistema (distinto de la preferencia de la app).
  bool _systemLocationGranted = true;
  bool _systemNotificationsAllowed = true;

  static const String _diarioLockFeature = 'diario_lock';

  bool _diarioLockSupported = false;
  bool _diarioLockEnabled = false;
  bool _diarioLockLoading = true;

  // Login rápido: entrar sin tipear email/contraseña, usando huella +
  // las credenciales guardadas en SecureCredentialsService. A diferencia
  // del candado del Diario, esto no es un feature flag por uid: el hecho
  // de tener credenciales guardadas ES que está activado.
  bool _quickLoginSupported = false;
  bool _quickLoginEnabled = false;
  bool _quickLoginLoading = true;

  bool _signingOut = false;

  // Perfil propio (isSelf), en vivo: de acá sale la obra social que se
  // muestra en la fila "Obra social" y sobre la que guarda el selector.
  StreamSubscription<FamilyProfile?>? _selfSub;
  FamilyProfile? _selfProfile;
  bool _selfLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_onSettingsChanged);
    _refreshSystemPermissions();
    _loadDiarioLockState();
    _loadQuickLoginState();
    _listenSelfProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettingsChanged);
    _selfSub?.cancel();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  // Al volver de los ajustes del teléfono se relee el permiso real.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSystemPermissions();
  }

  Future<void> _refreshSystemPermissions() async {
    bool loc = true;
    try {
      final p = await Geolocator.checkPermission();
      loc = p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (_) {}
    final notif = await LocalAlarmService.instance.notificationsAllowed();
    if (!mounted) return;
    setState(() {
      _systemLocationGranted = loc;
      _systemNotificationsAllowed = notif;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    await _settings.setNotificationsEnabled(value);
    if (value) {
      // La app lo permite: si el sistema las bloqueó, se pide / se explica.
      var allowed = await LocalAlarmService.instance.requestNotificationsPermission();
      if (!mounted) return;
      setState(() => _systemNotificationsAllowed = allowed);
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Las notificaciones están bloqueadas en los ajustes del teléfono.'),
            action: SnackBarAction(label: 'Abrir ajustes', onPressed: Geolocator.openAppSettings),
          ),
        );
      }
    }
  }

  Future<void> _toggleLocation(bool value) async {
    await _settings.setLocationEnabled(value);
    if (!value) return;
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      final granted = p == LocationPermission.whileInUse || p == LocationPermission.always;
      if (!mounted) return;
      setState(() => _systemLocationGranted = granted);
    } catch (_) {}
  }

  void _listenSelfProfile() {
    try {
      _selfSub = ProfileService.instance.watchSelfProfile().listen(
            (profile) {
          if (!mounted) return;
          setState(() {
            _selfProfile = profile;
            _selfLoading = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _selfLoading = false);
        },
      );
    } catch (_) {
      // Sin usuario logueado (ej. sesión recién cerrada): la fila queda
      // como "No disponible" en vez de romper la pantalla.
      _selfLoading = false;
    }
  }

  String get _insuranceSubtitle {
    if (_selfLoading) return 'Cargando…';
    final self = _selfProfile;
    if (self == null) return 'No disponible';
    return self.insurance.isNotEmpty ? self.insurance : 'Sin seleccionar';
  }

  Future<void> _editInsurance() async {
    final self = _selfProfile;
    if (self == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos encontrar tu perfil.')),
      );
      return;
    }
    final picked = await showInsurancePicker(context, current: self.insurance);
    if (picked == null || !mounted) return; // canceló
    if (picked == self.insurance) return; // no cambió nada
    try {
      await ProfileService.instance.setInsurance(self.id, picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(picked.isEmpty ? 'Obra social quitada.' : 'Obra social guardada: $picked')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la obra social. Intentá de nuevo.')),
      );
    }
  }

  Future<void> _loadDiarioLockState() async {
    final uid = AuthService.instance.currentUser?.uid;
    final supported = await BiometricService.instance.isDeviceSupported();
    final enabled = uid == null
        ? false
        : await BiometricService.instance.isEnabledFor(_diarioLockFeature, uid);
    if (!mounted) return;
    setState(() {
      _diarioLockSupported = supported;
      _diarioLockEnabled = enabled;
      _diarioLockLoading = false;
    });
  }

  Future<void> _onDiarioLockChanged(bool value) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;

    if (value) {
      // Antes de activarlo, confirmamos que la huella cargada en el
      // equipo funciona; si el usuario cancela o falla, no lo activamos.
      final ok = await BiometricService.instance.authenticate(
        reason: 'Confirmá tu huella para proteger el Diario',
      );
      if (!ok) return;
    }

    await BiometricService.instance.setEnabledFor(_diarioLockFeature, uid, value);
    if (!mounted) return;
    setState(() => _diarioLockEnabled = value);
  }

  Future<void> _loadQuickLoginState() async {
    final uid = AuthService.instance.currentUser?.uid;
    final supported = await BiometricService.instance.isDeviceSupported();
    final hasSaved = uid == null
        ? false
        : await SecureCredentialsService.instance.hasSavedCredentialsFor(uid);
    if (!mounted) return;
    setState(() {
      _quickLoginSupported = supported;
      _quickLoginEnabled = hasSaved;
      _quickLoginLoading = false;
    });
  }

  Future<void> _onQuickLoginChanged(bool value) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;

    if (!value) {
      // Solo borramos si lo guardado en el equipo es efectivamente de
      // ESTA cuenta; si perteneciera a otra (ver hasSavedCredentialsFor),
      // no la tocamos.
      await SecureCredentialsService.instance.clear();
      if (!mounted) return;
      setState(() => _quickLoginEnabled = false);
      return;
    }

    final email = AuthService.instance.currentUser?.email;
    if (email == null) return;

    final hasPassword = AuthService.instance.hasPasswordProvider;

    // Si la cuenta ya tiene contraseña (email/contraseña) se la pedimos
    // para confirmarla. Si entró con Google y todavía no tiene una, en
    // realidad se la estamos pidiendo para CREARLA (Google nunca le dio
    // una a Firebase), así que el diálogo avisa eso.
    final password = await _askPassword(email, creating: !hasPassword);
    if (password == null || password.isEmpty) return;

    try {
      await AuthService.instance.verifyOrSetPasswordForQuickLogin(
        email: email,
        password: password,
      );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo verificar la contraseña.')),
      );
      return;
    }

    final ok = await BiometricService.instance.authenticate(
      reason: 'Confirmá tu huella para activar el login rápido',
    );
    if (!ok) return;

    await SecureCredentialsService.instance.save(uid: uid, email: email, password: password);
    if (!mounted) return;
    setState(() => _quickLoginEnabled = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login rápido activado.')),
    );
  }

  Future<String?> _askPassword(String email, {bool creating = false}) {
    final controller = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(creating ? 'Creá una contraseña' : 'Confirmá tu contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                creating
                    ? 'Tu cuenta entró con Google y todavía no tiene contraseña propia. '
                    'Creá una para $email: la vas a poder usar también para entrar '
                    'sin Google, y para el login rápido con huella.'
                    : 'Para activar el login rápido con huella, ingresá la contraseña de $email.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Contraseña',
                  suffixIcon: IconButton(
                    tooltip: 'Mostrar u ocultar contraseña',
                    icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Antes hacíamos el pop primero y el signOut después: eso dejaba al
  /// usuario viendo la pestaña Perfil (lo que había atrás en el Shell)
  /// durante los segundos que tarda el signOut de Firebase/Google, antes
  /// de que AuthGate reaccionara y mostrara LoginPage. Invertimos el
  /// orden: esperamos el signOut acá (con el botón en loading) y recién
  /// ahí hacemos pop, así cuando se revela lo que hay debajo ya es
  /// LoginPage directamente, sin pasar por Perfil.
  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthService.instance.signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
    if (!mounted) return;
    // Sin esto, si esta pantalla se abrió con Navigator.push (como pasa
    // desde "Mi familia" o desde una ficha de perfil), queda apilada por
    // encima de AuthGate y tapa el LoginPage aunque la sesión ya se haya
    // cerrado.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openMyProfile() async {
    final profiles = await ProfileService.instance.watchProfiles().first;
    // `isSelf` solo no alcanza: hay uno por integrante de la familia.
    final self = ProfileService.selfOf(profiles, AuthService.instance.currentUser?.uid);
    if (!mounted) return;
    if (self == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos encontrar tu perfil.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileFormScreen(existingProfile: self)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Configuración',
              onBack: onBackToDashboard,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Preferencias'),
                    const SizedBox(height: 16),
                    _buildToggleSetting(
                      title: 'Notificaciones',
                      subtitle: 'Recibe alertas de salud',
                      value: _settings.notificationsEnabled,
                      onChanged: _toggleNotifications,
                    ),
                    if (_settings.notificationsEnabled && !_systemNotificationsAllowed) ...[
                      const SizedBox(height: 8),
                      _buildSettingTile(
                        icon: Icons.notifications_off_outlined,
                        title: 'Bloqueadas en el teléfono',
                        subtitle: 'Tocá para permitirlas en los ajustes',
                        onTap: Geolocator.openAppSettings,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildToggleSetting(
                      title: 'Servicios de Ubicación',
                      subtitle: 'Permitir acceso a ubicación',
                      value: _settings.locationEnabled,
                      onChanged: _toggleLocation,
                    ),
                    if (_settings.locationEnabled && !_systemLocationGranted) ...[
                      const SizedBox(height: 8),
                      _buildSettingTile(
                        icon: Icons.location_off_outlined,
                        title: 'Permiso denegado en el teléfono',
                        subtitle: 'Tocá para permitirlo en los ajustes',
                        onTap: Geolocator.openAppSettings,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildToggleSetting(
                      title: 'SOS fijo en el Inicio',
                      subtitle: 'El botón SOS queda solo en el Inicio y no aparece en las demás pantallas',
                      value: _settings.sosPinnedToDashboard,
                      onChanged: _settings.setSosPinnedToDashboard,
                    ),
                    const SizedBox(height: 12),
                    _buildSettingTile(
                      icon: Icons.accessibility_new_outlined,
                      title: 'Accesibilidad',
                      subtitle: 'Tamaño de texto, contraste y voz',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AccessibilityScreen()),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildSectionTitle('Cuenta'),
                    const SizedBox(height: 16),
                    if (!_diarioLockLoading && _diarioLockSupported) ...[
                      _buildToggleSetting(
                        title: 'Proteger el Diario con huella',
                        subtitle: 'Pedir huella cada vez que entrás al Diario',
                        value: _diarioLockEnabled,
                        onChanged: _onDiarioLockChanged,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_quickLoginLoading && _quickLoginSupported) ...[
                      _buildToggleSetting(
                        title: 'Login rápido con huella',
                        subtitle: 'Entrar sin escribir tu email y contraseña',
                        value: _quickLoginEnabled,
                        onChanged: _onQuickLoginChanged,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildSettingTile(
                      icon: Icons.person_outline,
                      title: 'Perfil',
                      subtitle: 'Editar información personal',
                      onTap: _openMyProfile,
                    ),
                    const SizedBox(height: 12),
                    _buildSettingTile(
                      icon: Icons.local_hospital_outlined,
                      title: 'Obra social',
                      subtitle: _insuranceSubtitle,
                      onTap: _editInsurance,
                    ),
                    const SizedBox(height: 12),
                    _buildSettingTile(
                      icon: Icons.family_restroom_outlined,
                      title: 'Compartir perfiles',
                      subtitle: 'Elegí quién de tu familia ve cada perfil',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SharingSettingsScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSettingTile(
                      icon: Icons.security_outlined,
                      title: 'Privacidad y Seguridad',
                      subtitle: 'Contraseña, cuentas vinculadas y eliminar cuenta',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PrivacySecurityScreen()),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildSectionTitle('Información'),
                    const SizedBox(height: 16),
                    _buildSettingTile(
                      icon: Icons.explore_outlined,
                      title: 'Recorrido de bienvenida',
                      subtitle: 'Volver a ver la guía rápida de la app',
                      onTap: () => OnboardingTourScreen.open(context),
                    ),
                    const SizedBox(height: 12),
                    _buildSettingTile(
                      icon: Icons.info_outline,
                      title: 'Acerca de',
                      subtitle: 'Versión 1.0.0',
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'Salute',
                        applicationVersion: '1.0.0',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSettingTile(
                      icon: Icons.description_outlined,
                      title: 'Términos y Condiciones',
                      subtitle: 'Privacidad y política de uso',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TermsScreen()),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 54), child: ElevatedButton.icon(
                        onPressed: _signingOut ? null : _signOut,
                        icon: _signingOut
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                            : const Icon(Icons.logout),
                        label: Text(_signingOut ? 'Cerrando sesión...' : 'Cerrar Sesión'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SaluteColors.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: SaluteColors.primaryGreen,
      ),
    );
  }

  Widget _buildToggleSetting({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return MergeSemantics(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: SaluteColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: SaluteColors.primaryGreen,
          ),
        ],
      ),
    ));
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SaluteColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: SaluteColors.primaryGreen, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: SaluteColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: SaluteColors.textMuted, size: 24),
          ],
        ),
      ),
    );
  }

  void onBackToDashboard() {
    Navigator.of(context).pop();
  }
}