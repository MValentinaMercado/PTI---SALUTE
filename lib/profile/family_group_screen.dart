import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family.dart';
import 'package:saluteapp/core/services/family_service.dart';

/// FEAT-001/002: crear un grupo familiar nuevo o unirse a uno existente
/// por código. Si el usuario ya pertenece a una familia, en vez de este
/// formulario se muestra directamente el código para compartir.
class FamilyGroupScreen extends StatelessWidget {
  const FamilyGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Mi familia',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: StreamBuilder<Family?>(
                stream: FamilyService.instance.watchMyFamily(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final family = snapshot.data;
                  if (family != null) {
                    return _FamilyCodeView(family: family);
                  }
                  return const _CreateOrJoinView();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ya pertenece a una familia: mostramos el código para compartir con
/// el resto, y un formulario para invitar por email (FEAT-003) además
/// del código a mano.
class _FamilyCodeView extends StatefulWidget {
  final Family family;
  const _FamilyCodeView({required this.family});

  @override
  State<_FamilyCodeView> createState() => _FamilyCodeViewState();
}

class _FamilyCodeViewState extends State<_FamilyCodeView> {
  final _emailController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleInvite() async {
    setState(() => _sending = true);
    try {
      await FamilyService.instance.inviteByEmail(widget.family, _emailController.text);
      _emailController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitación enviada.')),
        );
      }
    } on FamilyFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            family.name,
            style: const TextStyle(fontSize: DsFontSize.h3, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            '${family.memberUids.length} miembro${family.memberUids.length == 1 ? '' : 's'} con cuenta propia',
            style: TextStyle(fontSize: DsFontSize.md, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SaluteColors.primaryGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  'Código de invitación',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: DsFontSize.md),
                ),
                const SizedBox(height: 8),
                Text(
                  family.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: family.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado.')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar código'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Invitar por email',
            style: TextStyle(fontSize: DsFontSize.h4, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            'Le mandamos el código por mail para que se una.',
            style: TextStyle(fontSize: DsFontSize.md, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'nombre@email.com',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _sending ? null : _handleInvite,
                  style: FilledButton.styleFrom(backgroundColor: SaluteColors.primaryGreen),
                  child: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          StreamBuilder<List<FamilyInvite>>(
            stream: FamilyService.instance.watchPendingInvites(family.id),
            builder: (context, snapshot) {
              final invites = snapshot.data ?? const <FamilyInvite>[];
              if (invites.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'INVITADOS PENDIENTES',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[500], letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: invites
                        .map((i) => Chip(
                              label: Text(i.email),
                              backgroundColor: SaluteColors.lightGreen,
                              labelStyle: TextStyle(color: SaluteColors.primaryGreen, fontSize: 12),
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Compartí el código con quien quieras que se una con su '
            'propia cuenta. Los perfiles de hijos o mascotas que ya '
            'tengas cargados quedan visibles para toda la familia.',
            style: TextStyle(fontSize: DsFontSize.md, color: Colors.grey[600], height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Todavía no pertenece a ninguna familia: puede crear una o unirse con
/// un código.
class _CreateOrJoinView extends StatefulWidget {
  const _CreateOrJoinView();

  @override
  State<_CreateOrJoinView> createState() => _CreateOrJoinViewState();
}

class _CreateOrJoinViewState extends State<_CreateOrJoinView> {
  final _createNameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  bool _creating = false;
  bool _joining = false;

  @override
  void dispose() {
    _createNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    setState(() => _creating = true);
    try {
      await FamilyService.instance.createFamily(_createNameController.text);
    } on FamilyFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _handleJoin() async {
    setState(() => _joining = true);
    try {
      final family = await FamilyService.instance.joinFamily(_joinCodeController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Te uniste a "${family.name}".')),
        );
      }
    } on FamilyFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crear familia',
            style: TextStyle(fontSize: DsFontSize.h4, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            'Generá un código único para compartir con el resto de tu familia.',
            style: TextStyle(fontSize: DsFontSize.md, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _createNameController,
            decoration: const InputDecoration(
              hintText: 'Ej: Familia Pérez',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _creating ? null : _handleCreate,
              style: FilledButton.styleFrom(backgroundColor: SaluteColors.primaryGreen),
              child: _creating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Crear familia'),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[300])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('o', style: TextStyle(color: Colors.grey[500])),
              ),
              Expanded(child: Divider(color: Colors.grey[300])),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Unirme a una familia',
            style: TextStyle(fontSize: DsFontSize.h4, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresá el código que te compartieron.',
            style: TextStyle(fontSize: DsFontSize.md, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _joinCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'SALUTE-8K29X',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _joining ? null : _handleJoin,
              style: OutlinedButton.styleFrom(foregroundColor: SaluteColors.primaryGreen),
              child: _joining
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unirme con código'),
            ),
          ),
        ],
      ),
    );
  }
}
