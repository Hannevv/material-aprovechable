import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure_supabase/infrastructure_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:material_mobile/presentation/mobile_controller.dart';
import '../../admin_flutter_web/lib/presentation/admin_controller.dart';
import '../../../test_support/fakes.dart' show FakeGps;

Future<void> until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!condition()) {
    if (DateTime.now().isAfter(end))
      throw TimeoutException('Condición de integración no alcanzada');
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

class Runtime {
  final SupabaseClient client;
  late final Gateway gateway;
  late final SupabaseSolicitudRepository repo;
  late final AuthService auth;
  late final SolicitudService solicitudes;
  late final RecicladorService recicladores;
  Runtime(Map data, {bool perderRespuesta = false})
    : client = SupabaseClient(data['url'], data['anon']) {
    gateway = perderRespuesta
        ? RespuestaPerdida(SupabaseGateway(client))
        : SupabaseGateway(client);
    repo = SupabaseSolicitudRepository(gateway);
    final u = SupabaseUsuarioRepository(gateway);
    auth = AuthService(SupabaseAuthRepository(gateway, u), u);
    solicitudes = SolicitudService(repo, SupabaseHistorialRepository(gateway));
    recicladores = RecicladorService(SupabaseRecicladorRepository(gateway));
  }
  MobileController mobile() => MobileController(auth, solicitudes, FakeGps());
  AdminController admin() => AdminController(auth, solicitudes, recicladores);
  Future<void> dispose() async {
    await repo.dispose();
    await client.dispose();
  }
}

/// Simula solo perder la respuesta después de un commit REAL, nunca falsifica datos de la BD.
class RespuestaPerdida implements Gateway {
  final Gateway delegate;
  bool perder = true;
  RespuestaPerdida(this.delegate);
  @override
  String? get uid => delegate.uid;
  @override
  String? get correo => delegate.correo;
  @override
  Stream<String?> get sesiones => delegate.sesiones;
  @override
  Future<List<Map<String, dynamic>>> leer(Consulta q) => delegate.leer(q);
  @override
  Future<Map<String, dynamic>> rpc(String n, Map<String, dynamic> a) async {
    final r = await delegate.rpc(n, a);
    if (n == 'crear_solicitud' && perder) {
      perder = false;
      throw TimeoutException('Respuesta descartada por prueba');
    }
    return r;
  }

  @override
  Future<Map<String, dynamic>> edge(String n, Map<String, dynamic> a) =>
      delegate.edge(n, a);
  @override
  Future<void> registrar(String c, String p) => delegate.registrar(c, p);
  @override
  Future<void> ingresar(String c, String p) => delegate.ingresar(c, p);
  @override
  Future<void> salir() => delegate.salir();
  @override
  Stream<void> cambiosSolicitudes() => delegate.cambiosSolicitudes();
}

void main() {
  final path = Platform.environment['LIVE_FIXTURES'];
  test(
    'controladores móvil/admin contra Auth RPC RLS Edge y Realtime reales',
    () async {
      final d = jsonDecode(File(path!).readAsStringSync()) as Map;
      final a = Runtime(d),
          a2 = Runtime(d),
          cit = Runtime(d),
          rec = Runtime(d),
          extr = Runtime(d);
      final admin = a.admin(),
          admin2 = a2.admin(),
          ciudadano = cit.mobile(),
          reciclador = rec.mobile(),
          ajeno = extr.mobile();
      Future<void> login(dynamic c, String role) =>
          c.entrar(d[role]['email'], d[role]['password']);
      try {
        await login(admin, 'admin');
        await login(admin2, 'admin');
        await login(ciudadano, 'ciudadano');
        await login(reciclador, 'reciclador');
        expect(admin.usuario?.rol, Rol.ADMIN);
        expect(ciudadano.usuario?.rol, Rol.CIUDADANO);
        expect(reciclador.usuario?.rol, Rol.RECICLADOR);
        await Future<void>.delayed(const Duration(seconds: 2));
        final marca = 'UI-${DateTime.now().microsecondsSinceEpoch}';
        await ciudadano.crear(
          [TipoMaterial.PAPEL, TipoMaterial.METAL],
          marca,
          false,
          'Dirección integración',
        );
        expect(ciudadano.error, isNull);
        await until(
          () => ciudadano.lista.any((s) => s.descripcionMaterial == marca),
        );
        final s = ciudadano.lista.firstWhere(
          (s) => s.descripcionMaterial == marca,
        );
        await until(() => admin.lista.any((r) => r.id == s.id));
        await Future.wait([
          admin.asignar(s, d['reciclador']['id']),
          admin2.asignar(s, d['reciclador']['id']),
        ]);
        expect(
          [
            admin.mensaje,
            admin2.mensaje,
          ].where((m) => m == 'Cambio confirmado'),
          hasLength(1),
        );
        expect(
          [
            admin.mensaje,
            admin2.mensaje,
          ].where((m) => m?.contains('Conflicto') ?? false),
          hasLength(1),
        );
        await until(() => reciclador.lista.any((r) => r.id == s.id));
        await admin.cancelar(s);
        expect(
          admin.mensaje,
          contains('Conflicto'),
        ); // snapshot PENDIENTE ya obsoleto
        await until(
          () => ciudadano.lista.any(
            (r) => r.id == s.id && r.estado == EstadoSolicitud.ASIGNADA,
          ),
        );
        await reciclador.recolectar(
          reciclador.lista.firstWhere((r) => r.id == s.id),
        );
        expect(reciclador.error, isNull);
        await until(() => !reciclador.lista.any((r) => r.id == s.id));
        await until(
          () => ciudadano.lista.any(
            (r) => r.id == s.id && r.estado == EstadoSolicitud.RECOLECTADA,
          ),
        );
        await admin.verHistorial(s.id);
        expect(admin.historial.map((h) => h.estadoNuevo), [
          EstadoSolicitud.ASIGNADA,
          EstadoSolicitud.RECOLECTADA,
        ]);
        final nuevo = 'uiflow-${DateTime.now().microsecondsSinceEpoch}';
        await admin.guardarReciclador(
          nombre: 'Prueba UI',
          documento: nuevo,
          modalidad: ModalidadReciclador.CON_APP,
          correo: '$nuevo@example.com',
          clave: 'Local-password-123',
        );
        expect(admin.error, isNull);
        final r2 = admin.recicladoresLista.firstWhere(
          (r) => r.documento == nuevo,
        );
        await ajeno.entrar('$nuevo@example.com', 'Local-password-123');
        expect(ajeno.usuario?.rol, Rol.RECICLADOR);
        await ciudadano.crear([TipoMaterial.VIDRIO], nuevo, true, '');
        await until(
          () => ciudadano.lista.any((r) => r.descripcionMaterial == nuevo),
        );
        final otra = ciudadano.lista.firstWhere(
          (r) => r.descripcionMaterial == nuevo,
        );
        await admin.asignar(otra, r2.id);
        await until(() => ajeno.lista.any((r) => r.id == otra.id));
        expect(reciclador.lista.any((r) => r.id == otra.id), isFalse);
        await reciclador.recolectar(
          ajeno.lista.firstWhere((r) => r.id == otra.id),
        );
        expect(reciclador.error, contains('autorizado'));
        final asignada = ajeno.lista.firstWhere((r) => r.id == otra.id);
        await admin.cancelar(asignada);
        await ajeno.reentrar();
        await until(() => !ajeno.lista.any((r) => r.id == otra.id));
        await admin.cambiarActividad(r2);
        await ajeno.reentrar();
        expect(ajeno.usuario, isNull);
        expect(ajeno.lista, isEmpty);
        await ajeno.entrar('$nuevo@example.com', 'Local-password-123');
        expect(ajeno.usuario, isNull);
        expect(ajeno.error, isNotNull);
        await admin.guardarReciclador(
          nombre: 'Duplicado',
          documento: nuevo,
          modalidad: ModalidadReciclador.CON_APP,
          correo: 'otro-$nuevo@example.com',
          clave: 'Local-password-123',
        );
        expect(admin.error, contains('duplicados'));
        final http = HttpClient();
        try {
          final pause = await http.postUrl(
            Uri.parse('${d['url']}/__test/realtime/pause'),
          );
          await (await pause.close()).drain<void>();
          final reconexion =
              'reconexion-${DateTime.now().microsecondsSinceEpoch}';
          await ciudadano.crear(
            [TipoMaterial.PAPEL],
            reconexion,
            false,
            'Calle reconexión',
          );
          final resume = await http.postUrl(
            Uri.parse('${d['url']}/__test/realtime/resume'),
          );
          await (await resume.close()).drain<void>();
          await until(
            () => admin.lista.any((s) => s.descripcionMaterial == reconexion),
          );
          expect(admin.errorConexion, isNull);
        } finally {
          http.close();
        }
        await ciudadano.salir();
        expect(ciudadano.lista, isEmpty);
        await login(ciudadano, 'ciudadano');
        await until(() => ciudadano.lista.any((r) => r.id == s.id));
        expect(
          ciudadano.lista.every((r) => r.ciudadanoId == ciudadano.usuario!.uid),
          isTrue,
        );
      } finally {
        for (final c in [admin, admin2, ciudadano, reciclador, ajeno]) {
          c.dispose();
        }
        for (final r in [a, a2, cit, rec, extr]) {
          await r.dispose();
        }
      }
    },
    skip: path == null
        ? 'Requiere LIVE_FIXTURES y servicios locales reales'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'respuesta perdida después de commit real exige reconciliación y revisión',
    () async {
      final d = jsonDecode(File(path!).readAsStringSync()) as Map;
      final r = Runtime(d, perderRespuesta: true);
      final c = r.mobile();
      try {
        await c.entrar(d['ciudadano']['email'], d['ciudadano']['password']);
        final marca = 'ambigua-${DateTime.now().microsecondsSinceEpoch}';
        await c.crear([TipoMaterial.CARTON], marca, false, 'Calle integración');
        expect(c.noConfirmado, isTrue);
        expect(c.reconciliado, isTrue);
        expect(
          c.lista.where((s) => s.descripcionMaterial == marca),
          hasLength(1),
        );
        await c.crear([TipoMaterial.CARTON], marca, false, 'Calle integración');
        expect(
          c.lista.where((s) => s.descripcionMaterial == marca),
          hasLength(1),
        );
        c.resolverAmbigua();
        expect(
          c.noConfirmado,
          isFalse,
        ); // usuario encontró la solicitud: no vuelve a enviarla
      } finally {
        c.dispose();
        await r.dispose();
      }
    },
    skip: path == null
        ? 'Requiere LIVE_FIXTURES y servicios locales reales'
        : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
