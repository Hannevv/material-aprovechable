import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:infrastructure_mobile/infrastructure_mobile.dart';

class GPS extends GeolocatorPlatform {
  bool enabled = true, requested = false;
  LocationPermission permiso = LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permiso;
  @override
  Future<LocationPermission> requestPermission() async {
    requested = true;
    return permiso;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    longitude: -76.6,
    latitude: 2.4,
    timestamp: DateTime.now(),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );
}

void main() {
  test('GPS produce coordenadas sin dirección', () async {
    final u = await GeolocalizacionStrategy(platform: GPS()).obtenerUbicacion();
    expect(u.latitud, 2.4);
    expect(u.direccion, isNull);
  });
  test('servicio deshabilitado permite alternativa manual', () async {
    await expectLater(
      GeolocalizacionStrategy(
        platform: GPS()..enabled = false,
      ).obtenerUbicacion(),
      throwsA(isA<Fallo>()),
    );
    expect(
      (await const DireccionManualStrategy(
        'Calle',
      ).obtenerUbicacion()).direccion,
      'Calle',
    );
  });
  test('permiso denegado solicita y rechaza', () async {
    final gps = GPS()..permiso = LocationPermission.denied;
    await expectLater(
      GeolocalizacionStrategy(platform: gps).obtenerUbicacion(),
      throwsA(isA<Fallo>()),
    );
    expect(gps.requested, isTrue);
  });
  test('denegado permanentemente no vuelve a solicitar', () async {
    final gps = GPS()..permiso = LocationPermission.deniedForever;
    await expectLater(
      GeolocalizacionStrategy(platform: gps).obtenerUbicacion(),
      throwsA(isA<Fallo>()),
    );
    expect(gps.requested, isFalse);
  });
}
