import 'package:flutter/material.dart';
import 'package:saluteapp/components/insurance_picker.dart';
import 'package:saluteapp/components/voice_buttons.dart';
import 'package:saluteapp/components/profile_avatar.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Alta o edición de un integrante del grupo familiar.
/// Si [existingProfile] viene null, es alta; si viene con valor, edita.
class ProfileFormScreen extends StatefulWidget {
  final FamilyProfile? existingProfile;

  const ProfileFormScreen({super.key, this.existingProfile});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  late ProfileType _type;
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _relationController = TextEditingController();
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _speciesController = TextEditingController();
  final _breedController = TextEditingController();
  DateTime? _birthDate;
  String _insurance = ''; // '' = sin obra social / sin cargar
  String _avatarUrl = ''; // '' = sin foto
  bool _saving = false;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    _type = p?.type ?? ProfileType.persona;
    _nameController.text = p?.name ?? '';
    _lastNameController.text = p?.lastName ?? '';
    _usernameController.text = p?.username ?? '';
    _relationController.text = p?.relation ?? '';
    _bloodTypeController.text = p?.bloodType ?? '';
    _allergiesController.text = p?.allergies ?? '';
    _speciesController.text = p?.species ?? '';
    // Para que el chip de Perro/Gato se marque también al escribir a mano.
    _speciesController.addListener(() {
      if (mounted) setState(() {});
    });
    _breedController.text = p?.breed ?? '';
    _birthDate = p?.birthDate;
    _insurance = p?.insurance ?? '';
    _avatarUrl = p?.avatarUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _relationController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _speciesController.dispose();
    _breedController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _changePhoto() async {
    final result = await AvatarPhoto.choose(context, hasPhoto: _avatarUrl.isNotEmpty);
    // null = canceló; '' = quitar la foto.
    if (result != null && mounted) setState(() => _avatarUrl = result);
  }

