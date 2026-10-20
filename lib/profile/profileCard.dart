import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/profile_avatar.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/settingsScreen.dart';
import 'package:saluteapp/core/models/vital_entry.dart';
import 'package:saluteapp/personal/metricas.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTES DE ESTILO
// ─────────────────────────────────────────────────────────────────────────────

const double _borderRadius = 22.0;
const double _smallBorderRadius = 16.0;
const EdgeInsets _cardPadding = EdgeInsets.all(18);
const EdgeInsets _screenPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);
const Color _alertRed = Color(0xFFB03A3A);

List<BoxShadow> _softShadow([double alpha = 0.05]) => [
      BoxShadow(
        color: Colors.black.withValues(alpha: alpha),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];

class FamilyProfileData {
  final String name;
  final String relation;
  final String age;
  final String avatarUrl;
  final String bloodType;
  final String allergies;
  final String lastCheckup;
  final String emergencyContact;

  /// Nombre y teléfono del contacto de emergencia (SOS) cuando hay uno
  /// configurado: con ellos la tarjeta de emergencia ofrece llamar.
  final String emergencyName;
  final String emergencyPhone;

  /// Obra social a mostrar. `null` = no aplica (ej. mascotas): no se muestra
  /// el casillero.
  final String? insurance;
  final String wellbeingLabel;
  final String wellbeingTitle;
  final String wellbeingValue;
  final VitalEntry? latestVital;

  /// `true` para mascotas: la tarjeta de bienestar pasa a ser la de peso
  /// (otro ícono y otra descripción de accesibilidad).
  final bool isPet;

  /// Etiquetas cortas que se muestran en la cabecera (ej. "Perro", "Labrador").
  final List<String> badges;
  final List<FamilyAlertData> alerts;
  final List<MedicationData> medications;

  const FamilyProfileData({
    required this.name,
    required this.relation,
    required this.age,
    required this.avatarUrl,
    required this.bloodType,
    required this.allergies,
    required this.lastCheckup,
    required this.emergencyContact,
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.insurance,
    required this.wellbeingLabel,
    required this.wellbeingTitle,
    required this.wellbeingValue,
    this.latestVital,
    this.isPet = false,
    this.badges = const [],
    required this.alerts,
    required this.medications,
  });

  /// Devuelve una copia con `alerts` y/o `medications` reemplazados.
  /// Se usa para "inyectar" los datos en vivo de Firestore (agenda,
  /// medicación) sobre el resto de los campos, que son estáticos.
  FamilyProfileData copyWith({
    List<FamilyAlertData>? alerts,
    List<MedicationData>? medications,
    String? wellbeingValue,
    String? emergencyContact,
    String? emergencyName,
    String? emergencyPhone,
    VitalEntry? latestVital,
  }) {
    return FamilyProfileData(
      name: name,
      relation: relation,
      age: age,
      avatarUrl: avatarUrl,
      bloodType: bloodType,
      allergies: allergies,
      lastCheckup: lastCheckup,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      emergencyName: emergencyName ?? this.emergencyName,
      emergencyPhone: emergencyPhone ?? this.emergencyPhone,
      insurance: insurance,
      wellbeingLabel: wellbeingLabel,
      wellbeingTitle: wellbeingTitle,
      wellbeingValue: wellbeingValue ?? this.wellbeingValue,
      latestVital: latestVital ?? this.latestVital,
      isPet: isPet,
      badges: badges,
      alerts: alerts ?? this.alerts,
      medications: medications ?? this.medications,
    );
  }
}

class FamilyAlertData {
  final String tag;
  final String title;
  final String subtitle;
  final Color bgColor;
  final IconData icon;

  const FamilyAlertData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.icon,
  });
}

class MedicationData {
  final String id;
  final String name;
  final String dose;
  final double progress;

  /// Tratamiento sin fecha de fin: en vez de la barra de progreso (que
  /// siempre estaría llena) se muestra una etiqueta "Crónico".
  final bool isChronic;

  const MedicationData({
    this.id = '',
    required this.name,
    required this.dose,
    required this.progress,
    this.isChronic = false,
  });
}

class FamiliarProfileScreen extends StatelessWidget {
  final VoidCallback? onBackToDashboard;
  final FamilyProfileData member;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onEditMedication;
  final VoidCallback? onOpenChecklist;

  /// Botón "Ficha médica" (ficha médica del perfil).
  final VoidCallback? onQuickRecord;

  /// Tarjeta "Bienestar Actual" (abre las métricas del perfil).
  final VoidCallback? onOpenWellbeing;

  /// Carné de vacunación (personas y mascotas). Si es null, no se muestra
  /// el acceso.
  final VoidCallback? onOpenVaccines;

