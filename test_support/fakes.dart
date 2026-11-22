import 'dart:async';
import 'package:application/application.dart';
import 'package:domain/domain.dart';

Usuario usuario(Rol rol, {String id = 'u'}) => Usuario(
  uid: id,
  correo: 'test@example.com',
  rol: rol,
  nombre: rol == Rol.RECICLADOR ? null : 'Prueba',
  fechaAceptacionPolitica: rol == Rol.CIUDADANO ? DateTime.utc(2026) : null,
);
Solicitud solicitud({
  String id = 's',
  EstadoSolicitud estado = EstadoSolicitud.PENDIENTE,
  bool gps = false,
  List<TipoMaterial> materiales = const [
    TipoMaterial.PAPEL,
    TipoMaterial.METAL,
  ],
}) => Solicitud(
  id: id,
  ciudadanoId: 'u',
  materiales: materiales,
  ubicacion: gps
      ? Ubicacion(latitud: 2.4, longitud: -76.6)
      : Ubicacion(direccion: 'Calle 1'),
  fechaCreacion: DateTime.utc(2026),
  estado: estado,
  recicladorId: estado == EstadoSolicitud.PENDIENTE ? null : 'r',
  fechaAsignacion: estado == EstadoSolicitud.PENDIENTE
      ? null
      : DateTime.utc(2026, 1, 2),
);
Reciclador reciclador({
  String id = 'r',
  ModalidadReciclador modalidad = ModalidadReciclador.CON_APP,
  EstadoReciclador estado = EstadoReciclador.ACTIVO,
}) => Reciclador(
  id: id,
  nombre: 'Reciclador',
  documento: id,
  modalidad: modalidad,
  estado: estado,
  usuarioUid: modalidad == ModalidadReciclador.CON_APP ? 'u' : null,
);

class FakeAuth implements AuthRepository, UsuarioRepository {
  Rol rol = Rol.CIUDADANO;
  Completer<Usuario>? lecturaPendiente;
  Usuario? actual;
  bool inactivo = false;
  int registros = 0, salidas = 0;
  final events = StreamController<String?>.broadcast(sync: true);
  @override
  String? get uidActual => actual?.uid;
  @override
  Stream<String?> get sesiones => events.stream;
  @override
  Future<Usuario> iniciarSesion(String c, String p) async {
    actual = usuario(rol);
    events.add(actual!.uid);
    if (inactivo) {
      actual = null;
      events.add(null);
      throw const Fallo(TipoFallo.autorizacion, 'Cuenta no habilitada');
    }
    return actual!;
  }

  @override
  Future<Usuario> registrarCiudadano(
    String n,
    String c,
    String p,
    bool a,
  ) async {
    exigir(a && p.length >= 8, 'Registro inválido');
    registros++;
    actual = usuario(Rol.CIUDADANO);
    events.add(actual!.uid);
    return actual!;
  }

  @override
  Future<void> cerrarSesion() async {
    salidas++;
    actual = null;
    events.add(null);
  }

  @override
  Future<Usuario> obtenerActual() async {
    if (lecturaPendiente != null) return lecturaPendiente!.future;
    if (inactivo || actual == null)
      throw const Fallo(TipoFallo.autorizacion, 'Cuenta no habilitada');
    return actual!;
  }

  @override
  Future<Usuario> obtenerPorUid(String uid) => obtenerActual();
  void cambiar(String uid) {
    actual = usuario(rol, id: uid);
    events.add(uid);
  }

  Future<void> dispose() => events.close();
}

