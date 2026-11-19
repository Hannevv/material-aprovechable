import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  for (final e in EstadoSolicitud.values) {
    for (final action in ['asignar', 'recolectar', 'cancelar']) {
      test('${e.name} $action', () {
        final state = estadoDe(e);
        EstadoSolicitud call() => switch (action) {
          'asignar' => state.asignar(),
          'recolectar' => state.recolectar(),
          _ => state.cancelar(),
        };
        final valid =
            (e == EstadoSolicitud.PENDIENTE && action != 'recolectar') ||
            (e == EstadoSolicitud.ASIGNADA && action != 'asignar');
        if (valid) {
          expect(call(), switch (action) {
            'asignar' => EstadoSolicitud.ASIGNADA,
            'recolectar' => EstadoSolicitud.RECOLECTADA,
            _ => EstadoSolicitud.CANCELADA,
          });
        } else {
          expect(call, throwsA(isA<Fallo>()));
        }
      });
    }
  }
  test('ubicaciones válidas y límites', () {
    expect(Ubicacion(latitud: -90, longitud: 180).tieneCoordenadas, isTrue);
    expect(Ubicacion(direccion: 'Calle').tieneCoordenadas, isFalse);
  });
  test('ubicaciones inválidas', () {
    for (final f in [
      () => Ubicacion(),
      () => Ubicacion(direccion: ' '),
      () => Ubicacion(latitud: 1),
      () => Ubicacion(longitud: 1),
      () => Ubicacion(latitud: 91, longitud: 0),
      () => Ubicacion(latitud: 0, longitud: 181),
      () => Ubicacion(latitud: double.nan, longitud: 0),
      () => Ubicacion(latitud: 1, longitud: 1, direccion: 'Calle'),
    ]) {
      expect(f, throwsA(isA<Fallo>()));
    }
  });
  test('Strategy manual sin geocodificación', () async {
    final u = await const DireccionManualStrategy('Calle').obtenerUbicacion();
    expect(u.direccion, 'Calle');
    expect(u.latitud, isNull);
  });
  test('solicitud inmutable y ciclo de vida', () {
    final s = Solicitud(
      id: 's',
      ciudadanoId: 'c',
      materiales: [TipoMaterial.PAPEL],
      ubicacion: Ubicacion(direccion: 'C'),
      fechaCreacion: DateTime.utc(2026),
      estado: EstadoSolicitud.PENDIENTE,
    );
    final a = s.asignar('r', DateTime.utc(2026));
    expect(s.estado, EstadoSolicitud.PENDIENTE);
    expect(a.recolectar().recicladorId, 'r');
    expect(() => s.materiales.clear(), throwsUnsupportedError);
    expect(() => a.recolectar().cancelar(), throwsA(isA<Fallo>()));
  });
  test('materiales requeridos', () {
    expect(
      () => Solicitud(
        id: 's',
        ciudadanoId: 'c',
        materiales: [],
        ubicacion: Ubicacion(direccion: 'C'),
        fechaCreacion: DateTime.now(),
        estado: EstadoSolicitud.PENDIENTE,
      ),
      throwsA(isA<Fallo>()),
    );
  });
  test('cuenta y modalidad', () {
    expect(
      () => Reciclador(
        id: 'r',
        nombre: 'N',
        documento: 'D',
        modalidad: ModalidadReciclador.CON_APP,
        estado: EstadoReciclador.ACTIVO,
      ),
      throwsA(isA<Fallo>()),
    );
    expect(
      Reciclador(
        id: 'r',
        nombre: 'N',
        documento: 'D',
        modalidad: ModalidadReciclador.SIN_APP,
        estado: EstadoReciclador.INACTIVO,
      ).esAsignable,
      isFalse,
    );
  });
}
