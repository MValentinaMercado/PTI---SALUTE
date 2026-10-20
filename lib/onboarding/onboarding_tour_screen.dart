import 'package:flutter/material.dart';
import 'package:saluteapp/components/voice_buttons.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/onboarding_service.dart';

/// Un paso del recorrido: un ícono, un título corto y un texto sencillo.
class _TourStep {
  final IconData icon;
  final String title;
  final String body;
  const _TourStep({required this.icon, required this.title, required this.body});
}

const List<_TourStep> _steps = [
  _TourStep(
    icon: Icons.favorite_outline,
    title: '¡Bienvenido a Salute!',
    body: 'Acá cuidás tu salud y la de tu familia. Te mostramos lo principal en pocos pasos. '
        'Podés salir cuando quieras.',
  ),
  _TourStep(
    icon: Icons.groups_outlined,
    title: 'Tu familia y tus mascotas',
    body: 'En el Inicio ves a cada persona o mascota. Tocá una cara para abrir su perfil, '
        'o tocá el botón + para agregar a alguien.',
  ),
  _TourStep(
    icon: Icons.medication_outlined,
    title: 'Tus medicamentos a horario',
    body: 'En Diario, tocá «Nuevo tratamiento». Te avisamos a la hora de cada toma '
        'y podés anotar si ya la tomaste.',
  ),
  _TourStep(
    icon: Icons.event_note_outlined,
    title: 'Todo tu historial junto',
    body: 'En Diario están tu agenda, tus vacunas y tus consultas. '
        'En Órdenes guardás recetas y estudios sacándoles una foto.',
  ),
  _TourStep(
    icon: Icons.emergency_outlined,
    title: 'Botón SOS para emergencias',
    body: 'Es el botón rojo que ves abajo a la izquierda. Mantenelo apretado un segundo y medio, '
        'o tocalo y confirmá. Avisa a tu contacto de emergencia con tu ubicación. '
        'Cargá ese contacto en tu Perfil.',
  ),
  _TourStep(
    icon: Icons.accessibility_new,
    title: 'Hecha a tu medida',
    body: 'Podés agrandar la letra, escuchar los textos y dictar con el micrófono. '
        'Lo encontrás en Perfil, Configuración, Accesibilidad.',
  ),
];

/// Recorrido guiado inicial. Pantalla completa, un paso por vez, con los
/// mismos controles siempre en el mismo lugar:
///  - arriba a la derecha: «Omitir»
///  - abajo: «Atrás» (izquierda) y «Siguiente» / «Empezar» (derecha)
/// Cada paso se puede escuchar en voz alta.
class OnboardingTourScreen extends StatefulWidget {
  const OnboardingTourScreen({super.key});

  /// Abre el recorrido a pantalla completa. Se resuelve al cerrarlo.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const OnboardingTourScreen(),
      ),
    );
  }

  @override
  State<OnboardingTourScreen> createState() => _OnboardingTourScreenState();
}

class _OnboardingTourScreenState extends State<OnboardingTourScreen> {
  final PageController _pageController = PageController();
  int _index = 0;
  bool _closing = false;

  bool get _isFirst => _index == 0;
  bool get _isLast => _index == _steps.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _next() => _isLast ? _finish() : _goTo(_index + 1);

  void _back() {
    if (_isFirst) {
      _finish();
    } else {
      _goTo(_index - 1);
    }
  }

  /// Terminar u omitir: en los dos casos se marca como visto.
  Future<void> _finish() async {
    if (_closing) return;
    _closing = true;
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) await OnboardingService.instance.markDone(uid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // El botón «atrás» del teléfono retrocede un paso; en el primero, sale.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: SaluteColors.bgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _StepPage(step: _steps[i], index: i),
                ),
              ),
              _buildDots(),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Paso ${_index + 1} de ${_steps.length}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SaluteColors.textMuted),
              ),
            ),
          ),
          // Mismo lugar en todos los pasos; en el último se oculta pero
          // conserva su espacio, para que nada se mueva.
          Visibility(
            visible: !_isLast,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              child: const Text('Omitir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: ExcludeSemantics(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _steps.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _index ? 28 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: i == _index ? SaluteColors.primaryGreen : SaluteColors.lightGreen,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: Visibility(
              visible: !_isFirst,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: OutlinedButton(
                  onPressed: _back,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SaluteColors.primaryGreen,
                    side: const BorderSide(color: SaluteColors.primaryGreen, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Atrás', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: SaluteColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _isLast ? 'Empezar' : 'Siguiente',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final _TourStep step;
  final int index;
  const _StepPage({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    // Scroll por si la letra está muy agrandada: nunca desborda.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(color: SaluteColors.lightGreen, shape: BoxShape.circle),
              child: Icon(step.icon, size: 56, color: SaluteColors.primaryGreen),
            ),
          ),
          const SizedBox(height: 28),
          Semantics(
            header: true,
            child: Text(
              step.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, height: 1.45, fontWeight: FontWeight.w500, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpeakButton(id: 'tour-$index', text: '${step.title}. ${step.body}'),
              Flexible(
                child: Text(
                  'Escuchar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SaluteColors.primaryGreen),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