class FakeSolicitudes implements SolicitudRepository, HistorialRepository {
  List<Solicitud> rows = [];
  int creaciones = 0,
      reconciliaciones = 0,
      cancelaciones = 0,
      recolecciones = 0,
      asignaciones = 0,
      canalesCancelados = 0;
  bool ambiguo = false, consultaFalla = false, conflicto = false;
  EstadoSolicitud? filtro, esperado;
  TipoMaterial? material;
  Ubicacion? ubicacion;
  List<TipoMaterial>? recibidos;
  String? descripcion, recicladorId;
  late final cambios = StreamController<List<Solicitud>>.broadcast(
    onCancel: () {
      canalesCancelados++;
    },
  );
  List<Solicitud> filtrar() => rows
      .where(
        (s) =>
            (filtro == null || s.estado == filtro) &&
            (material == null || s.materiales.contains(material)),
      )
      .toList();
  Stream<List<Solicitud>> observar() {
    late StreamController<List<Solicitud>> out;
    StreamSubscription<List<Solicitud>>? inner;
    out = StreamController<List<Solicitud>>(
      onListen: () {
        out.add(filtrar());
        inner = cambios.stream.listen(out.add);
      },
      onCancel: () async {
        await inner?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<List<Solicitud>> observarMisSolicitudes() {
    filtro = null;
    return observar();
  }

  @override
  Stream<List<Solicitud>> observarMisAsignaciones() {
    filtro = EstadoSolicitud.ASIGNADA;
    return observar();
  }

  @override
  Stream<List<Solicitud>> observarPorFiltro(
    EstadoSolicitud e,
    TipoMaterial? m,
  ) {
    filtro = e;
    material = m;
    return observar();
  }

  void emitir() {
    cambios.add(filtrar());
  }

  @override
  void reconciliarVistas() {
    reconciliaciones++;
    emitir();
  }

  @override
  Future<List<Solicitud>> reconciliarCreacionNoConfirmada() async {
    reconciliaciones++;
    if (consultaFalla)
      throw const Fallo(TipoFallo.conectividad, 'Sin conexión');
    return rows;
  }

  @override
  Future<Solicitud> crear(List<TipoMaterial> m, String? d, Ubicacion u) async {
    creaciones++;
    recibidos = m;
    descripcion = d;
    ubicacion = u;
    if (ambiguo)
      throw const Fallo(TipoFallo.noConfirmado, 'Resultado no confirmado');
    final s = Solicitud(
      id: 'nueva',
      ciudadanoId: 'u',
      materiales: m,
      descripcionMaterial: d,
      ubicacion: u,
      fechaCreacion: DateTime.now(),
      estado: EstadoSolicitud.PENDIENTE,
    );
    rows = [s, ...rows];
    emitir();
    return s;
  }

  ResultadoTransicion resultado(EstadoSolicitud destino) => ResultadoTransicion(
    !conflicto,
    conflicto ? EstadoSolicitud.ASIGNADA : destino,
    conflicto ? 'CONFLICTO_ESTADO' : 'CONFIRMADA',
  );
  @override
  Future<ResultadoTransicion> cancelar(String id, EstadoSolicitud e) async {
    cancelaciones++;
    esperado = e;
    return resultado(EstadoSolicitud.CANCELADA);
  }

  @override
  Future<ResultadoTransicion> marcarRecolectada(String id) async {
    recolecciones++;
    return resultado(EstadoSolicitud.RECOLECTADA);
  }

  @override
  Future<ResultadoTransicion> asignar(String id, String rid) async {
    asignaciones++;
    recicladorId = rid;
    return resultado(EstadoSolicitud.ASIGNADA);
  }

  @override
  Future<Solicitud> obtenerPorId(String id) async =>
      rows.firstWhere((s) => s.id == id);
  @override
  Future<List<HistorialEstado>> listarPorSolicitud(String id) async => [
    HistorialEstado(
      id: 'h',
      solicitudId: id,
      estadoAnterior: EstadoSolicitud.PENDIENTE,
      estadoNuevo: EstadoSolicitud.ASIGNADA,
      fechaHora: DateTime.utc(2026),
      actor: const Actor('admin', Rol.ADMIN),
      recicladorId: 'r',
    ),
  ];
  Future<void> dispose() => cambios.close();
}

class FakeRecicladores implements RecicladorRepository {
  List<Reciclador> rows = [
    reciclador(),
    reciclador(id: 'sin', modalidad: ModalidadReciclador.SIN_APP),
    reciclador(id: 'inactivo', estado: EstadoReciclador.INACTIVO),
  ];
  ModalidadReciclador? creada;
  EstadoReciclador? estado;
  String? editado;
  bool falla = false;
  @override
  Future<List<Reciclador>> listar() async => rows;
  @override
  Future<Reciclador> registrarConApp(
    String n,
    String d,
    String? t,
    String c,
    String p,
  ) async {
    if (falla)
      throw const Fallo(TipoFallo.validacion, 'Datos inválidos o duplicados');
    creada = ModalidadReciclador.CON_APP;
    return reciclador();
  }

  @override
  Future<Reciclador> registrarSinApp(String n, String d, String? t) async {
    creada = ModalidadReciclador.SIN_APP;
    return reciclador(modalidad: creada!);
  }

  @override
  Future<void> actualizar(String id, String n, String d, String? t) async {
    editado = id;
  }

  @override
  Future<void> cambiarEstado(String id, EstadoReciclador e) async {
    estado = e;
  }

  @override
  Future<bool> existeDocumento(String d) async =>
      rows.any((r) => r.documento == d);
  @override
  Future<Reciclador> obtenerPorId(String id) async =>
      rows.firstWhere((r) => r.id == id);
}

class FakeGps implements UbicacionStrategy {
  int llamadas = 0;
  @override
  Future<Ubicacion> obtenerUbicacion() async {
    llamadas++;
    return Ubicacion(latitud: 2.4, longitud: -76.6);
  }
}

class Fixture {
  final auth = FakeAuth(),
      solicitudes = FakeSolicitudes(),
      recicladores = FakeRecicladores(),
      gps = FakeGps();
  AuthService get authService => AuthService(auth, auth);
  SolicitudService get solicitudService =>
      SolicitudService(solicitudes, solicitudes);
  RecicladorService get recicladorService => RecicladorService(recicladores);
  Future<void> dispose() async {
    await auth.dispose();
    await solicitudes.dispose();
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
