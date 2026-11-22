import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:material_mobile/presentation/mobile_controller.dart';
import '../../../test_support/fakes.dart';

void main() {
  late Fixture f;
  late MobileController c;
  setUp(() {
    f = Fixture();
    c = MobileController(
      f.authService,
      f.solicitudService,
      f.gps,
      politica: 'Contenido de prueba suministrado',
    );
  });
  tearDown(() async {
    c.dispose();
    await flush();
    await f.dispose();
  });
  test(
    'respuesta de validación de sesión tardía no notifica controlador destruido',
    () async {
      final x = MobileController(f.authService, f.solicitudService, f.gps);
      await x.entrar('c@example.com', 'p');
      f.auth.lecturaPendiente = Completer<Usuario>();
      final pendiente = x.reentrar();
      x.dispose();
      f.auth.lecturaPendiente!.completeError(
        const Fallo(TipoFallo.autorizacion, 'Sesión caducada'),
      );
      await pendiente;
      expect(x.cerrado, isTrue);
    },
  );
  test('registro exige política, aceptación y contraseña mínima', () async {
    await c.registrar('Nombre', 'c@example.com', '123', true);
    expect(f.auth.registros, 0);
    await c.registrar('Nombre', 'c@example.com', 'Password123', false);
    expect(f.auth.registros, 0);
    await c.registrar('Nombre', 'c@example.com', 'Password123', true);
    expect(c.usuario!.rol, Rol.CIUDADANO);
    expect(f.auth.registros, 1);
    expect(c.usuario!.fechaAceptacionPolitica, isNotNull);
  });
  test('sin política no registra', () async {
    final x = MobileController(f.authService, f.solicitudService, f.gps);
    await x.registrar('N', 'c@example.com', 'Password123', true);
    expect(f.auth.registros, 0);
    x.dispose();
  });
  test('login y logout limpian lista y suscripción', () async {
    f.solicitudes.rows = [solicitud()];
    await c.entrar('c@example.com', 'Password123');
    await flush();
    expect(c.lista, hasLength(1));
    await c.salir();
    await flush();
    expect(c.usuario, isNull);
    expect(c.lista, isEmpty);
    expect(f.solicitudes.canalesCancelados, 1);
  });
  test('rechaza ADMIN en móvil', () async {
    f.auth.rol = Rol.ADMIN;
    await c.entrar('c@example.com', 'p');
    expect(c.usuario, isNull);
    expect(f.auth.salidas, 1);
    expect(c.error, contains('no tiene acceso'));
  });
  test('creación GPS uno y varios materiales confirma identificador', () async {
    await c.entrar('c@example.com', 'p');
    await c.crear([TipoMaterial.PAPEL], '', true, '');
    expect(f.gps.llamadas, 1);
    expect(f.solicitudes.ubicacion!.tieneCoordenadas, isTrue);
    expect(c.mensaje, contains('nueva'));
    await c.crear(
      [TipoMaterial.METAL, TipoMaterial.VIDRIO],
      'Descripción',
      true,
      '',
    );
    expect(f.solicitudes.recibidos, hasLength(2));
  });
  test('dirección manual no invoca GPS; descripción 0/250/>250', () async {
    await c.entrar('c@example.com', 'p');
    await c.crear([TipoMaterial.PAPEL], '', false, 'Calle 1');
    expect(f.solicitudes.descripcion, isNull);
    expect(f.solicitudes.ubicacion!.latitud, isNull);
    await c.crear([TipoMaterial.PAPEL], 'x' * 250, false, 'Calle');
    expect(f.solicitudes.creaciones, 2);
    await c.crear([TipoMaterial.PAPEL], 'x' * 251, false, 'Calle');
    expect(f.solicitudes.creaciones, 2);
    expect(f.gps.llamadas, 0);
  });
  test('lista vacía y actualización mediante Stream', () async {
    await c.entrar('c@example.com', 'p');
    await flush();
    expect(c.lista, isEmpty);
    f.solicitudes.rows = [solicitud(estado: EstadoSolicitud.ASIGNADA)];
    f.solicitudes.emitir();
    await flush();
    expect(c.lista.single.estado, EstadoSolicitud.ASIGNADA);
  });
  test(
    'cancelación usa PENDIENTE y reconcilia conflicto sin repetir',
    () async {
      await c.entrar('c@example.com', 'p');
      f.solicitudes.conflicto = true;
      await c.cancelar(solicitud());
      expect(f.solicitudes.esperado, EstadoSolicitud.PENDIENTE);
      expect(f.solicitudes.cancelaciones, 1);
      expect(c.mensaje, contains('cambió'));
      expect(f.solicitudes.reconciliaciones, greaterThan(0));
    },
  );
  test('reciclador consulta asignadas y marca recolectada', () async {
    f.auth.rol = Rol.RECICLADOR;
    f.solicitudes.rows = [solicitud(estado: EstadoSolicitud.ASIGNADA)];
    await c.entrar('r@example.com', 'p');
    await flush();
    expect(c.lista, hasLength(1));
    expect(f.solicitudes.filtro, EstadoSolicitud.ASIGNADA);
    await c.recolectar(c.lista.single);
    expect(f.solicitudes.recolecciones, 1);
  });
  test(
    'reciclador inactivo no puede entrar; inactivación cierra al reentrar',
    () async {
      f.auth.rol = Rol.RECICLADOR;
      f.auth.inactivo = true;
      await c.entrar('r@example.com', 'p');
      expect(c.usuario, isNull);
      f.auth.inactivo = false;
      await c.entrar('r@example.com', 'p');
      f.auth.inactivo = true;
      await c.reentrar();
      expect(c.usuario, isNull);
      expect(c.lista, isEmpty);
    },
  );
  test('cambio de usuario descarta datos y eventos posteriores', () async {
    f.solicitudes.rows = [solicitud()];
    await c.entrar('c@example.com', 'p');
    await flush();
    f.auth.cambiar('otro');
    await flush();
    expect(c.lista, isEmpty);
    expect(c.usuario, isNull);
    f.solicitudes.emitir();
    await flush();
    expect(c.lista, isEmpty);
  });
  test('foreground/reentrada solicita consulta autorizada', () async {
    await c.entrar('c@example.com', 'p');
    await c.reentrar();
    expect(f.solicitudes.reconciliaciones, 1);
  });
  test(
    'creación ambigua consulta y requiere revisión explícita antes de reintentar',
    () async {
      await c.entrar('c@example.com', 'p');
      f.solicitudes.ambiguo = true;
      await c.crear([TipoMaterial.PAPEL], '', false, 'C');
      expect(c.noConfirmado, isTrue);
      expect(c.reconciliado, isTrue);
      await c.crear([TipoMaterial.PAPEL], '', false, 'C');
      expect(f.solicitudes.creaciones, 1);
      c.resolverAmbigua();
      f.solicitudes.ambiguo = false;
      await c.crear([TipoMaterial.PAPEL], '', false, 'C');
      expect(f.solicitudes.creaciones, 2);
    },
  );
  test('consulta fallida no habilita reintento ambiguo', () async {
    await c.entrar('c@example.com', 'p');
    f.solicitudes.ambiguo = true;
    f.solicitudes.consultaFalla = true;
    await c.crear([TipoMaterial.PAPEL], '', false, 'C');
    c.resolverAmbigua();
    expect(c.noConfirmado, isTrue);
    expect(c.reconciliado, isFalse);
  });
}