  Future<void> _pickInsurance() async {
    final picked = await showInsurancePicker(context, current: _insurance);
    if (picked != null && mounted) setState(() => _insurance = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Ingresá un nombre.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        final updated = widget.existingProfile!.copyWith(
          name: name,
          lastName: _lastNameController.text.trim(),
          username: _usernameController.text.trim(),
          relation: _relationController.text.trim(),
          bloodType: _bloodTypeController.text.trim(),
          allergies: _allergiesController.text.trim(),
          insurance: _type == ProfileType.persona ? _insurance : '',
          // El contacto de emergencia ya no se edita desde este formulario;
          // se conserva el valor que ya tenía guardado el perfil.
          emergencyContact: widget.existingProfile!.emergencyContact,
          birthDate: _birthDate,
          avatarUrl: _avatarUrl,
          species: _type == ProfileType.mascota ? _speciesController.text.trim() : null,
          breed: _type == ProfileType.mascota ? _breedController.text.trim() : null,
        );
        await ProfileService.instance.updateProfile(updated);
      } else {
        final newProfile = FamilyProfile(
          id: '',
          ownerUid: '',
          type: _type,
          name: name,
          lastName: _lastNameController.text.trim(),
          username: _usernameController.text.trim(),
          relation: _relationController.text.trim(),
          bloodType: _bloodTypeController.text.trim(),
          allergies: _allergiesController.text.trim(),
          insurance: _type == ProfileType.persona ? _insurance : '',
          // Se crea sin contacto de emergencia: este formulario ya no
          // ofrece cargarlo; se puede completar después si hace falta.
          emergencyContact: '',
          birthDate: _birthDate,
          avatarUrl: _avatarUrl,
          species: _type == ProfileType.mascota ? _speciesController.text.trim() : null,
          breed: _type == ProfileType.mascota ? _breedController.text.trim() : null,
        );
        await ProfileService.instance.createProfile(newProfile);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _showMessage('No se pudo guardar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar perfil'),
        content: Text('¿Seguro que querés eliminar a ${widget.existingProfile!.name}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: SaluteColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ProfileService.instance.deleteProfile(widget.existingProfile!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _showMessage('No se pudo eliminar. Intentá de nuevo.');
      setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      appBar: AppBar(
        backgroundColor: SaluteColors.bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(_isEditing ? 'Editar perfil' : 'Nuevo perfil'),
        actions: [
          // El perfil propio (isSelf) no se puede borrar desde acá: es el
          // que representa al dueño de la cuenta (ver BUG-001).
          if (_isEditing && widget.existingProfile?.isSelf != true)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline, color: SaluteColors.danger),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoPicker(),
              const SizedBox(height: 24),
              if (!_isEditing) ...[
                const _FieldLabel('TIPO DE PERFIL'),
                const SizedBox(height: 10),
                _buildTypeSelector(),
                const SizedBox(height: 20),
              ],
              const _FieldLabel('NOMBRE'),
              const SizedBox(height: 10),
              _textField(_nameController, hint: 'Nombre'),
              const SizedBox(height: 20),
              if (_type == ProfileType.persona) ...[
                const _FieldLabel('APELLIDO'),
                const SizedBox(height: 10),
                _textField(_lastNameController, hint: 'Apellido'),
                const SizedBox(height: 20),
                const _FieldLabel('NOMBRE DE USUARIO'),
                const SizedBox(height: 10),
                _textField(
                  _usernameController,
                  hint: 'Cómo querés que te llamemos en la app',
                ),
                const SizedBox(height: 20),
              ],
              _FieldLabel(_type == ProfileType.mascota ? 'RELACIÓN (EJ: MASCOTA DE JUAN)' : 'RELACIÓN (EJ: HIJA, PADRE)'),
              const SizedBox(height: 10),
              _textField(_relationController, hint: 'Relación'),
              const SizedBox(height: 20),
              if (_type == ProfileType.mascota) ...[
                const _FieldLabel('ESPECIE'),
                const SizedBox(height: 10),
                _buildSpeciesChips(),
                const SizedBox(height: 10),
                _textField(_speciesController, hint: 'Perro, gato, etc.'),
                const SizedBox(height: 6),
                Text(
                  'Con perro o gato el carné de vacunas ya trae un esquema orientativo.',
                  style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                ),
                const SizedBox(height: 20),
                const _FieldLabel('RAZA'),
                const SizedBox(height: 10),
                _textField(_breedController, hint: 'Raza'),
                const SizedBox(height: 20),
              ],
              const _FieldLabel('FECHA DE NACIMIENTO'),
              const SizedBox(height: 10),
              _buildDatePicker(),
              const SizedBox(height: 20),
              if (_type == ProfileType.persona) ...[
                const _FieldLabel('GRUPO SANGUÍNEO'),
                const SizedBox(height: 10),
                _textField(_bloodTypeController, hint: 'Ej: O+'),
                const SizedBox(height: 20),
                const _FieldLabel('OBRA SOCIAL'),
                const SizedBox(height: 10),
                _buildInsurancePicker(),
                const SizedBox(height: 20),
              ],
              const _FieldLabel('ALERGIAS'),
              const SizedBox(height: 10),
              _textField(_allergiesController, hint: 'Ej: Penicilina, mariscos, polen', dictation: true),
              const SizedBox(height: 32),
              _buildSaveButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Foto de perfil: se ve en el Perfil, el Diario y el selector de perfiles.
  Widget _buildPhotoPicker() {
    final hasPhoto = _avatarUrl.isNotEmpty;
    return Center(
      child: Column(
        children: [
          ProfileAvatar(
            avatarUrl: _avatarUrl,
            type: _type,
            name: _nameController.text,
            radius: 54,
            onEditPhoto: _saving ? null : _changePhoto,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _saving ? null : _changePhoto,
            icon: Icon(hasPhoto ? Icons.edit_outlined : Icons.add_a_photo_outlined, size: 18),
            label: Text(hasPhoto ? 'Cambiar foto' : 'Agregar foto'),
            style: TextButton.styleFrom(
              foregroundColor: SaluteColors.primaryGreen,
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesChips() {
    final current = _speciesController.text.trim().toLowerCase();
    Widget chip(String label) {
      final selected = current == label.toLowerCase();
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: SaluteColors.primaryGreen,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : Colors.black87,
        ),
        onSelected: (_) => setState(() => _speciesController.text = label),
      );
    }

    return Wrap(spacing: 8, children: [chip('Perro'), chip('Gato')]);
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: _typeChip('Persona', ProfileType.persona, Icons.person_outline),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _typeChip('Mascota', ProfileType.mascota, Icons.pets_outlined),
        ),
      ],
    );
  }

  Widget _typeChip(String label, ProfileType type, IconData icon) {
    final selected = _type == type;
    return GestureDetector(
      onTap: () => setState(() => _type = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? SaluteColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? SaluteColors.primaryGreen : Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : SaluteColors.textMuted, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _pickBirthDate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 18, color: SaluteColors.textMuted),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _birthDate != null
                    ? '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}'
                    : 'Seleccionar fecha',
                style: TextStyle(
                  color: _birthDate != null ? Colors.black87 : SaluteColors.textMuted,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsurancePicker() {
    return GestureDetector(
      onTap: _pickInsurance,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.local_hospital_outlined, size: 18, color: SaluteColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _insurance.isNotEmpty ? _insurance : 'Seleccionar obra social',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _insurance.isNotEmpty ? Colors.black87 : SaluteColors.textMuted,
                  fontSize: 15,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: SaluteColors.textMuted),
          ],
        ),
      ),
    );
  }

  /// [dictation] agrega el micrófono y deja crecer el campo; se usa solo
  /// donde el texto es libre y puede ser largo (no en nombres, raza, etc.,
  /// que el reconocimiento de voz suele escribir mal).
  Widget _textField(TextEditingController controller, {required String hint, bool dictation = false}) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: dictation ? 4 : 1,
      keyboardType: dictation ? TextInputType.multiline : null,
      textCapitalization: dictation ? TextCapitalization.sentences : TextCapitalization.none,
      style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        suffixIcon: dictation
            ? Align(
                alignment: Alignment.topRight,
                widthFactor: 1,
                heightFactor: 1,
                child: DictationButton(controller: controller),
              )
            : null,
        hintText: hint,
        hintStyle: TextStyle(color: SaluteColors.textMuted, fontSize: 15),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SaluteColors.primaryGreen, width: 2),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: SaluteColors.primaryGreen,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _saving
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)),
        )
            : Text(
          _isEditing ? 'Guardar cambios' : 'Crear perfil',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
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
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: SaluteColors.primaryGreen,
        letterSpacing: 1,
      ),
    );
  }
}