import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('nullability de Usuario según rol', () {
    expect(
      () => Usuario(uid: 'u', correo: 'c', rol: Rol.CIUDADANO, nombre: 'N'),
      throwsA(isA<Fallo>()),
    );
    expect(Usuario(uid: 'u', correo: 'c', rol: Rol.RECICLADOR).nombre, isNull);
    expect(
      () => Usuario(uid: 'u', correo: 'c', rol: Rol.ADMIN),
      throwsA(isA<Fallo>()),
    );
  });
  test('SIN_APP no puede tener cuenta', () {
    expect(
      () => Reciclador(
        id: 'r',
        nombre: 'N',
        documento: 'D',
        modalidad: ModalidadReciclador.SIN_APP,
        estado: EstadoReciclador.ACTIVO,
        usuarioUid: 'u',
      ),
      throwsA(isA<Fallo>()),
    );
  });
  test('asignación y descripción inválidas se rechazan', () {
    Solicitud make(EstadoSolicitud e, {String? r, DateTime? f, String? d}) =>
        Solicitud(
          id: 's',
          ciudadanoId: 'c',
          materiales: [TipoMaterial.PAPEL],
          ubicacion: Ubicacion(direccion: 'C'),
          fechaCreacion: DateTime.now(),
          estado: e,
          recicladorId: r,
          fechaAsignacion: f,
          descripcionMaterial: d,
        );
    expect(() => make(EstadoSolicitud.ASIGNADA), throwsA(isA<Fallo>()));
    expect(
      () => make(EstadoSolicitud.CANCELADA, r: 'r'),
      throwsA(isA<Fallo>()),
    );
    expect(
      () => make(EstadoSolicitud.PENDIENTE, d: 'x' * 251),
      throwsA(isA<Fallo>()),
    );
    expect(
      make(
        EstadoSolicitud.PENDIENTE,
        d: '😀' * 250,
      ).descripcionMaterial!.runes.length,
      250,
    );
  });
}
