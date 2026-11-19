import 'dart:async';
import 'package:domain/domain.dart';
import 'package:infrastructure_supabase/infrastructure_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'fake_gateway.dart';

void main() {
  test('mapeo explícito de solicitud y nullable', () {
    final s = solicitudDe(solicitudRow());
    expect(s.materiales, [TipoMaterial.PAPEL]);
    expect(s.recicladorId, isNull);
    expect(s.fechaCreacion.isUtc, isTrue);
    expect(solicitudDe(solicitudRow(estado: 'ASIGNADA')).recicladorId, 'r');
  });
  test('mapeo historial distingue ejecutor y asociado', () {
    final h = historialDe({
      'id': 'h',
      'solicitud_id': 's',
      'estado_anterior': 'ASIGNADA',
      'estado_nuevo': 'RECOLECTADA',
      'fecha_hora': '2026-01-01T00:00:00Z',
      'usuario_ejecutor_uid': 'admin',
      'rol_ejecutor': 'ADMIN',
      'reciclador_id': 'r',
    });
    expect(h.actor.usuarioId, 'admin');
    expect(h.recicladorId, 'r');
  });
  test('errores autorización validación red y no confirmado', () {
    expect(
      traducirError(const PostgrestException(message: 'x', code: '42501')).tipo,
      TipoFallo.autorizacion,
    );
    expect(
      traducirError(const PostgrestException(message: 'x', code: '23505')).tipo,
      TipoFallo.validacion,
    );
    expect(traducirError(TimeoutException('x')).tipo, TipoFallo.conectividad);
    expect(
      traducirError(TimeoutException('x'), mutacion: true).tipo,
      TipoFallo.noConfirmado,
    );
  });
  test('cancelación solo precondición sin actor/destino', () async {
    final g = FakeGateway()
      ..result = {
        'confirmada': false,
        'estado_actual': 'ASIGNADA',
        'codigo': 'CONFLICTO_ESTADO',
      };
    final r = await SupabaseSolicitudRepository(
      g,
    ).cancelar('s', EstadoSolicitud.PENDIENTE);
    expect(r.confirmada, isFalse);
    expect(g.args, {'solicitud_id': 's', 'estado_esperado': 'PENDIENTE'});
    await g.dispose();
  });
  test('creación incierta bloquea reintento ciego y reconsulta', () async {
    final g = FakeGateway()
      ..failure = TimeoutException('lost')
      ..rows = [solicitudRow()];
    final r = SupabaseSolicitudRepository(g);
    await expectLater(
      r.crear([TipoMaterial.PAPEL], null, Ubicacion(direccion: 'C')),
      throwsA(isA<Fallo>()),
    );
    await expectLater(
      r.crear([TipoMaterial.PAPEL], null, Ubicacion(direccion: 'C')),
      throwsA(isA<Fallo>()),
    );
    expect(g.rpcs, 1);
    expect(await r.reconciliarCreacionNoConfirmada(), hasLength(1));
    expect(g.query!.filtros, {'ciudadano_uid': 'u'});
    await g.dispose();
  });
  test('lecturas y filtro material se delegan al servidor', () async {
    final g = FakeGateway()..rows = [solicitudRow()];
    final r = SupabaseSolicitudRepository(g);
    expect((await r.obtenerPorId('s')).id, 's');
    final sub = r
        .observarPorFiltro(EstadoSolicitud.PENDIENTE, TipoMaterial.PAPEL)
        .listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(g.query!.columnas, contains('!inner'));
    expect(g.query!.filtros['coincidencia.tipo_material'], 'PAPEL');
    await sub.cancel();
    await g.dispose();
  });
  test('fila invisible se reconcilia explícitamente sin polling', () async {
    final g = FakeGateway();
    final signal = StreamController<void>.broadcast();
    var rows = [1];
    final events = <List<int>>[];
    final sub = observarAutorizado(
      g,
      () async => rows,
      reconciliar: signal.stream,
    ).listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    rows = [];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, [
      [1],
    ]);
    signal.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events.last, isEmpty);
    await sub.cancel();
    expect(g.canceled, 1);
    await signal.close();
    await g.dispose();
  });
  test('reconexión provoca reconsulta', () async {
    final g = FakeGateway();
    var reads = 0;
    final sub = observarAutorizado(g, () async => [++reads]).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    g.changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reads, 2);
    await sub.cancel();
    await g.dispose();
  });
  test('cambio de sesión descarta respuesta en vuelo y cierra canal', () async {
    final g = FakeGateway();
    final pending = Completer<List<int>>();
    final events = <List<int>>[];
    final done = Completer<void>();
    observarAutorizado(
      g,
      () => pending.future,
    ).listen(events.add, onDone: done.complete);
    g.user = 'otro';
    g.sessions.add('otro');
    pending.complete([99]);
    await done.future.timeout(const Duration(seconds: 1));
    expect(events, [<int>[]]);
    expect(g.canceled, 1);
    await g.dispose();
  });
  test('logout vacía y termina suscripción', () async {
    final g = FakeGateway();
    final events = <List<int>>[];
    final done = Completer<void>();
    observarAutorizado(
      g,
      () async => [1],
    ).listen(events.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await g.salir();
    await done.future;
    expect(events.last, isEmpty);
    expect(g.canceled, 1);
    await g.dispose();
  });
}
