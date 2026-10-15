import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Registro de errores técnicos en un archivo de texto del dispositivo.
///
/// Es para lo que al usuario no le sirve ver (configuración, excepciones
/// inesperadas, fallos internos): se muestra un mensaje amable en pantalla y
/// el detalle queda acá. Una línea por error:
///
///   tiempo | ventana | archivo:línea | error
///
/// Uso:
/// ```dart
/// } catch (e, st) {
///   ErrorLog.instance.record(window: 'Registro', error: e, stack: st);
/// }
/// ```
/// `archivo:línea` se deduce solo del stack trace (primer frame de la app);
/// también se puede pasar `file:` a mano.
class ErrorLog {
  ErrorLog._();
  static final ErrorLog instance = ErrorLog._();

  static const _fileName = 'salute_error_log.txt';

  /// Al pasar este tamaño se descarta la mitad más vieja del archivo.
  static const _maxBytes = 512 * 1024;
  static const _maxErrorChars = 800;

  File? _file;
  Future<void> _queue = Future.value();

  /// Anota un error. No lanza nunca ni hace esperar a quien lo llama.
  void record({
    required String window,
    required Object error,
    StackTrace? stack,
    String? file,
  }) {
    try {
      final line = _format(window: window, error: error, stack: stack, file: file);
      debugPrint('[ErrorLog] $line');
      // Cola: evita que dos errores seguidos se pisen al escribir.
      _queue = _queue.then((_) => _append(line)).catchError((_) {});
    } catch (_) {
      // El log jamás debe romper la app.
    }
  }

  /// Ruta del archivo (útil para mostrarla o compartirla).
  Future<String> get path async => (await _resolve()).path;

  /// Contenido completo del log ('' si todavía no hay errores).
  Future<String> readAll() async {
    await _queue;
    final f = await _resolve();
    return await f.exists() ? f.readAsString() : '';
  }

  Future<void> clear() async {
    await _queue;
    final f = await _resolve();
    if (await f.exists()) await f.writeAsString('');
  }

  /// Anota también los errores no capturados del framework y de código
  /// asíncrono. Llamar una vez en `main()`.
  static void installGlobalHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      instance.record(window: 'Global (UI)', error: details.exceptionAsString(), stack: details.stack);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.record(window: 'Global (async)', error: error, stack: stack);
      return true;
    };
  }

  String _format({
    required String window,
    required Object error,
    StackTrace? stack,
    String? file,
  }) {
    final time = DateTime.now().toIso8601String();
    var text = error.toString().replaceAll(RegExp(r'\s*\r?\n\s*'), ' ⏎ ').trim();
    if (text.length > _maxErrorChars) text = '${text.substring(0, _maxErrorChars)}…';
    return '$time | $window | ${file ?? _originOf(stack)} | $text';
  }

  /// Primer frame del stack que pertenezca a la app: `core/auth_service.dart:223`.
  static String _originOf(StackTrace? stack) {
    if (stack == null) return 'desconocido';
    final m = RegExp(r'package:saluteapp/([^\s:]+\.dart):(\d+)').firstMatch(stack.toString());
    return m == null ? 'desconocido' : '${m[1]}:${m[2]}';
  }

  Future<File> _resolve() async {
    final existing = _file;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/$_fileName');
  }

  Future<void> _append(String line) async {
    final f = await _resolve();
    if (await f.exists() && await f.length() > _maxBytes) {
      final content = await f.readAsString();
      final half = content.substring(content.length ~/ 2);
      final firstBreak = half.indexOf('\n');
      await f.writeAsString(firstBreak == -1 ? '' : half.substring(firstBreak + 1));
    }
    await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }
}
