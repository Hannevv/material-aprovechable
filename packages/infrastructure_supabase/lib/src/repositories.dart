import 'dart:async';
import 'package:domain/domain.dart';
import 'gateway.dart';
import 'models.dart';
import 'errors.dart';
import 'observer.dart';

class SupabaseUsuarioRepository implements UsuarioRepository {
  final Gateway db;
  SupabaseUsuarioRepository(this.db);
  @override
  Future<Usuario> obtenerActual() async {
    final uid = db.uid;
    if (uid == null) throw const Fallo(TipoFallo.autorizacion, 'Sin sesión');
    return obtenerPorUid(uid);
  }

  @override
  Future<Usuario> obtenerPorUid(String uid) => proteger(() async {
    if (uid != db.uid)
      throw const Fallo(
        TipoFallo.autorizacion,
        'Correo de terceros no disponible',
      );
    final rows = await db.leer(Consulta('usuarios', filtros: {'uid': uid}));
    if (rows.isEmpty)
      throw const Fallo(TipoFallo.autorizacion, 'Perfil pendiente');
    final user = usuarioDe(rows.single, db.correo ?? '');
    if (user.rol == Rol.RECICLADOR) {
      final r = await db.leer(
        Consulta('recicladores', filtros: {'usuario_uid': uid}),
      );
      if (r.isEmpty || r.single['estado'] != 'ACTIVO')
        throw const Fallo(TipoFallo.autorizacion, 'Cuenta no habilitada');
    }
    return user;
  });
}

class SupabaseAuthRepository implements AuthRepository {
  final Gateway db;
  final UsuarioRepository usuarios;
  SupabaseAuthRepository(this.db, this.usuarios);
  @override
  String? get uidActual => db.uid;
  @override
  Stream<String?> get sesiones => db.sesiones;
  @override
  Future<Usuario> registrarCiudadano(
    String nombre,
    String correo,
    String clave,
    bool acepta,
  ) => proteger(() async {
    exigir(acepta, 'Aceptación requerida');
    // Si Auth ya confirmó y solo falló el perfil, no repetir signUp.
    if (db.uid == null) {
      await db.registrar(correo, clave);
    } else if (db.correo?.toLowerCase() != correo.toLowerCase()) {
      throw const Fallo(TipoFallo.autorizacion, 'Sesión distinta');
    }
    await db.rpc('crear_perfil_ciudadano', {
      'nombre': nombre,
      'fecha_aceptacion_politica': DateTime.now().toUtc().toIso8601String(),
    });
    return usuarios.obtenerActual();
  }, mutacion: true);
  @override
  Future<Usuario> iniciarSesion(String correo, String clave) =>
      proteger(() async {
        await db.ingresar(correo, clave);
        try {
          return await usuarios.obtenerActual();
        } catch (_) {
          await db.salir();
          rethrow;
        }
      });
  @override
  Future<void> cerrarSesion() => proteger(() => db.salir());
}

class SupabaseSolicitudRepository implements SolicitudRepository {
  final Gateway db;
  final StreamController<void> _reconciliaciones =
      StreamController<void>.broadcast();
  // El Composition Root/vista futura invoca al volver al foreground o reentrar.
  @override
  void reconciliarVistas() {
    if (!_reconciliaciones.isClosed) _reconciliaciones.add(null);
  }

  Future<void> dispose() => _reconciliaciones.close();
  String? _creacionNoConfirmadaUid;
  SupabaseSolicitudRepository(this.db);
  Future<List<Solicitud>> _listar({
    Map<String, Object> filtros = const {},
  }) async => (await db.leer(
    Consulta(
      'solicitudes',
      columnas: '*,solicitud_materiales(tipo_material)',
      filtros: filtros,
      orden: 'fecha_creacion',
      ascendente: false,
    ),
  )).map(solicitudDe).toList();
  @override
  Future<Solicitud> crear(List<TipoMaterial> m, String? d, Ubicacion u) async {
    if (_creacionNoConfirmadaUid == db.uid && db.uid != null)
      throw const Fallo(
        TipoFallo.noConfirmado,
        'Existe una creación no confirmada: reconciliar antes de continuar',
      );
    final uid = db.uid;
    try {
      final row = await proteger(
        () => db.rpc('crear_solicitud', {
          'materiales': m.map((v) => v.name).toList(),
          'descripcion': d,
          'direccion': u.direccion,
          'latitud': u.latitud,
          'longitud': u.longitud,
        }),
        mutacion: true,
      );
      // No depender de una segunda consulta para confirmar una creación ya confirmada.
      reconciliarVistas();
      return solicitudDe({
        ...row,
        'solicitud_materiales': m
            .toSet()
            .map((v) => {'tipo_material': v.name})
            .toList(),
      });
    } on Fallo catch (e) {
      if (e.tipo == TipoFallo.noConfirmado) _creacionNoConfirmadaUid = uid;
      rethrow;
    }
  }

