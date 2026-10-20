/// Contenido legal de SALUTE (Aviso de Privacidad y Términos de Servicio).
///
/// IMPORTANTE:
///  - Cada vez que cambies el texto, actualizá [kTermsVersion] y
///    [kLegalLastUpdate]: la versión aceptada se guarda en `users/{uid}`.
///  - Completá [kLegalContactEmail] con un correo real antes de publicar.
///  - Este texto es una base redactada para el proyecto; antes de lanzar
///    la app al público conviene que lo revise un profesional del derecho.
const String kTermsVersion = '2026-10-05';
const String kLegalLastUpdate = '5 de octubre de 2026';
const String kLegalContactEmail = 'agregaemail@gmail.com';

class LegalItem {
  final String title;
  final String body;
  const LegalItem(this.title, this.body);
}

const List<LegalItem> kPrivacyItems = [
  LegalItem(
    'Qué datos recopilamos',
    'Datos de tu cuenta (nombre y correo) y la información que vos cargás: '
        'perfiles de personas y mascotas, historial médico, medicación, signos '
        'vitales, agenda, diario de bienestar y botiquín. Usamos tu ubicación '
        'solo cuando abrís el mapa o activás una alerta de emergencia. Los '
        'archivos adjuntos a tus órdenes (fotos y PDF) se guardan únicamente '
        'en tu dispositivo.',
  ),
  LegalItem(
    'Cómo los protegemos',
    'La información viaja cifrada (HTTPS/TLS). El detalle de tu historial '
        'médico y las notas de medicación se cifran con AES-256 antes de '
        'subirse, con una clave que queda en el almacenamiento seguro de tu '
        'dispositivo. El resto de los datos (por ejemplo fechas, tipos de '
        'registro o signos vitales) se almacena con las protecciones '
        'estándar de Google Cloud, sin cifrado adicional de la app. Solo '
        'vos y las personas con las que decidas compartir cada perfil '
        'pueden ver sus datos de salud.',
  ),
  LegalItem(
    'Servicios de terceros',
    'Usamos Firebase (Google) para la cuenta y el almacenamiento, Google '
        'Sign-In si elegís entrar con Google, y servicios de mapas para '
        'mostrar centros de salud cercanos. Si usás el chat de orientación, '
        'el texto que escribas se procesa mediante un servicio de '
        'inteligencia artificial de terceros. Estos proveedores pueden '
        'operar servidores fuera de la Argentina. No vendemos tu '
        'información personal.',
  ),
  LegalItem(
    'Datos sensibles y consentimiento',
    'Los datos de salud son datos sensibles. Al crear tu cuenta aceptás '
        'que los tratemos con la única finalidad de brindarte las funciones '
        'de la app. Si cargás datos de otras personas (por ejemplo, hijos o '
        'familiares a cargo), declarás tener autoridad para hacerlo.',
  ),
  LegalItem(
    'Tus derechos',
    'De acuerdo con la Ley 25.326 de Protección de Datos Personales, '
        'podés acceder, rectificar, actualizar y suprimir tus datos en '
        'cualquier momento. Podés eliminar tu cuenta y todos tus datos desde '
        'Configuración > Privacidad y Seguridad. También podés escribirnos a '
        '$kLegalContactEmail. La Agencia de Acceso a la Información Pública '
        '(AAIP) es el órgano de control de la ley y atiende denuncias y '
        'reclamos.',
  ),
];

const List<LegalItem> kTermsItems = [
  LegalItem(
    'Uso de la plataforma',
    'SALUTE es una herramienta de organización y seguimiento de la salud '
        'familiar, desarrollada como proyecto académico en etapa de '
        'prototipo. No brinda asesoramiento médico profesional y no debe '
        'usarse para diagnósticos. Ante una emergencia, llamá al 107 o al '
        '911.',
  ),
  LegalItem(
    'Inteligencia artificial y lectura automática',
    'El chat de orientación y la lectura automática de órdenes (OCR) son '
        'ayudas informativas: pueden '
        'contener errores y no constituyen un diagnóstico ni un tratamiento. '
        'Revisá siempre los datos antes de guardarlos y consultá a un '
        'profesional de la salud.',
  ),
  LegalItem(
    'Tu cuenta y tu familia',
    'Sos responsable de mantener seguras tus credenciales y de la '
        'información que cargues. Compartir un perfil con un familiar es una '
        'decisión tuya y podés revocarla cuando quieras desde la app.',
  ),
  LegalItem(
    'Alertas de emergencia',
    'El envío de alertas depende de tu conexión, de los permisos del '
        'dispositivo y de servicios de terceros. No garantizamos que la '
        'alerta sea recibida ni atendida; no la uses como único medio de '
        'pedir ayuda.',
  ),
  LegalItem(
    'Propiedad intelectual',
    'Los diseños, logotipos, textos y el código de SALUTE pertenecen a sus '
        'autores. Vos conservás la propiedad de los datos personales que '
        'ingresás.',
  ),
  LegalItem(
    'Cambios y ley aplicable',
    'Podemos modificar estos términos para reflejar cambios legales o '
        'mejoras del servicio; te avisaremos dentro de la app con '
        'anticipación razonable. Se rigen por las leyes de la República '
        'Argentina.',
  ),
];