import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:material_admin/presentation/admin_controller.dart';
import '../../../test_support/fakes.dart';

void main() {
  late Fixture f;
  late AdminController c;
  setUp(() {
    f = Fixture();
    f.auth.rol = Rol.ADMIN;
    c = AdminController(f.authService, f.solicitudService, f.recicladorService);
  });
  tearDown(() async {
    c.dispose();
    await flush();
    await f.dispose();
  });
  test('ADMIN entra; filtro inicial PENDIENTE', () async {
    await c.entrar('a@example.com', 'p');
    expect(c.usuario!.rol, Rol.ADMIN);
    expect(f.solicitudes.filtro, EstadoSolicitud.PENDIENTE);
  });
  test('rechaza CIUDADANO y RECICLADOR', () async {
    for (final rol in [Rol.CIUDADANO, Rol.RECICLADOR]) {
      f.auth.rol = rol;
      await c.entrar('c@example.com', 'p');
      expect(c.usuario, isNull);
    }
    expect(f.auth.salidas, 2);
  });
  test('filtros combinados y múltiples materiales sin duplicados', () async {
    f.solicitudes.rows = [
      solicitud(),
      solicitud(
        id: 'otra',
        estado: EstadoSolicitud.ASIGNADA,
        materiales: [TipoMaterial.VIDRIO],
      ),
    ];
    await c.entrar('a@example.com', 'p');
    await c.filtrar(EstadoSolicitud.PENDIENTE, TipoMaterial.METAL);
    await flush();
    expect(c.lista, hasLength(1));
    expect(c.lista.single.materiales, hasLength(2));
    expect(f.solicitudes.material, TipoMaterial.METAL);
  });
  test('asignación manual CON_APP y SIN_APP activos', () async {
    await c.entrar('a@example.com', 'p');
    expect(c.asignables, hasLength(2));
    for (final r in c.asignables) {
      await c.asignar(solicitud(), r.id);
      expect(f.solicitudes.recicladorId, r.id);
    }
    await c.asignar(solicitud(), 'inactivo');
    expect(f.solicitudes.asignaciones, 2);
  });
  test(
    'carrera de asignación informa conflicto y reconcilia una vez',
    () async {
      await c.entrar('a@example.com', 'p');
      f.solicitudes.conflicto = true;
      await c.asignar(solicitud(), 'r');
      expect(f.solicitudes.asignaciones, 1);
      expect(c.mensaje, contains('Conflicto'));
      expect(f.solicitudes.reconciliaciones, 1);
    },
  );
  test(
    'cancelación conserva estado observado y no repite por conflicto',
    () async {
      await c.entrar('a@example.com', 'p');
      f.solicitudes.conflicto = true;
      await c.cancelar(solicitud(estado: EstadoSolicitud.ASIGNADA));
      expect(f.solicitudes.esperado, EstadoSolicitud.ASIGNADA);
      expect(f.solicitudes.cancelaciones, 1);
    },
  );
  test('cierres permitidos y estados finales bloqueados', () async {
    await c.entrar('a@example.com', 'p');
    await c.cancelar(solicitud());
    await c.recolectar(solicitud(estado: EstadoSolicitud.ASIGNADA));
    await c.cancelar(solicitud(estado: EstadoSolicitud.RECOLECTADA));
    expect(f.solicitudes.cancelaciones, 1);
    expect(f.solicitudes.recolecciones, 1);
  });
  test('altas CON_APP y SIN_APP y duplicado saneado', () async {
    await c.entrar('a@example.com', 'p');
    for (final m in ModalidadReciclador.values) {
      await c.guardarReciclador(
        nombre: 'N',
        documento: 'D',
        modalidad: m,
        correo: 'r@example.com',
        clave: 'Password123',
      );
      expect(f.recicladores.creada, m);
    }
    f.recicladores.falla = true;
    await c.guardarReciclador(
      nombre: 'N',
      documento: 'D',
      modalidad: ModalidadReciclador.CON_APP,
      correo: 'r@example.com',
      clave: 'Password123',
    );
    expect(c.error, contains('duplicados'));
  });
  test('editar solo campos permitidos; inactivar y reactivar', () async {
    await c.entrar('a@example.com', 'p');
    await c.guardarReciclador(
      original: reciclador(),
      nombre: 'N',
      documento: 'D',
      telefono: '1',
      modalidad: ModalidadReciclador.CON_APP,
    );
    expect(f.recicladores.editado, 'r');
    await c.cambiarActividad(reciclador());
    expect(f.recicladores.estado, EstadoReciclador.INACTIVO);
    await c.cambiarActividad(reciclador(estado: EstadoReciclador.INACTIVO));
    expect(f.recicladores.estado, EstadoReciclador.ACTIVO);
  });
  test('historial conserva ejecutor, rol y reciclador', () async {
    await c.entrar('a@example.com', 'p');
    await c.verHistorial('s');
    expect(c.historial.single.actor.rol, Rol.ADMIN);
    expect(c.historial.single.recicladorId, 'r');
    expect(c.historial.single.estadoAnterior, EstadoSolicitud.PENDIENTE);
  });
  test('actualización Stream y logout limpian todos los datos', () async {
    await c.entrar('a@example.com', 'p');
    await flush();
    f.solicitudes.rows = [solicitud()];
    f.solicitudes.emitir();
    await flush();
    expect(c.lista, hasLength(1));
    await c.verHistorial('s');
    await c.salir();
    expect(c.lista, isEmpty);
    expect(c.recicladoresLista, isEmpty);
    expect(c.historial, isEmpty);
    await flush();
    expect(f.solicitudes.canalesCancelados, 1);
  });
  test('reentrada reconsulta sin polling', () async {
    await c.entrar('a@example.com', 'p');
    await c.reentrar();
    expect(f.solicitudes.reconciliaciones, 1);
  });
}
