import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

class SolicitudesFake implements SolicitudRepository {
  EstadoSolicitud? expected;
  Ubicacion? location;
  @override
  Future<ResultadoTransicion> cancelar(String id, EstadoSolicitud e) async {
    expected = e;
    return ResultadoTransicion(true, EstadoSolicitud.CANCELADA, 'ok');
  }

  @override
  Future<Solicitud> crear(List<TipoMaterial> m, String? d, Ubicacion u) async {
    location = u;
    return Solicitud(
      id: 's',
      ciudadanoId: 'c',
      materiales: m,
      ubicacion: u,
      fechaCreacion: DateTime.now(),
      estado: EstadoSolicitud.PENDIENTE,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class HistorialFake implements HistorialRepository {
  @override
  Future<List<HistorialEstado>> listarPorSolicitud(String id) async => [];
}

class RecFake implements RecicladorRepository {
  EstadoReciclador? state;
  bool conApp = false;
  @override
  Future<void> cambiarEstado(String id, EstadoReciclador e) async {
    state = e;
  }

  @override
  Future<Reciclador> registrarConApp(
    String n,
    String d,
    String? t,
    String c,
    String p,
  ) async {
    conApp = true;
    return Reciclador(
      id: 'r',
      nombre: n,
      documento: d,
      modalidad: ModalidadReciclador.CON_APP,
      estado: EstadoReciclador.ACTIVO,
      usuarioUid: 'u',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class AuthFake implements AuthRepository, UsuarioRepository {
  bool called = false;
  @override
  Future<Usuario> registrarCiudadano(
    String n,
    String c,
    String p,
    bool a,
  ) async {
    called = true;
    return Usuario(
      uid: 'u',
      correo: c,
      rol: Rol.CIUDADANO,
      nombre: n,
      fechaAceptacionPolitica: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('cancelación propaga precondición observada', () async {
    final r = SolicitudesFake(),
        s = SolicitudService(SolicitudesFake(), HistorialFake());
    final service = SolicitudService(r, HistorialFake());
    await service.cancelarPendientePropia('s');
    expect(r.expected, EstadoSolicitud.PENDIENTE);
    await service.cancelarComoAdmin('s', EstadoSolicitud.ASIGNADA);
    expect(r.expected, EstadoSolicitud.ASIGNADA);
    expect(await s.consultarHistorial('s'), isEmpty);
  });
  test('registro usa Strategy y valida materiales', () async {
    final r = SolicitudesFake();
    final s = SolicitudService(r, HistorialFake());
    await s.registrarSolicitud(
      [TipoMaterial.VIDRIO],
      null,
      const DireccionManualStrategy('C'),
    );
    expect(r.location!.direccion, 'C');
    await expectLater(
      s.registrarSolicitud([], null, const DireccionManualStrategy('C')),
      throwsA(isA<Fallo>()),
    );
  });
  test('aceptación obligatoria antes de Auth', () async {
    final f = AuthFake(), service = AuthService(AuthFake(), AuthFake());
    final s = AuthService(f, f);
    expect(
      () => s.registrarCiudadano('N', 'c', 'Password123', false),
      throwsA(isA<Fallo>()),
    );
    expect(f.called, isFalse);
    await service.registrarCiudadano('N', 'c', 'Password123', true);
  });
  test('gestión reciclador delega estados y alta', () async {
    final f = RecFake(), s = RecFake();
    final service = RecicladorService(f);
    await service.inactivar('r');
    expect(f.state, EstadoReciclador.INACTIVO);
    await service.reactivar('r');
    expect(f.state, EstadoReciclador.ACTIVO);
    await RecicladorService(s).registrar(
      'N',
      'D',
      null,
      ModalidadReciclador.CON_APP,
      correo: 'c',
      contrasenaInicial: 'Password123',
    );
    expect(s.conApp, isTrue);
  });
}
