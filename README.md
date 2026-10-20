# SALUTE

**Aplicación móvil de salud preventiva familiar**: toda la información médica de personas y mascotas del hogar, en un solo lugar.


## Descripción

En la mayoría de los hogares la información médica está dispersa: recetas arrugadas, fotos en el celular, vacunas que nadie sabe si están al día, turnos que se pasan por alto. **SALUTE** centraliza todo eso y lo vuelve activo: cada integrante de la familia (y cada mascota) tiene su propio perfil, y la app se encarga de recordar, organizar y asistir.

> SALUTE **no reemplaza al profesional de la salud** ni emite diagnósticos. Las orientaciones del asistente de IA son informativas.

## Funcionalidades

| Módulo | Qué permite |
|---|---|
| **Cuenta y familia** | Registro, login con email o Google, recuperación de contraseña, grupos familiares con código o invitación por email. |
| **Perfiles** | Perfiles de personas y mascotas (grupo sanguíneo, alergias, obra social, especie, raza, peso). |
| **Historial médico** | Consultas, estudios, órdenes y recetas con adjuntos, protegidos con cifrado. |
| **Medicación y botiquín** | Tratamientos con horarios, alarmas locales (funcionan sin conexión) y control de stock y vencimientos. |
| **Carné de vacunación** | Vacunas con próxima dosis y recordatorio automático en la agenda; ideal para mascotas. |
| **Escaneo OCR** | Lectura de recetas y certificados desde una foto, **en el dispositivo** (Google ML Kit). Siempre se revisa antes de guardar. |
| **Diario y bienestar** | Estado de ánimo (emoción, foco, energía, ansiedad), triaje de síntomas (escala EVA, notas SOAP) y signos vitales. |
| **Agenda** | Turnos, controles y eventos con recordatorios. |
| **Mapa de salud** | Hospitales, clínicas, farmacias, veterinarias y vacunatorios cercanos (Google Maps). |
| **Asistente de IA** | Chat de orientación general y primeros auxilios. |
| **SOS** | Alerta por SMS (automático en Android) o WhatsApp con la ubicación actual, a un contacto de emergencia. |
| **Ficha médica** | Exportación en PDF o texto eligiendo qué secciones incluir. |
| **Compartir perfil** | El titular decide con qué integrantes de la familia comparte sus datos clínicos. |
| **Accesibilidad** | Alto contraste, texto escalable, lectura en voz alta, dictado por voz y compatibilidad con lectores de pantalla (objetivo WCAG 2.1 AA). |

## Stack tecnológico

- **Flutter / Dart** – app multiplataforma (Android e iOS)
- **Firebase** – Authentication, Cloud Firestore, Cloud Functions y extensión Trigger Email
- **Google ML Kit** – OCR en el dispositivo
- **Google Maps / Places API** – mapa y servicios cercanos
- **APIs de IA de terceros** (Gemini, OpenAI, Anthropic) mediante una interfaz común de adaptadores
- **Cifrado AES-256-GCM** con clave guardada en Keystore (Android) / Keychain (iOS)
- **Autenticación biométrica** (`local_auth`), notificaciones locales, `speech_to_text` y `flutter_tts`
- **Health Connect / HealthKit** (`health`) para wearables
- **Figma** – diseño y prototipado

## Estructura del repositorio

```
├── lib/
│   ├── auth/         # Login, registro, recuperación y bloqueo biométrico
│   ├── components/   # Widgets reutilizables y sistema de diseño
│   ├── core/         # Servicios, modelos, controladores y configuración
│   ├── legal/        # Avisos y descargos legales
│   ├── onboarding/   # Flujo de bienvenida
│   ├── personal/     # Agenda, botiquín, métricas, tratamientos y triaje
│   ├── profile/      # Perfiles, historial, vacunas, medicación, diario e IA
│   ├── sos/          # Alerta de emergencia
│   ├── home_screen.dart
│   ├── map_screen.dart
│   └── main.dart
├── test/             # Tests unitarios y de widgets
├── android/ · ios/   # Proyectos nativos
├── firestore.rules   # Reglas de seguridad de Firestore
└── firestore.indexes.json
```

## Seguridad y privacidad

- Campos sensibles (detalle del historial, notas de medicación, adjuntos) cifrados en el dispositivo con **AES-256-GCM** antes de llegar a Firestore.
- Transmisión por **TLS/HTTPS** y reglas de seguridad de Firestore.
- Control de acceso **por perfil**: solo los integrantes que el titular autoriza pueden ver los datos clínicos.
- Bloqueo con huella o reconocimiento facial para el acceso rápido y el diario.
- Permisos solicitados solo cuando la función los necesita (cámara, ubicación, contactos, micrófono).
- Diseño alineado con la Ley 25.326 (Protección de Datos Personales) y la Ley 26.529 (Derechos del Paciente) de Argentina.

## Limitaciones del proyecto

### Inteligencia artificial

Una de las limitaciones que encontramos durante el desarrollo fue el uso de las inteligencias artificiales. Al principio, la idea era que cada usuario pudiera elegir qué IA quería utilizar e iniciar sesión con su propia cuenta. Sin embargo, durante el desarrollo decidimos seleccionar nosotras dos modelos y adaptarlos mejor al objetivo del proyecto.

El principal inconveniente fue que trabajar con estos modelos requiere recursos y créditos para que puedan funcionar. Al agotarse los créditos disponibles, no pudimos seguir realizando pruebas ni mantener todas las funcionalidades activas. Por este motivo, la sección de IA quedó limitada.

A pesar de esto, pudimos avanzar con el desarrollo y comprobar el funcionamiento de la propuesta. Una posible mejora a futuro sería contar con más recursos para mantener los modelos activos y permitir que los usuarios interactúen con ellos sin interrupciones.

### Otras limitaciones

- Falta de validación clínica del índice de riesgo de salud.
- Dependencia de servicios externos para ciertas integraciones.
- El cifrado de aplicación es local a cada dispositivo: los datos cifrados no pueden leerse desde otros dispositivos de la familia.
- El envío automático de SMS en emergencias solo es posible en Android; en iOS requiere confirmación del usuario.

## Trabajo futuro

- Cifrado extremo a extremo con intercambio de claves entre integrantes de la familia.
- Análisis de sentimientos sobre el diario de salud.
- Alertas dentro de la app para notificar a los familiares.
- Integración con instituciones de salud reales.
- Mantener los modelos de IA activos de forma sostenida y expandir sus funcionalidades.
- Versiones más robustas del sistema de accesibilidad.

## Fuera de alcance

Diagnóstico médico automatizado, integración con historias clínicas institucionales u obras sociales, dispositivos médicos o hardware especializado, y análisis predictivo clínico.


## Documentación

- [Documentación completa del proyecto](https://docs.google.com/document/d/1Y-XPEtKf24gTDTXvoJUf_7aidIAvVz7cgZmYl37PeTY/edit?usp=sharing)
- [CANVAS](https://canva.link/g7687sc74xmtvag)
- [Diagrama de Gantt](https://docs.google.com/spreadsheets/d/1fSKd8wSsBgIA7qS_laL4D9YXt2dreGdS/edit?usp=sharing&ouid=112998894132033389740&rtpof=true&sd=true)
- [Diagramas de Casos de Uso y de Componentes](https://drive.google.com/file/d/1Jd_H8uojvo9d3QKqkxf4YvI3IFq3m2FH/view)
- [Prototipo en Figma](https://www.figma.com/design/GpdjEhtqLnUtBcqdgSPk9A/SALUTE-APP?node-id=0-1&t=ISCDuQmgPpkhu5iW-1)