  /// Si viene, la foto de la cabecera se puede tocar para cambiarla (sacar
  /// una foto o elegir de la galería). Null = solo lectura.
  final VoidCallback? onChangePhoto;

  /// Llamar al contacto de emergencia (abre el marcador). Null si no hay
  /// contacto SOS configurado.
  final VoidCallback? onCallEmergency;

  /// Elegir / cambiar el contacto de emergencia. Null si no corresponde
  /// editarlo desde acá.
  final VoidCallback? onEditEmergency;

  const FamiliarProfileScreen({
    super.key,
    required this.member,
    this.onBackToDashboard,
    this.onEdit,
    this.onEditMedication,
    this.onOpenChecklist,
    this.onQuickRecord,
    this.onOpenWellbeing,
    this.onOpenVaccines,
    this.onChangePhoto,
    this.onCallEmergency,
    this.onEditEmergency,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Perfil',
              onBack: onBackToDashboard,
              onSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(onBackToDashboard: () => Navigator.of(context).pop()),
                  ),
                );
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: _screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileHeaderCard(
                      member: member,
                      onEdit: onEdit,
                      onQuickRecord: onQuickRecord,
                      onChangePhoto: onChangePhoto,
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle(title: 'Resumen clínico', icon: Icons.monitor_heart_outlined),
                    const SizedBox(height: 14),
                    _ClinicalOverviewGrid(member: member),
                    if (!member.isPet) ...[
                      const SizedBox(height: 14),
                      _EmergencyCard(
                        name: member.emergencyName,
                        phone: member.emergencyPhone,
                        fallbackText: member.emergencyContact,
                        onCall: onCallEmergency,
                        onConfigure: onEditEmergency,
                      ),
                    ],
                    const SizedBox(height: 28),
                    member.isPet
                        ? _WellbeingCard(member: member, onTap: onOpenWellbeing)
                        : HealthStatusCard(
                            latest: member.latestVital,
                            onTap: onOpenWellbeing,
                          ),
                    const SizedBox(height: 14),
                    if (onOpenVaccines != null) ...[
                      _VaccineBanner(onTap: onOpenVaccines!),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 14),
                    const _SectionTitle(title: 'Alertas', icon: Icons.notifications_active_outlined),
                    const SizedBox(height: 12),
                    if (member.alerts.isEmpty)
                      _EmptySectionHint(text: 'No hay turnos ni alertas pendientes para ${member.name}.')
                    else
                      ...member.alerts.expand(
                        (alert) => [
                          _AlertCard(
                            tag: alert.tag,
                            title: alert.title,
                            subtitle: alert.subtitle,
                            bgColor: alert.bgColor,
                            icon: alert.icon,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    const SizedBox(height: 20),
                    const _SectionTitle(title: 'Medicación actual', icon: Icons.medication_outlined),
                    const SizedBox(height: 12),
                    if (member.medications.isNotEmpty && onOpenChecklist != null) ...[
                      _ChecklistBanner(onTap: onOpenChecklist!),
                      const SizedBox(height: 14),
                    ],
                    if (member.medications.isEmpty)
                      const _EmptySectionHint(text: 'Sin medicación activa registrada.')
                    else
                      ...member.medications.map(
                        (medication) => _MedicationItem(
                          name: medication.name,
                          dose: medication.dose,
                          progress: medication.progress,
                          isChronic: medication.isChronic,
                          onTap: onEditMedication != null && medication.id.isNotEmpty
                              ? () => onEditMedication!(medication.id)
                              : null,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION TITLE HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: SaluteColors.lightGreen.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: SaluteColors.primaryGreen),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE HEADER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  final FamilyProfileData member;
  final VoidCallback? onEdit;
  final VoidCallback? onQuickRecord;
  final VoidCallback? onChangePhoto;

  const _ProfileHeaderCard({
    required this.member,
    this.onEdit,
    this.onQuickRecord,
    this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [member.relation, member.age].where((e) => e.isNotEmpty).join(' • ');
    // Mascotas: terracota más claro que el del avatar; personas: verde.
    final gradientColors = member.isPet
        ? const [Color(0xFFC96F48), Color(0xFFA9532F)]
        : const [SaluteColors.primaryGreen, SaluteColors.darkGreen];
    final accent = gradientColors.first;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Marca de agua decorativa.
          Positioned(
            right: -22,
            top: -18,
            child: Icon(
              member.isPet ? Icons.pets : Icons.favorite,
              size: 150,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            // El Stack le da restricciones sueltas a sus hijos, así que sin
            // el ancho completo la Column se ajusta al contenido y queda
            // pegada a la izquierda en vez de centrada en la tarjeta.
            child: SizedBox(
              width: double.infinity,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ProfileAvatar(
                  avatarUrl: member.avatarUrl,
                  type: member.isPet ? ProfileType.mascota : ProfileType.persona,
                  name: member.name,
                  radius: 50,
                  ring: true,
                  showInitial: false,
                  onEditPhoto: onChangePhoto,
                ),
                const SizedBox(height: 16),
                Text(
                  member.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
                if (member.badges.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: member.badges.map((b) => _HeaderChip(label: b)).toList(),
                  ),
                ],
                const SizedBox(height: 18),
                // Wrap: si no entran los botones en la fila, el de editar baja
                // de línea en vez de desbordar el ancho de la tarjeta.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeaderButton(
                      icon: Icons.medical_information_outlined,
                      label: member.isPet ? 'Ficha veterinaria' : 'Ficha médica',
                      filled: true,
                      accent: accent,
                      onTap: onQuickRecord,
                      tooltip: 'Ver ficha médica',
                    ),
                    if (onEdit != null)
                      _HeaderButton(
                        icon: Icons.edit_outlined,
                        label: 'Editar',
                        filled: false,
                        onTap: onEdit,
                        tooltip: 'Editar perfil',
                      ),
                  ],
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  const _HeaderChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final Color accent;
  final VoidCallback? onTap;
  final String? tooltip;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.filled,
    this.accent = SaluteColors.primaryGreen,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? accent : Colors.white;
    final button = Material(
      color: filled ? Colors.white : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(_smallBorderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_smallBorderRadius),
        child: Container(
          // Alto mínimo de 46 px: área táctil accesible.
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_smallBorderRadius),
            border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLINICAL OVERVIEW GRID
// ─────────────────────────────────────────────────────────────────────────────

class _ClinicalOverviewGrid extends StatelessWidget {
  final FamilyProfileData member;

  const _ClinicalOverviewGrid({required this.member});

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;
    // El grupo sanguíneo es un dato de personas: en una mascota no aplica.
    // (El contacto de emergencia tiene su propia tarjeta.)
    final tiles = <_OverviewTile>[
      if (!member.isPet)
        _OverviewTile(
          icon: Icons.bloodtype_outlined,
          label: 'TIPO DE SANGRE',
          value: member.bloodType,
        ),
      _OverviewTile(
        icon: Icons.warning_amber_rounded,
        label: 'ALERGIAS',
        value: member.allergies,
        bgColor: _alertRed,
      ),
      _OverviewTile(
        icon: Icons.event_available_outlined,
        label: 'ÚLTIMO CHEQUEO',
        value: member.lastCheckup,
      ),
      if (member.insurance != null)
        _OverviewTile(
          icon: Icons.health_and_safety_outlined,
          label: 'OBRA SOCIAL',
          value: member.insurance!,
        ),
    ];

    // Wrap en vez de GridView con aspect ratio fijo: la altura de cada
    // tarjeta la define su contenido, así el texto no se corta en pantallas
    // chicas ni con el tamaño de fuente del sistema aumentado. Con una
    // cantidad impar de casilleros, el último ocupa todo el ancho para no
    // quedar suelto a la izquierda.
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < tiles.length; i++)
              SizedBox(
                width: (tiles.length.isOdd && i == tiles.length - 1) ? constraints.maxWidth : halfWidth,
                child: tiles[i],
              ),
          ],
        );
      },
    );
  }
}

class _OverviewTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? bgColor;
  const _OverviewTile({required this.icon, required this.label, required this.value, this.bgColor});

  @override
  Widget build(BuildContext context) {
    final onColor = bgColor != null;
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.white,
        borderRadius: BorderRadius.circular(_smallBorderRadius),
        boxShadow: _softShadow(0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: onColor ? Colors.white70 : SaluteColors.brownOrange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: onColor ? Colors.white70 : SaluteColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: onColor ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROTOCOLO DE EMERGENCIA
// ─────────────────────────────────────────────────────────────────────────────

/// "Protocolo de Emergencia": a quién avisa el botón rojo SOS. Con un contacto
/// configurado muestra su nombre y teléfono (tocar la fila o el botón verde
/// abre el marcador; el lápiz lo cambia); sin contacto, ofrece configurarlo.
/// En el perfil de otro familiar (sin permiso para editar) solo se muestra lo
/// que diga su ficha.
class _EmergencyCard extends StatelessWidget {
  final String name;
  final String phone;
  final String fallbackText;
  final VoidCallback? onCall;
  final VoidCallback? onConfigure;

  const _EmergencyCard({
    required this.name,
    required this.phone,
    required this.fallbackText,
    this.onCall,
    this.onConfigure,
  });

  static const _description =
      'Elegí a la persona a la que avisamos si necesitás ayuda. El botón rojo SOS, '
      'que está en todas las pantallas, le manda un mensaje con tu ubicación.';

  bool get _hasContact => onCall != null && phone.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasContact && onConfigure == null) return _buildReadOnly();

    return Container(
      width: double.infinity,
      padding: _cardPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadius),
        boxShadow: _softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SaluteColors.lightGreen.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emergency_outlined, color: SaluteColors.primaryGreen, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Protocolo de Emergencia',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _description,
            style: TextStyle(fontSize: 13, color: SaluteColors.textMuted, height: 1.4, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          if (_hasContact) _buildContact() else _buildConfigureButton(),
        ],
      ),
    );
  }

  Widget _buildContact() {
    final displayName = name.trim().isNotEmpty ? name.trim() : 'Contacto de emergencia';
    return Semantics(
      button: true,
      label: 'Llamar a $displayName',
      child: Material(
        color: SaluteColors.bgColor,
        borderRadius: BorderRadius.circular(_smallBorderRadius),
        child: InkWell(
          onTap: onCall,
          borderRadius: BorderRadius.circular(_smallBorderRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: SaluteColors.primaryGreen.withValues(alpha: 0.15),
                  child: Text(
                    displayName[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: SaluteColors.primaryGreen),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SaluteColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (onConfigure != null)
                  IconButton(
                    onPressed: onConfigure,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: SaluteColors.textMuted,
                    tooltip: 'Cambiar contacto',
                  ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: SaluteColors.primaryGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.call, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigureButton() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 50),
      child: FilledButton.icon(
        onPressed: onConfigure,
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: const Text('CONFIGURAR S.O.S.', style: TextStyle(fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: SaluteColors.primaryGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_smallBorderRadius)),
        ),
      ),
    );
  }

  /// Perfil de otro familiar: se muestra lo que diga su ficha, sin llamar.
  Widget _buildReadOnly() {
    return SizedBox(
      width: double.infinity,
      child: _OverviewTile(
        icon: Icons.emergency_outlined,
        label: 'EMERGENCIA',
        value: fallbackText.isNotEmpty ? fallbackText : 'Sin configurar',
        bgColor: SaluteColors.primaryGreen,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BANNERS
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(_borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_borderRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaccineBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _VaccineBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ActionBanner(
      color: SaluteColors.terracotta,
      icon: Icons.vaccines_outlined,
      title: 'Carné de vacunación',
      subtitle: 'Dosis aplicadas, próximas y certificado',
      onTap: onTap,
    );
  }
}

class _ChecklistBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ChecklistBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ActionBanner(
      color: SaluteColors.primaryGreen,
      icon: Icons.checklist_rounded,
      title: 'Checklist de hoy',
      subtitle: 'Marcá cada toma como tomada o no tomada',
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEDICATION LIST ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _MedicationItem extends StatelessWidget {
  final String name;
  final String dose;
  final double progress;
  final bool isChronic;
  final VoidCallback? onTap;
  const _MedicationItem({
    required this.name,
    required this.dose,
    required this.progress,
    this.isChronic = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_borderRadius),
          child: Container(
            padding: _cardPadding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_borderRadius),
              boxShadow: _softShadow(0.04),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SaluteColors.lightGreen.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(_smallBorderRadius),
                  ),
                  child: const Icon(Icons.medication_outlined, color: SaluteColors.primaryGreen, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      if (isChronic)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: SaluteColors.lightGreen.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Crónico',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SaluteColors.primaryGreen),
                          ),
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[200],
                            color: SaluteColors.primaryGreen,
                            minHeight: 7,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(
                    dose,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: SaluteColors.textMuted),
                  ),
                ),
                const Icon(Icons.chevron_right, color: SaluteColors.textMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY SECTION HINT
// ─────────────────────────────────────────────────────────────────────────────

class _EmptySectionHint extends StatelessWidget {
  final String text;
  const _EmptySectionHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_smallBorderRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(color: SaluteColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WELLBEING CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WellbeingCard extends StatelessWidget {
  final FamilyProfileData member;
  final VoidCallback? onTap;

  const _WellbeingCard({required this.member, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: _cardPadding,
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(_borderRadius),
        border: Border.all(color: SaluteColors.lightGreen.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _softShadow(0.05),
            ),
            child: Icon(
              member.isPet ? Icons.monitor_weight_outlined : Icons.monitor_heart,
              color: member.isPet ? SaluteColors.primaryGreen : SaluteColors.danger,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.wellbeingLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: SaluteColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  member.wellbeingTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: SaluteColors.primaryGreen),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              member.wellbeingValue,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: member.isPet ? 'Ver historial de peso' : 'Ver métricas de bienestar',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_borderRadius),
        child: card,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final String tag, title, subtitle;
  final Color bgColor;
  final IconData icon;
  const _AlertCard({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: _cardPadding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_borderRadius),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.95), size: 26),
          ),
        ],
      ),
    );
  }
}
