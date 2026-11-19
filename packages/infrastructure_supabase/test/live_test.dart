import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:domain/domain.dart';
import 'package:infrastructure_supabase/infrastructure_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

Future<void> until(bool Function() f) async {
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (!f()) {
    if (DateTime.now().isAfter(end))
      throw TimeoutException('Expected condition did not occur');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  final path = Platform.environment['LIVE_FIXTURES'];
  test(
    'Postgres Changes real, RLS, filtros y reconciliación',
    () async {
      final data = jsonDecode(File(path!).readAsStringSync()) as Map;
      final clients = <String, SupabaseClient>{},
          repos = <String, SupabaseSolicitudRepository>{};
      final subs = <StreamSubscription>[];
      final raw = <String, List<PostgresChangePayload>>{},
          views = <String, List<Solicitud>>{};
      try {
        for (final role in ['admin', 'ciudadano', 'reciclador', 'otro']) {
          final client = SupabaseClient(data['url'], data['anon']);
          clients[role] = client;
          await client.auth.signInWithPassword(
            email: data[role]['email'],
            password: data[role]['password'],
          );
          repos[role] = SupabaseSolicitudRepository(SupabaseGateway(client));
          raw[role] = [];
          final ready = Completer<void>();
          client
              .channel('raw-$role')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'solicitudes',
                callback: raw[role]!.add,
              )
              .subscribe((s, e) {
                if (s == RealtimeSubscribeStatus.subscribed &&
                    !ready.isCompleted)
                  ready.complete();
                if (e != null && !ready.isCompleted) ready.completeError(e);
              });
          await ready.future.timeout(const Duration(seconds: 15));
        }
        subs.add(
          repos['admin']!
              .observarPorFiltro(EstadoSolicitud.PENDIENTE, TipoMaterial.PAPEL)
              .listen(
                (r) => views['admin'] = r,
                onError: (Object e) {
                  expect(e, isA<Fallo>());
                },
              ),
        );
        subs.add(
          repos['ciudadano']!.observarMisSolicitudes().listen(
            (r) => views['ciudadano'] = r,
            onError: (Object e) {
              expect(e, isA<Fallo>());
            },
          ),
        );
        subs.add(
          repos['reciclador']!.observarMisAsignaciones().listen(
            (r) => views['reciclador'] = r,
            onError: (Object e) {
              expect(e, isA<Fallo>());
            },
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        final s = await repos['ciudadano']!.crear(
          [TipoMaterial.PAPEL, TipoMaterial.METAL],
          null,
          Ubicacion(direccion: 'Integración'),
        );
        await until(() => raw['admin']!.any((p) => p.newRecord['id'] == s.id));
        await until(() => views['admin']?.any((r) => r.id == s.id) ?? false);
        expect(raw['otro']!.any((p) => p.newRecord['id'] == s.id), isFalse);
        await repos['admin']!.asignar(s.id, data['reciclador']['id']);
        await until(
          () => raw['ciudadano']!.any(
            (p) =>
                p.newRecord['id'] == s.id &&
                p.newRecord['estado'] == 'ASIGNADA',
          ),
        );
        await until(
          () => raw['reciclador']!.any((p) => p.newRecord['id'] == s.id),
        );
        await until(
          () => views['reciclador']?.any((r) => r.id == s.id) ?? false,
        );
        await until(() => !(views['admin']?.any((r) => r.id == s.id) ?? true));
        await repos['admin']!.cancelar(s.id, EstadoSolicitud.ASIGNADA);
        // El evento final no es visible por RLS. Foreground/reentrada dispara SELECT autorizado.
        repos['reciclador']!.reconciliarVistas();
        await until(
          () => !(views['reciclador']?.any((r) => r.id == s.id) ?? true),
        );
        expect(
          await clients['reciclador']!
              .from('solicitudes')
              .select()
              .eq('id', s.id),
          isEmpty,
        );
        expect(
          raw['reciclador']!.any(
            (p) =>
                p.newRecord['id'] == s.id &&
                p.newRecord['estado'] == 'CANCELADA',
          ),
          isFalse,
        );
        await http.post(Uri.parse('${data['url']}/__test/realtime/pause'));
        final second = await repos['ciudadano']!.crear(
          [TipoMaterial.PAPEL],
          null,
          Ubicacion(direccion: 'Reconexión'),
        );
        await http.post(Uri.parse('${data['url']}/__test/realtime/resume'));
        await until(
          () => views['admin']?.any((r) => r.id == second.id) ?? false,
        );
        await clients['reciclador']!.auth.signOut();
        await until(() => views['reciclador']?.isEmpty ?? false);
        await clients['reciclador']!.auth.signInWithPassword(
          email: data['otro']['email'],
          password: data['otro']['password'],
        );
        expect(views['reciclador'], isEmpty);
      } finally {
        for (final s in subs) {
          await s.cancel();
        }
        for (final r in repos.values) {
          await r.dispose();
        }
        for (final c in clients.values) {
          await c.dispose();
        }
      }
    },
    skip: path == null
        ? 'Requires LIVE_FIXTURES for isolated real services'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
