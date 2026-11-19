import 'package:domain/domain.dart';
import 'package:geolocator/geolocator.dart';

class GeolocalizacionStrategy implements UbicacionStrategy {
  final GeolocatorPlatform platform;
  GeolocalizacionStrategy({GeolocatorPlatform? platform})
    : platform = platform ?? GeolocatorPlatform.instance;
  @override
  Future<Ubicacion> obtenerUbicacion() async {
    if (!await platform.isLocationServiceEnabled())
      throw const Fallo(
        TipoFallo.validacion,
        'GPS no disponible; utilice dirección manual',
      );
    var permiso = await platform.checkPermission();
    if (permiso == LocationPermission.denied)
      permiso = await platform.requestPermission();
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever ||
        permiso == LocationPermission.unableToDetermine)
      throw const Fallo(
        TipoFallo.autorizacion,
        'Sin permiso GPS; utilice dirección manual',
      );
    final p = await platform.getCurrentPosition(
      locationSettings: const LocationSettings(
        timeLimit: Duration(seconds: 15),
      ),
    );
    return Ubicacion(latitud: p.latitude, longitud: p.longitude);
  }
}
