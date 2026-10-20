// lib/screens/ai.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/voice_buttons.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/tts_service.dart';
import 'package:saluteapp/core/models/chat_models.dart';
import 'package:saluteapp/core/services/ai_adapters_service.dart';
import 'package:saluteapp/core/services/chat_history_repository.dart';

class SaluteAIScreen extends StatefulWidget {
  final VoidCallback? onBackToDashboard;

  const SaluteAIScreen({super.key, this.onBackToDashboard});

  @override
  State<SaluteAIScreen> createState() => _SaluteAIScreenState();
}

class _SaluteAIScreenState extends State<SaluteAIScreen> {
  final ChatHistoryRepository _repo = ChatHistoryRepository();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();

  _AiOption _selectedAi = _aiOptions.first;

  /// Conversación abierta desde el historial (null = consulta nueva).
  Conversation? _active;

  /// Se incrementa para recrear el chat (nueva consulta, abrir historial,
  /// cambiar de IA). No depende del id de la conversación para no
  /// reconstruir el chat mientras se guarda el primer mensaje.
  int _chatSession = 0;

  List<Conversation> _history = [];

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  @override
  void dispose() {
    TtsService.instance.stop();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _refreshHistory() async {
    final all = await _repo.loadAll();
    final supportedIds = _aiOptions.map((option) => option.model.id).toSet();
    final supported = all
        .where((conversation) => supportedIds.contains(conversation.aiId))
        .toList();

    // Descarta conversaciones creadas con proveedores que ya no existen.
    for (final conversation in all) {
      if (!supportedIds.contains(conversation.aiId)) {
        await _repo.delete(conversation.id);
      }
    }

    if (mounted) setState(() => _history = supported);
  }

  void _newConversation() {
    setState(() {
      _active = null;
      _chatSession++;
    });
  }

  void _selectAi(_AiOption ai) {
    if (ai.model.id == _selectedAi.model.id) return;
    // Con otro agente no se arrastra el contexto del anterior.
    setState(() {
      _selectedAi = ai;
      _active = null;
      _chatSession++;
    });
  }

  void _openConversation(Conversation c) {
    setState(() {
      _active = c;
      _selectedAi = _aiOptions.firstWhere(
            (o) => o.model.id == c.aiId,
        orElse: () => _aiOptions.first,
      );
      _chatSession++;
    });
  }

  Future<void> _deleteConversation(Conversation c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar consulta'),
        content: Text('¿Querés eliminar "${c.title}" del historial?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _repo.delete(c.id);
    if (_active?.id == c.id && mounted) _newConversation();
    await _refreshHistory();
  }

  // -------------------------------------------------------------------------
  // Escáner de recetas
  // -------------------------------------------------------------------------

  String _mimeOf(XFile f) {
    final name = f.path.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return f.mimeType ?? 'image/jpeg';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _scanPrescription() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Sacar foto'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Redimensionar y comprimir: más rápido, más barato y suficiente para OCR.
    final Uint8List bytes;
    final String mimeType;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
      mimeType = _mimeOf(file);
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo acceder a la cámara o a la galería.');
      }
      return;
    }
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final ai = _selectedAi;
    String? text;
    try {
      final adapter = AiFactory.getAdapter(ai.model);
      text = await adapter.sendImage(
        bytes,
        mimeType: mimeType,
        prompt: _scanPrompt,
        systemPrompt: _scanSystemPrompt,
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // cierra el loading

    if (text == null) {
      _showSnack('No se pudo leer la receta. Probá de nuevo.');
      return;
    }

    final edited = await _showTranscription(text);
    if (edited == null || edited.trim().isEmpty) return;
    await _saveScan(edited.trim(), ai);
  }

  Future<String?> _showTranscription(String text) {
    final controller = TextEditingController(text: text);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transcripción de la receta',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La IA puede equivocarse, sobre todo con letra manuscrita. '
                    'Revisá nombres de medicamentos y dosis contra tu receta original.',
                style: TextStyle(color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Descartar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(controller.text),
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveScan(String text, _AiOption ai) async {
    final now = DateTime.now();
    final conv = Conversation(
      id: now.microsecondsSinceEpoch.toString(),
      aiId: ai.model.id,
      title: 'Receta escaneada • ${now.day} ${_meses[now.month - 1]}',
      updatedAt: now,
      messages: [
        AiMessage(role: 'user', text: '📄 Receta escaneada', createdAt: now),
        AiMessage(role: 'assistant', text: text, createdAt: now),
      ],
    );
    await _repo.save(conv);
    await _refreshHistory();
    // Queda abierta en el chat para poder hacer preguntas sobre la receta.
    if (mounted) _openConversation(conv);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Salute IA',
              onBack: widget.onBackToDashboard,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _DisclaimerBanner(),
                    const SizedBox(height: 20),
                    const _HeroHeadline(),
                    const SizedBox(height: 20),
                    _AiSelector(selected: _selectedAi, onSelected: _selectAi),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: _ChatCard(
                        key: ValueKey('chat-$_chatSession'),
                        controller: _inputController,
                        ai: _selectedAi,
                        initial: _active,
                        repo: _repo,
                        onSaved: (_) => _refreshHistory(),
                        onNewConversation: _newConversation,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _AccionesRapidasSection(onScan: _scanPrescription),
                    const SizedBox(height: 28),
                    _HistorialSection(
                      items: _history,
                      onOpen: _openConversation,
                      onDelete: _deleteConversation,
                    ),
                    const SizedBox(height: 8),
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

// ---------------------------------------------------------------------------
// Opciones de IA
// ---------------------------------------------------------------------------

class _AiOption {
  final AiModel model;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String systemPrompt;

  const _AiOption({
    required this.model,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.systemPrompt,
  });
}

const String _salutePrompt =
    'Sos un asistente de la app Salute. Respondé en español rioplatense, '
    'de forma clara y concisa, con información general y educativa. '
    'Nunca diagnostiques ni indiques dosis o tratamientos. Ante síntomas '
    'importantes, dudas de medicación o posibles interacciones, recomendá '
    'consultar a un profesional de la salud.';

// Prompts del escáner: el agente solo transcribe, no interpreta.
const String _scanSystemPrompt =
    'Sos un asistente de transcripción de documentos. Tu única tarea es '
    'transcribir texto de imágenes, sin interpretar ni opinar.';

const String _scanPrompt =
    'Transcribí fielmente el texto de esta receta médica, respetando el '
    'orden y los renglones. Si una palabra o número no se lee con certeza, '
    'escribí [ilegible] en su lugar. No corrijas, no interpretes y no agregues '
    'dosis, recomendaciones ni advertencias. Si la imagen no es una receta o '
    'no se puede leer, decilo claramente.';

const List<_AiOption> _aiOptions = [
  _AiOption(
    model: AiModel(
      id: 'gemini-2.5-flash',
      name: 'Gemini Flash',
      provider: AiProvider.gemini,
    ),
    name: 'Gemini Flash',
    description: 'Asistente botánico',
    icon: Icons.auto_awesome,
    color: SaluteColors.primaryGreen,
    systemPrompt:
    '$_salutePrompt Tu especialidad son las plantas medicinales y la '
        'botánica: propiedades tradicionales, usos y precauciones.',
  ),
  _AiOption(
    model: AiModel(id: 'gpt-4o', name: 'GPT-4o', provider: AiProvider.openAi),
    name: 'GPT-4o',
    description: 'Asistente general',
    icon: Icons.forum_outlined,
    color: Color(0xFF387B63),
    systemPrompt:
    '$_salutePrompt Sos un asistente general de salud, hábitos y '
        'estilo de vida.',
  ),
];

class _AiSelector extends StatelessWidget {
  final _AiOption selected;
  final ValueChanged<_AiOption> onSelected;

  const _AiSelector({required this.selected, required this.onSelected});

  Future<void> _openPicker(BuildContext context) async {
    final option = await showModalBottomSheet<_AiOption>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AiSwitcherSheet(selected: selected, options: _aiOptions),
    );
    if (option != null) onSelected(option);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: selected.color,
              child: Icon(selected.icon, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'IA seleccionada',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  Text(
                    selected.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more, size: 20, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }
}

class _AiSwitcherSheet extends StatelessWidget {
  final _AiOption selected;
  final List<_AiOption> options;

  const _AiSwitcherSheet({required this.selected, required this.options});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Qué IA querés utilizar?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...options.map(
                  (option) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: option.color,
                  child: Icon(option.icon, color: Colors.white, size: 18),
                ),
                title: Text(
                  option.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(option.description),
                trailing: selected.name == option.name
                    ? const Icon(
                  Icons.check_circle,
                  color: SaluteColors.primaryGreen,
                )
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFFFE082), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB300).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.info_rounded,
              size: 18,
              color: Color(0xFFFFB300),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Asistente de Orientación',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFB300),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Análisis informativo basado en plantas y bienestar integral. No reemplaza consulta médica profesional.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeadline extends StatelessWidget {
  const _HeroHeadline();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: Colors.black87,
        ),
        children: [
          TextSpan(text: 'Tu bienestar,\n'),
          TextSpan(
            text: 'cultivado por IA.',
            style: TextStyle(color: SaluteColors.primaryGreen),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

class _ChatCard extends StatefulWidget {
  final TextEditingController controller;
  final _AiOption ai;
  final Conversation? initial;
  final ChatHistoryRepository repo;
  final ValueChanged<Conversation> onSaved;
  final VoidCallback onNewConversation;

  const _ChatCard({
    super.key,
    required this.controller,
    required this.ai,
    required this.initial,
    required this.repo,
    required this.onSaved,
    required this.onNewConversation,
  });

  @override
  State<_ChatCard> createState() => _ChatCardState();
}

class _ChatCardState extends State<_ChatCard> {
  static const String _greeting =
      '¡Hola! ¿En qué puedo ayudarte hoy sobre salud y bienestar?';

  late final Conversation _conv;
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;

  /// Error mostrado solo en la UI: no se guarda ni se envía a la IA.
  String? _error;

  @override
  void initState() {
    super.initState();
    _conv = widget.initial ??
        Conversation(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          aiId: widget.ai.model.id,
          title: 'Nueva consulta',
          updatedAt: DateTime.now(),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmitted(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isLoading) return;

    widget.controller.clear();

    setState(() {
      _error = null;
      _conv.messages.add(
        AiMessage(role: 'user', text: query, createdAt: DateTime.now()),
      );
      if (_conv.messages.length == 1) {
        _conv.title = query.length > 40 ? '${query.substring(0, 40)}…' : query;
      }
      _isLoading = true;
    });
    await _persist();
    _scrollToBottom();

    String? reply;
    String? error;
    try {
      final adapter = AiFactory.getAdapter(widget.ai.model);
      reply = await adapter.sendMessage(
        List<AiMessage>.unmodifiable(_conv.messages),
        systemPrompt: widget.ai.systemPrompt,
      );
    } catch (_) {
      error =
      '⚠️ Ocurrió un error al consultar con ${widget.ai.name}. Verificá tu conexión e intentá de nuevo.';
    }

    // La respuesta se guarda aunque el usuario ya haya cambiado de pantalla.
    if (reply != null) {
      _conv.messages.add(
        AiMessage(role: 'assistant', text: reply, createdAt: DateTime.now()),
      );
      await _persist();
    }

    if (!mounted) return;
    setState(() {
      _error = error;
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _persist() async {
    _conv.updatedAt = DateTime.now();
    await widget.repo.save(_conv);
    widget.onSaved(_conv);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Widget _bubble(BuildContext context, String text,
      {required bool isUser, String? speakId}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? SaluteColors.lightGreen : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: isUser
              ? [
            BoxShadow(
              color: SaluteColors.primaryGreen.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: isUser ? SaluteColors.primaryGreen : Colors.grey[800],
                height: 1.5,
                fontWeight: isUser ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (!isUser && speakId != null)
              SpeakButton(id: speakId, text: text, color: widget.ai.color),
          ],
        ),
      ),
    );
  }

  Widget _loadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.ai.color,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${widget.ai.name} está pensando...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _conv.messages;
    // Índices: 0 = saludo (solo UI), 1..n = mensajes, luego loading o error.
    final itemCount =
        1 + messages.length + (_isLoading ? 1 : 0) + (_error != null ? 1 : 0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[100]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.ai.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.ai.color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(widget.ai.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistente ${widget.ai.name}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'EN LÍNEA  •  ${widget.ai.description.toUpperCase()}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[500],
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Nueva consulta',
                  onPressed: widget.onNewConversation,
                  icon: Icon(
                    Icons.add_comment_outlined,
                    color: widget.ai.color,
                  ),
                ),
              ],
            ),
          ),

          // AREA DE MENSAJES
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _bubble(context, _greeting,
                        isUser: false, speakId: 'ai-msg-greeting');
                  }
                  final msgIndex = index - 1;
                  if (msgIndex < messages.length) {
                    final msg = messages[msgIndex];
                    return _bubble(context, msg.text,
                        isUser: msg.isUser,
                        speakId: msg.isUser ? null : 'ai-msg-$msgIndex');
                  }
                  if (_isLoading) return _loadingBubble();
                  return _bubble(context, _error!, isUser: false);
                },
              ),
            ),
          ),

          // INPUT FIELD
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            decoration: BoxDecoration(
              color: SaluteColors.bgColor,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: SaluteColors.lightGreen.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: SaluteColors.primaryGreen.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    onSubmitted: _handleSubmitted,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe tu consulta a ${widget.ai.name}...',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
                DictationButton(
                  controller: widget.controller,
                  color: widget.ai.color,
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    onPressed: () => _handleSubmitted(widget.controller.text),
                    icon: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.ai.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.ai.color.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  final String label;
  const _SuggestionChip({required this.label});

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? SaluteColors.primaryGreen.withValues(alpha: 0.1)
                : SaluteColors.lightGreen.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(22),
            border: _isHovered
                ? Border.all(
              color: SaluteColors.primaryGreen.withValues(alpha: 0.3),
              width: 1.5,
            )
                : null,
            boxShadow: _isHovered
                ? [
              BoxShadow(
                color: SaluteColors.primaryGreen.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
                : null,
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SaluteColors.primaryGreen,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Acciones rápidas
// ---------------------------------------------------------------------------

class _AccionesRapidasSection extends StatelessWidget {
  final VoidCallback onScan;

  const _AccionesRapidasSection({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Acciones Rapidas'),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: onScan,
          child: const _AccionCard(
            icon: Icons.document_scanner_outlined,
            iconBg: Color(0xFFF0F5F0),
            iconColor: SaluteColors.primaryGreen,
            title: 'Escaner de Recetas',
            subtitle:
            'Digitaliza tus ordenes medicas con vision artificial avanzada.',
            watermarkIcon: Icons.receipt_long_outlined,
            bgColor: Color(0xFFF5F5F5),
            titleColor: Colors.black87,
            subtitleColor: Color(0xFF666666),
            watermarkColor: Colors.black,
            watermarkOpacity: 0.04,
          ),
        ),
        const SizedBox(height: 12),
        const _AccionCard(
          icon: Icons.manage_search_outlined,
          iconBg: Color(0xFFE8E8E8),
          iconColor: Colors.black54,
          title: 'Buscar Especialistas',
          subtitle: 'Conecta con expertos en medicina integrativa y botanica.',
          watermarkIcon: Icons.person_search_outlined,
          bgColor: Color(0xFFEEEEEE),
          titleColor: Colors.black87,
          subtitleColor: Color(0xFF666666),
          watermarkColor: Colors.black,
          watermarkOpacity: 0.06,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 28,
          decoration: BoxDecoration(
            color: SaluteColors.primaryGreen,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final IconData watermarkIcon;
  final Color bgColor;
  final Color titleColor;
  final Color subtitleColor;
  final Color watermarkColor;
  final double watermarkOpacity;

  const _AccionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.watermarkIcon,
    required this.bgColor,
    required this.titleColor,
    required this.subtitleColor,
    required this.watermarkColor,
    required this.watermarkOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -16,
            child: Icon(
              watermarkIcon,
              size: 120,
              color: watermarkColor.withValues(alpha: watermarkOpacity),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 16,
                    color: subtitleColor,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Historial
// ---------------------------------------------------------------------------

const List<String> _meses = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

String _timeAgo(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'Ahora';
  if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
  if (diff.inHours < 24 && now.day == date.day) return 'Hace ${diff.inHours} h';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (today.difference(day).inDays == 1) return 'Ayer';
  return '${date.day} ${_meses[date.month - 1]}';
}

class _HistorialSection extends StatefulWidget {
  final List<Conversation> items;
  final ValueChanged<Conversation> onOpen;
  final ValueChanged<Conversation> onDelete;

  const _HistorialSection({
    required this.items,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_HistorialSection> createState() => _HistorialSectionState();
}

class _HistorialSectionState extends State<_HistorialSection> {
  static const int _collapsedCount = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final visible = _showAll ? items : items.take(_collapsedCount).toList();
    final canToggle = items.length > _collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: _SectionTitle(title: 'Historial de Consultas'),
            ),
            if (canToggle)
              GestureDetector(
                onTap: () => setState(() => _showAll = !_showAll),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: SaluteColors.lightGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _showAll ? 'VER MENOS' : 'VER TODO',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SaluteColors.primaryGreen,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Todavía no tenés consultas. Tus conversaciones con la IA van a aparecer acá.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          )
        else
          ...visible.map((c) {
            final ai = _aiOptions.firstWhere(
                  (o) => o.model.id == c.aiId,
              orElse: () => _aiOptions.first,
            );
            return _HistorialRow(
              icon: ai.icon,
              iconColor: ai.color,
              title: c.title,
              subtitle: '${ai.name} • ${_timeAgo(c.updatedAt)}',
              onTap: () => widget.onOpen(c),
              onDelete: () => widget.onDelete(c),
            );
          }),
      ],
    );
  }
}

class _HistorialRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistorialRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.grey[400],
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}