import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:url_launcher/url_launcher.dart';

// This key is used by the Places REST API and must not be the Android-restricted
// key configured in AndroidManifest.xml.
const String _kPlacesApiKey = String.fromEnvironment('PLACES_API_KEY');
const int _kSearchRadius = 3000;

class _PlaceCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final List<String> placeTypes;

  const _PlaceCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.placeTypes,
  });
}

class _PlaceResult {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double? rating;
  final int? userRatingsTotal;
  final bool isOpen;
  final String? phone;
  final String? website;
  final _PlaceCategory category;

  const _PlaceResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.rating,
    this.userRatingsTotal,
    required this.isOpen,
    this.phone,
    this.website,
    required this.category,
  });

  factory _PlaceResult.fromJson(
    Map<String, dynamic> json,
    _PlaceCategory category,
  ) {
    final location = json['location'] as Map<String, dynamic>?;
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final openingHours = json['currentOpeningHours'] as Map<String, dynamic>?;

    return _PlaceResult(
      placeId: json['id'] as String? ?? '',
      name: displayName?['text'] as String? ?? 'Sin nombre',
      address: json['formattedAddress'] as String? ?? '',
      lat: (location?['latitude'] as num?)?.toDouble() ?? 0,
      lng: (location?['longitude'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: (json['userRatingCount'] as num?)?.toInt(),
      isOpen: openingHours?['openNow'] as bool? ?? false,
      phone: json['nationalPhoneNumber'] as String?,
      website: json['websiteUri'] as String?,
      category: category,
    );
  }
}

final List<_PlaceCategory> _categories = <_PlaceCategory>[
  _PlaceCategory(
    id: 'hospital',
    label: 'Hospitales',
    icon: Icons.local_hospital_outlined,
    color: SaluteColors.terracotta,
    placeTypes: const ['hospital'],
  ),
  _PlaceCategory(
    id: 'clinica',
    label: 'Clínicas',
    icon: Icons.medical_services_outlined,
    color: SaluteColors.darkGreen,
    placeTypes: const ['medical_clinic', 'doctor'],
  ),
  _PlaceCategory(
    id: 'farmacia',
    label: 'Farmacias',
    icon: Icons.medication_outlined,
    color: SaluteColors.primaryGreen,
    placeTypes: const ['pharmacy'],
  ),
  _PlaceCategory(
    id: 'veterinaria',
    label: 'Veterinarias',
    icon: Icons.pets_outlined,
    color: SaluteColors.brownOrange,
    placeTypes: const ['veterinary_care'],
  ),
  _PlaceCategory(
    id: 'laboratorio',
    label: 'Laboratorios',
    icon: Icons.biotech_outlined,
    color: SaluteColors.darkGreen,
    // Places API (New) does not accept `health` for includedTypes.
    // Clinics are the closest supported nearby-healthcare category.
    placeTypes: const ['medical_clinic'],
  ),
  _PlaceCategory(
    id: 'vacunatorio',
    label: 'Vacunatorios',
    icon: Icons.vaccines_outlined,
    color: SaluteColors.primaryGreen,
    // No existe un tipo exacto de “vacunatorio” en Places API (New).
    // Usamos centros donde normalmente se aplican vacunas.
    placeTypes: const ['hospital', 'medical_clinic', 'doctor'],
  ),
  _PlaceCategory(
    id: 'dispensario',
    label: 'Dispensarios',
    icon: Icons.health_and_safety_outlined,
    color: SaluteColors.brownOrange,
    // “Dispensario” tampoco es un tipo exacto en Places API (New).
    // Se resuelve como una búsqueda amplia de centros de atención primaria.
    placeTypes: const ['medical_clinic', 'doctor', 'hospital'],
  ),
];

class _PlacesService {
  static const String _baseUrl =
      'https://places.googleapis.com/v1/places:searchNearby';

  static Future<List<_PlaceResult>> searchNearby({
    required double lat,
    required double lng,
    required _PlaceCategory category,
    int radius = _kSearchRadius,
  }) async {
    if (_kPlacesApiKey.isEmpty) {
      throw Exception(
        'Falta configurar PLACES_API_KEY con --dart-define=PLACES_API_KEY=...',
      );
    }

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _kPlacesApiKey,
        'X-Goog-FieldMask': <String>[
          'places.id',
          'places.displayName',
          'places.formattedAddress',
          'places.location',
          'places.rating',
          'places.userRatingCount',
          'places.currentOpeningHours.openNow',
          'places.nationalPhoneNumber',
          'places.websiteUri',
        ].join(','),
      },
      body: jsonEncode(<String, dynamic>{
        'includedTypes': category.placeTypes,
        'maxResultCount': 20,
        'locationRestriction': <String, dynamic>{
          'circle': <String, dynamic>{
            'center': <String, double>{'latitude': lat, 'longitude': lng},
            'radius': radius.toDouble(),
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Places API error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final places = data['places'] as List<dynamic>? ?? const [];
    return places
        .map(
          (place) =>
              _PlaceResult.fromJson(place as Map<String, dynamic>, category),
        )
        .where((place) => place.placeId.isNotEmpty)
        .toList();
  }
}

class SaluteMapScreen extends StatefulWidget {
  final VoidCallback? onBackToDashboard;

  const SaluteMapScreen({super.key, this.onBackToDashboard});

  @override
  State<SaluteMapScreen> createState() => _SaluteMapScreenState();
}

class _SaluteMapScreenState extends State<SaluteMapScreen> {
  GoogleMapController? _controller;
  Position? _userPosition;
  bool _loadingLocation = true;
  bool _loadingPlaces = false;
  bool _hasLocationPermission = false;
  String? _error;
  final Set<String> _activeCategories = <String>{};
  final List<_PlaceResult> _places = <_PlaceResult>[];
  final Map<MarkerId, Marker> _markers = <MarkerId, Marker>{};
  final Map<String, BitmapDescriptor> _categoryMarkerIcons =
      <String, BitmapDescriptor>{};
  _PlaceResult? _selectedPlace;
  int _placesRequestId = 0;

  static const CameraPosition _fallbackPosition = CameraPosition(
    target: LatLng(-34.6037, -58.3816),
    zoom: 13,
  );

  LatLng get _currentTarget {
    if (_userPosition != null) {
      return LatLng(_userPosition!.latitude, _userPosition!.longitude);
    }
    return _fallbackPosition.target;
  }

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadCategoryMarkerIcons();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _loadingLocation = false;
          _error = 'El servicio de ubicación está desactivado.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _loadingLocation = false;
          _hasLocationPermission = false;
          _error = 'Permiso de ubicación denegado.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _loadingLocation = false;
          _hasLocationPermission = false;
          _error = 'El permiso de ubicación fue bloqueado permanentemente.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userPosition = position;
        _hasLocationPermission = true;
        _loadingLocation = false;
        _error = null;
      });

      _moveCameraToUser();
      await _loadAllCategories();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _error = 'Error al obtener ubicación: $e';
      });
    }
  }

  Future<void> _loadAllCategories() async {
    if (_userPosition == null) return;

    final requestId = ++_placesRequestId;
    setState(() {
      _loadingPlaces = true;
      _error = null;
    });

    final categoriesToLoad = _categories
        .where((category) => _activeCategories.contains(category.id))
        .toList();

    // Limpiar resultados anteriores para que el filtro funcione correctamente
    if (mounted) {
      setState(() {
        _places.clear();
        _markers.clear();
        _rebuildMarkers();
      });
    }

    if (categoriesToLoad.isEmpty) {
      if (!mounted || requestId != _placesRequestId) return;
      setState(() {
        _loadingPlaces = false;
      });
      return;
    }

    final results = <_PlaceResult>[];
    final errors = <String>[];
    String? firstError;
    for (final category in categoriesToLoad) {
      try {
        final found = await _PlacesService.searchNearby(
          lat: _userPosition!.latitude,
          lng: _userPosition!.longitude,
          category: category,
        );
        results.addAll(found);
      } catch (e) {
        debugPrint('Error en categoría ${category.label}: $e');
        errors.add(category.label);
        firstError ??= e.toString();
      }
    }

    if (!mounted || requestId != _placesRequestId) return;

    final deduped = <String, _PlaceResult>{};
    for (final place in results) {
      deduped.putIfAbsent(place.placeId, () => place);
    }

    if (!mounted) return;
    setState(() {
      _places
        ..clear()
        ..addAll(deduped.values);
      _loadingPlaces = false;
      _rebuildMarkers();
      if (errors.isNotEmpty && results.isEmpty) {
        _error =
            'No se pudieron cargar los lugares.\n'
            '${firstError ?? 'Verifica la API key de Places y Places API (New).'}';
      } else if (errors.isNotEmpty) {
        _error =
            'Algunas categorías no pudieron cargarse: ${errors.join(', ')}.\n'
            '${firstError ?? ''}';
      }
    });
  }

  void _rebuildMarkers() {
    _markers.clear();

    for (final place in _places) {
      final markerId = MarkerId(place.placeId);
      _markers[markerId] = Marker(
        markerId: markerId,
        position: LatLng(place.lat, place.lng),
        icon:
            _categoryMarkerIcons[place.category.id] ??
            BitmapDescriptor.defaultMarkerWithHue(
              _hueFromColor(place.category.color),
            ),
        infoWindow: InfoWindow(
          title: place.name,
          snippet: place.isOpen ? 'Abierto ahora' : 'Cerrado',
          onTap: () => _showPlaceDetail(place),
        ),
        onTap: () => _showPlaceDetail(place),
        zIndexInt: 1,
      );
    }
  }

  double _hueFromColor(Color color) {
    final hslColor = HSLColor.fromColor(color);
    return hslColor.hue;
  }

  Future<void> _loadCategoryMarkerIcons() async {
    final icons = <String, BitmapDescriptor>{};
    for (final category in _categories) {
      icons[category.id] = await _createCategoryMarkerIcon(category);
    }

    if (!mounted) return;
    setState(() {
      _categoryMarkerIcons
        ..clear()
        ..addAll(icons);
      _rebuildMarkers();
    });
  }

  Future<BitmapDescriptor> _createCategoryMarkerIcon(
    _PlaceCategory category,
  ) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final center = const ui.Offset(size / 2, size / 2);

    final shadowPaint = ui.Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..isAntiAlias = true
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawCircle(center + const ui.Offset(0, 3), 34, shadowPaint);

    final markerPaint = ui.Paint()
      ..color = category.color
      ..isAntiAlias = true
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(center, 34, markerPaint);

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(category.icon.codePoint),
        style: TextStyle(
          color: Colors.white,
          fontSize: 38,
          fontFamily: category.icon.fontFamily,
          package: category.icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      center - ui.Offset(iconPainter.width / 2, iconPainter.height / 2),
    );

    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('No se pudo crear el icono de ${category.label}.');
    }

    return BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(),
      imagePixelRatio: 2,
    );
  }

  void _toggleCategory(String id) {
    setState(() {
      if (_activeCategories.contains(id)) {
        _activeCategories.remove(id);
      } else {
        _activeCategories.add(id);
      }
    });
    _loadAllCategories();
  }

  void _showPlaceDetail(_PlaceResult place) {
    setState(() => _selectedPlace = place);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlaceDetailSheet(
        place: place,
        onClose: () {
          Navigator.pop(context);
          if (mounted) {
            setState(() => _selectedPlace = null);
          }
        },
      ),
    );
  }

  Future<void> _centerOnUser() async {
    if (_userPosition == null) return;
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        15,
      ),
    );
  }

  void _moveCameraToUser() {
    if (_userPosition == null) return;
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLatLng = _currentTarget;

    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: userLatLng,
                zoom: 13,
              ),
              onMapCreated: (controller) {
                _controller = controller;
                if (_userPosition != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(userLatLng, 14),
                  );
                }
              },
              markers: Set<Marker>.of(_markers.values),
              myLocationEnabled: _hasLocationPermission,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onTap: (_) {
                if (_selectedPlace != null) {
                  setState(() => _selectedPlace = null);
                }
              },
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _FloatingAppBar(
                onBack: () {
                  final onBack = widget.onBackToDashboard;
                  if (onBack != null) {
                    onBack();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
                onMyLocation: _centerOnUser,
              ),
            ),
            Positioned(
              top: 76,
              left: 0,
              right: 0,
              child: _CategoryFilterBar(
                categories: _categories,
                activeCategories: _activeCategories,
                onToggle: _toggleCategory,
              ),
            ),
            Positioned(
              right: DsSpacing.lg,
              bottom: _selectedPlace == null ? 120 : 300,
              child: _MapControls(
                onZoomIn: () =>
                    _controller?.animateCamera(CameraUpdate.zoomIn()),
                onZoomOut: () =>
                    _controller?.animateCamera(CameraUpdate.zoomOut()),
                onLocate: _centerOnUser,
              ),
            ),
            if (_loadingLocation || _loadingPlaces)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DsSpacing.lg,
                      vertical: DsSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(DsBorderRadius.full),
                      boxShadow: DsShadow.md,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SaluteColors.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _loadingLocation
                              ? 'Obteniendo ubicación...'
                              : 'Buscando servicios cercanos...',
                          style: const TextStyle(
                            fontSize: DsFontSize.md,
                            fontWeight: DsFontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_loadingPlaces && _places.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DsSpacing.lg,
                      vertical: DsSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: SaluteColors.primaryGreen,
                      borderRadius: BorderRadius.circular(DsBorderRadius.full),
                    ),
                    child: Text(
                      '${_places.length} servicios encontrados',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: DsFontSize.base,
                        fontWeight: DsFontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(DsSpacing.md),
                  decoration: BoxDecoration(
                    color: SaluteColors.lightBrown,
                    borderRadius: BorderRadius.circular(DsBorderRadius.md),
                    border: Border.all(
                      color: SaluteColors.terracotta.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: SaluteColors.terracotta,
                      fontSize: DsFontSize.md,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onMyLocation;

  const _FloatingAppBar({required this.onBack, required this.onMyLocation});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Botón atrás
        _MapButton(icon: Icons.arrow_back, onTap: onBack),
        const SizedBox(width: 10),
        // Título centrado
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.lg,
              vertical: DsSpacing.md,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(DsBorderRadius.md),
              boxShadow: DsShadow.md,
            ),
            child: const Text(
              'Servicios de Salud',
              style: TextStyle(
                fontSize: DsFontSize.lg,
                fontWeight: DsFontWeight.w800,
                color: SaluteColors.primaryGreen,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Botón mi ubicación
        _MapButton(icon: Icons.my_location, onTap: onMyLocation),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: DsShadow.md,
        ),
        child: Icon(icon, color: SaluteColors.primaryGreen, size: 20),
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  final List<_PlaceCategory> categories;
  final Set<String> activeCategories;
  final ValueChanged<String> onToggle;

  const _CategoryFilterBar({
    required this.categories,
    required this.activeCategories,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.lg,
          vertical: DsSpacing.xs,
        ),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: DsSpacing.md),
        itemBuilder: (_, index) {
          final category = categories[index];
          final active = activeCategories.contains(category.id);
          return Semantics(
            button: true,
            label: category.label,
            selected: active,
            child: GestureDetector(
              onTap: () => onToggle(category.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xl),
                decoration: BoxDecoration(
                  color: active ? SaluteColors.primaryGreen : Colors.white,
                  borderRadius: BorderRadius.circular(DsBorderRadius.circle),
                  boxShadow: DsShadow.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      category.icon,
                      color: active ? Colors.white : SaluteColors.primaryGreen,
                      size: 22,
                    ),
                    const SizedBox(width: DsSpacing.sm),
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: DsFontSize.xl,
                        fontWeight: DsFontWeight.w700,
                        color: active ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onLocate;

  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsCard(
          padding: EdgeInsets.zero,
          borderRadius: DsBorderRadius.circle,
          boxShadow: DsShadow.md,
          child: Column(
            children: [
              _ControlButton(icon: Icons.add, onTap: onZoomIn),
              Container(height: 1, width: 28, color: SaluteColors.bgColor),
              _ControlButton(icon: Icons.remove, onTap: onZoomOut),
            ],
          ),
        ),
        const SizedBox(height: DsSpacing.md),
        DsCard(
          padding: EdgeInsets.zero,
          borderRadius: DsBorderRadius.circle,
          boxShadow: DsShadow.md,
          child: _ControlButton(
            icon: Icons.gps_fixed,
            onTap: onLocate,
            color: SaluteColors.primaryGreen,
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.black45,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 25),
      constraints: const BoxConstraints.tightFor(width: 56, height: 56),
      padding: EdgeInsets.zero,
    );
  }
}

class _PlaceDetailSheet extends StatelessWidget {
  final _PlaceResult place;
  final VoidCallback onClose;

  const _PlaceDetailSheet({required this.place, required this.onClose});

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: DsCard(
        padding: const EdgeInsets.all(DsSpacing.xl),
        borderRadius: DsBorderRadius.xl,
        boxShadow: DsShadow.lg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: SaluteColors.bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                DsBadge(
                  label: place.isOpen ? 'ABIERTO AHORA' : 'CERRADO',
                  backgroundColor: place.isOpen
                      ? SaluteColors.lightGreen
                      : SaluteColors.lightBrown,
                  labelColor: place.isOpen
                      ? SaluteColors.primaryGreen
                      : SaluteColors.terracotta,
                  padding: DsSpacing.md,
                ),
                if (place.rating != null) ...[
                  const SizedBox(width: DsSpacing.md),
                  const Icon(
                    Icons.star_rounded,
                    size: 20,
                    color: SaluteColors.brownOrange,
                  ),
                  const SizedBox(width: DsSpacing.xs),
                  Text(
                    place.rating!.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: DsFontSize.lg,
                      fontWeight: DsFontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              place.name,
              style: const TextStyle(
                fontSize: DsFontSize.xxl,
                fontWeight: DsFontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: DsSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: Colors.black45,
                ),
                const SizedBox(width: DsSpacing.xs),
                Expanded(
                  child: Text(
                    place.address,
                    style: const TextStyle(
                      fontSize: DsFontSize.lg,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: DsButtonPrimary(
                    label: 'Reservar turno',
                    onPressed: () => _openExternal(
                      context,
                      Uri.parse(
                        place.website ??
                            'https://www.google.com/maps/place/?q=place_id:${place.placeId}',
                      ),
                    ),
                    height: 56,
                  ),
                ),
                if (place.phone != null) ...[
                  const SizedBox(width: DsSpacing.md),
                  _RoundActionButton(
                    icon: Icons.phone_outlined,
                    onTap: () =>
                        _openExternal(context, Uri.parse('tel:${place.phone}')),
                  ),
                ],
                const SizedBox(width: DsSpacing.md),
                _RoundActionButton(
                  icon: Icons.directions_outlined,
                  onTap: () => _openExternal(
                    context,
                    Uri.parse(
                      'https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lng}&destination_place_id=${place.placeId}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SaluteColors.bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: SaluteColors.primaryGreen, size: 24),
        ),
      ),
    );
  }
}
