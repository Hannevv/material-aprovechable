import 'package:domain/domain.dart';
import 'package:infrastructure_supabase/infrastructure_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'fake_gateway.dart';

void main() {
  test('perfil actual obtiene correo de Auth y rechaza terceros', () async {
    final g = FakeGateway()
      ..rows = [
        {
          'uid': 'u',
          'nombre': 'N',
          'rol': 'ADMIN',
          'fecha_aceptacion_politica': null,
        },
      ];
    final r = SupabaseUsuarioRepository(g);
    expect((await r.obtenerActual()).correo, g.correo);
    await expectLater(r.obtenerPorUid('otro'), throwsA(isA<Fallo>()));
    await g.dispose();
  });
  test('login de reciclador inactivo cierra sesión', () async {
    final g = FakeGateway();
    g.reader = () async => g.query!.tabla == 'usuarios'
        ? [
            {'uid': 'u', 'rol': 'RECICLADOR', 'nombre': null},
          ]
        : [
            {'estado': 'INACTIVO'},
          ];
    await expectLater(
      SupabaseAuthRepository(
        g,
        SupabaseUsuarioRepository(g),
      ).iniciarSesion('c', 'p'),
      throwsA(isA<Fallo>()),
    );
    expect(g.uid, isNull);
    await g.dispose();
  });
  test('registro conserva aceptación en contrato y no envía rol', () async {
    final g = FakeGateway()
      ..rows = [
        {
          'uid': 'u',
          'nombre': 'N',
          'rol': 'CIUDADANO',
          'fecha_aceptacion_politica': '2026-01-01T00:00:00Z',
        },
      ];
    final a = SupabaseAuthRepository(g, SupabaseUsuarioRepository(g));
    await a.registrarCiudadano('N', g.correo!, 'Password123', true);
    expect(g.rpcName, 'crear_perfil_ciudadano');
    expect(
      g.args!.keys,
      unorderedEquals(['nombre', 'fecha_aceptacion_politica']),
    );
    await g.dispose();
  });
  test('alta CON_APP usa Edge y gestión usa RPC', () async {
    final g = FakeGateway()
      ..result = {
        'reciclador': {
          'id': 'r',
          'nombre': 'N',
          'documento': 'D',
          'modalidad': 'CON_APP',
          'estado': 'ACTIVO',
          'usuario_uid': 'u',
        },
      };
    final r = SupabaseRecicladorRepository(g);
    expect(
      (await r.registrarConApp('N', 'D', null, 'c', 'p')).tieneCuentaAcceso,
      isTrue,
    );
    expect(g.rpcName, 'crear_reciclador_con_app');
    expect(g.args!.containsKey('rol'), isFalse);
    await r.cambiarEstado('r', EstadoReciclador.INACTIVO);
    expect(g.rpcName, 'cambiar_estado_reciclador');
    await g.dispose();
  });
  test('historial consulta solo solicitud y orden cronológico', () async {
    final g = FakeGateway();
    expect(
      await SupabaseHistorialRepository(g).listarPorSolicitud('s'),
      isEmpty,
    );
    expect(g.query!.filtros, {'solicitud_id': 's'});
    expect(g.query!.orden, 'fecha_hora');
    await g.dispose();
  });
  test('errores Edge distinguen rechazo de resultado incierto', () {
    expect(
      traducirError(
        const FunctionException(
          status: 403,
          details: {'codigo': 'NO_AUTORIZADO'},
        ),
      ).tipo,
      TipoFallo.autorizacion,
    );
    expect(
      traducirError(
        const FunctionException(
          status: 503,
          details: {'codigo': 'RESULTADO_NO_CONFIRMADO'},
        ),
      ).tipo,
      TipoFallo.noConfirmado,
    );
    expect(
      traducirError(
        const FunctionException(status: 409, details: {'codigo': 'DUPLICADO'}),
      ).tipo,
      TipoFallo.validacion,
    );
  });
}
