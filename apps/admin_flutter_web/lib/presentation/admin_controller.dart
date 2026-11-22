import 'dart:async';
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'session_controller.dart';

class AdminController extends SessionController {
  final SolicitudService solicitudes;
  final RecicladorService recicladores;
  EstadoSolicitud estado = EstadoSolicitud.PENDIENTE;
  TipoMaterial? material;
  List<Solicitud> lista = [];
  List<Reciclador> recicladoresLista = [];
  List<HistorialEstado> historial = [];
  String? historialId;
  bool cargandoLista = false;
  StreamSubscription<List<Solicitud>>? _lista;
  int _filtroVersion = 0, _historialVersion = 0;
  AdminController(AuthService auth, this.solicitudes, this.recicladores)
    : super(auth, {Rol.ADMIN});
  @override
  void limpiarDatos() {
    unawaited(_lista?.cancel());
    _lista = null;
    lista = [];
    recicladoresLista = [];
    historial = [];
    historialId = null;
    estado = EstadoSolicitud.PENDIENTE;
    material = null;
    cargandoLista = false;
    _filtroVersion++;
    _historialVersion++;
  }

  @override
  Future<void> cargarDatos() async {
    await observar();
    await cargarRecicladores();
  }

  Future<void> observar() async {
    final turno = generacion, version = ++_filtroVersion;
    lista = [];
    cargandoLista = true;
    notifyListeners();
    final anterior = _lista;
    _lista = null;
    if (anterior != null) unawaited(anterior.cancel());
    if (cerrado || turno != generacion || version != _filtroVersion) return;
    _lista = solicitudes
        .observarSolicitudes(estado, material)
        .listen(
          (rows) {
            if (cerrado || turno != generacion || version != _filtroVersion)
              return;
            lista = rows;
            errorConexion = null;
            cargandoLista = false;
            notifyListeners();
          },
          onError: (Object e) {
            if (cerrado || turno != generacion || version != _filtroVersion)
              return;
            errorConexion = explicar(e);
            cargandoLista = false;
            notifyListeners();
          },
        );
  }

  Future<void> filtrar(EstadoSolicitud e, TipoMaterial? m) async {
    estado = e;
    material = m;
    await observar();
  }

  Future<void> cargarRecicladores() async {
    if (usuario == null || cerrado) return;
    final turno = generacion;
    final rows = await recicladores.listar();
    if (cerrado || turno != generacion) return;
    recicladoresLista = rows;
    notifyListeners();
  }

  List<Reciclador> get asignables =>
      recicladoresLista.where((r) => r.esAsignable).toList();
  Future<void> asignar(Solicitud s, String id) => ejecutar(() async {
    exigir(
      s.estado == EstadoSolicitud.PENDIENTE,
      'Selecciona una solicitud pendiente',
    );
    exigir(
      asignables.any((r) => r.id == id),
      'Selecciona un reciclador activo',
    );
    await _resultado(solicitudes.asignar(s.id, id));
  });
  Future<void> cancelar(Solicitud s) => ejecutar(() async {
    exigir(
      s.estado == EstadoSolicitud.PENDIENTE ||
          s.estado == EstadoSolicitud.ASIGNADA,
      'La solicitud ya es final',
    );
    await _resultado(solicitudes.cancelarComoAdmin(s.id, s.estado));
  });
  Future<void> recolectar(Solicitud s) => ejecutar(() async {
    exigir(
      s.estado == EstadoSolicitud.ASIGNADA,
      'Selecciona una solicitud asignada',
    );
    await _resultado(solicitudes.marcarRecolectada(s.id));
  });
  Future<void> _resultado(Future<ResultadoTransicion> f) async {
    final turno = generacion;
    final r = await f;
    if (cerrado || turno != generacion) return;
    mensaje = r.confirmada
        ? 'Cambio confirmado'
        : 'Conflicto: el estado actual es ${r.estadoActual.name}. Revisa la vista actualizada.';
    solicitudes.reconciliarVistas();
  }

  Future<void> verHistorial(String id) => ejecutar(() async {
    historial = [];
    historialId = id;
    final turno = generacion, version = ++_historialVersion;
    final rows = await solicitudes.consultarHistorial(id);
    if (cerrado || turno != generacion || version != _historialVersion) return;
    historial = rows;
  });
  Future<void> guardarReciclador({
    Reciclador? original,
    required String nombre,
    required String documento,
    String? telefono,
    required ModalidadReciclador modalidad,
    String? correo,
    String? clave,
  }) => ejecutar(() async {
    final turno = generacion;
    if (original == null) {
      if (modalidad == ModalidadReciclador.CON_APP) {
        exigir(correo?.contains('@') ?? false, 'Correo inválido');
        exigir(
          (clave?.length ?? 0) >= 8,
          'La contraseña debe tener al menos 8 caracteres',
        );
      }
      await recicladores.registrar(
        nombre.trim(),
        documento.trim(),
        telefono,
        modalidad,
        correo: correo,
        contrasenaInicial: clave,
      );
    } else {
      await recicladores.editar(
        original.id,
        nombre.trim(),
        documento.trim(),
        telefono,
      );
    }
    if (cerrado || turno != generacion) return;
    await cargarRecicladores();
    if (cerrado || turno != generacion) return;
    mensaje = 'Reciclador guardado';
  });
  Future<void> cambiarActividad(Reciclador r) => ejecutar(() async {
    final turno = generacion;
    if (r.estado == EstadoReciclador.ACTIVO) {
      await recicladores.inactivar(r.id);
    } else {
      await recicladores.reactivar(r.id);
    }
    if (cerrado || turno != generacion) return;
    await cargarRecicladores();
    if (cerrado || turno != generacion) return;
    solicitudes.reconciliarVistas();
    mensaje = 'Estado actualizado';
  });
  Future<void> reentrar() async {
    if (await verificarSesion()) {
      solicitudes.reconciliarVistas();
      await ejecutar(cargarRecicladores);
    }
  }
}