  @override
  Future<List<Solicitud>>
  reconciliarCreacionNoConfirmada() => proteger(() async {
    final rows = await _listar(filtros: {'ciudadano_uid': db.uid ?? ''});
    // No liberar un reintento ambiguo: sin clave idempotente no existe prueba general de ausencia.
    // La vista puede mostrar la lista autorizada; resolver una operación ambigua exige revisión.
    return rows;
  });
  @override
  Future<Solicitud> obtenerPorId(String id) => proteger(() async {
    final rows = await _listar(filtros: {'id': id});
    if (rows.isEmpty)
      throw const Fallo(TipoFallo.autorizacion, 'No autorizado');
    return rows.single;
  });
  Future<ResultadoTransicion> _cambio(String n, Map<String, dynamic> a) =>
      proteger(() async {
        final resultado = resultadoDe(await db.rpc(n, a));
        reconciliarVistas();
        return resultado;
      }, mutacion: true);
  @override
  Future<ResultadoTransicion> asignar(String id, String rid) =>
      _cambio('asignar_solicitud', {'solicitud_id': id, 'reciclador_id': rid});
  @override
  Future<ResultadoTransicion> marcarRecolectada(String id) =>
      _cambio('marcar_recolectada', {'solicitud_id': id});
  @override
  Future<ResultadoTransicion> cancelar(String id, EstadoSolicitud e) => _cambio(
    'cancelar_solicitud',
    {'solicitud_id': id, 'estado_esperado': e.name},
  );
  @override
  Stream<List<Solicitud>> observarMisSolicitudes() => observarAutorizado(
    db,
    () => _listar(filtros: {'ciudadano_uid': db.uid ?? ''}),
    reconciliar: _reconciliaciones.stream,
  );
  @override
  Stream<List<Solicitud>> observarMisAsignaciones() => observarAutorizado(
    db,
    () => _listar(filtros: {'estado': 'ASIGNADA'}),
    reconciliar: _reconciliaciones.stream,
  );
  @override
  Stream<List<Solicitud>> observarPorFiltro(
    EstadoSolicitud e,
    TipoMaterial? m,
  ) => observarAutorizado(db, () async {
    // El filtro de material se aplica en el servidor mediante relación !inner.
    if (m == null) return _listar(filtros: {'estado': e.name});
    final rows = await db.leer(
      Consulta(
        'solicitudes',
        columnas:
            '*,solicitud_materiales(tipo_material),coincidencia:solicitud_materiales!inner(tipo_material)',
        filtros: {'estado': e.name, 'coincidencia.tipo_material': m.name},
        orden: 'fecha_creacion',
        ascendente: false,
      ),
    );
    return rows.map(solicitudDe).toList();
  }, reconciliar: _reconciliaciones.stream);
}

class SupabaseHistorialRepository implements HistorialRepository {
  final Gateway db;
  SupabaseHistorialRepository(this.db);
  @override
  Future<List<HistorialEstado>> listarPorSolicitud(String id) => proteger(
    () async => (await db.leer(
      Consulta(
        'historial_estados',
        filtros: {'solicitud_id': id},
        orden: 'fecha_hora',
      ),
    )).map(historialDe).toList(),
  );
}

class SupabaseRecicladorRepository implements RecicladorRepository {
  final Gateway db;
  SupabaseRecicladorRepository(this.db);
  @override
  Future<Reciclador> registrarConApp(
    String n,
    String d,
    String? t,
    String c,
    String p,
  ) => proteger(() async {
    final r = await db.edge('crear_reciclador_con_app', {
      'nombre': n,
      'documento': d,
      'telefono': t,
      'correo': c,
      'contrasena_inicial': p,
    });
    return recicladorDe(Map<String, dynamic>.from(r['reciclador']));
  }, mutacion: true);
  @override
  Future<Reciclador> registrarSinApp(String n, String d, String? t) => proteger(
    () async => recicladorDe(
      await db.rpc('crear_reciclador_sin_app', {
        'nombre': n,
        'documento': d,
        'telefono': t,
      }),
    ),
    mutacion: true,
  );
  @override
  Future<void> actualizar(String id, String n, String d, String? t) =>
      proteger(() async {
        await db.rpc('actualizar_reciclador', {
          'reciclador_id': id,
          'nombre': n,
          'documento': d,
          'telefono': t,
        });
      }, mutacion: true);
  @override
  Future<void> cambiarEstado(String id, EstadoReciclador e) =>
      proteger(() async {
        await db.rpc('cambiar_estado_reciclador', {
          'reciclador_id': id,
          'estado': e.name,
        });
      }, mutacion: true);
  @override
  Future<List<Reciclador>> listar() => proteger(
    () async => (await db.leer(
      const Consulta('recicladores', orden: 'nombre'),
    )).map(recicladorDe).toList(),
  );
  @override
  Future<Reciclador> obtenerPorId(String id) => proteger(() async {
    final rows = await db.leer(Consulta('recicladores', filtros: {'id': id}));
    if (rows.isEmpty)
      throw const Fallo(TipoFallo.autorizacion, 'No autorizado');
    return recicladorDe(rows.single);
  });
  @override
  Future<bool> existeDocumento(String d) => proteger(
    () async => (await db.leer(
      Consulta('recicladores', filtros: {'documento': d}),
    )).isNotEmpty,
  );
}
