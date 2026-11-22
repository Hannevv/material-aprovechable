import 'dart:async';
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'session_controller.dart';

class MobileController extends SessionController {
  final SolicitudService solicitudes;
  final UbicacionStrategy gps;
  final String? politica;
  List<Solicitud> lista = [];
  bool cargandoLista = false, noConfirmado = false, reconciliado = false;
  StreamSubscription<List<Solicitud>>? _lista;
  MobileController(
    AuthService auth,
    this.solicitudes,
    this.gps, {
    this.politica,
  }) : super(auth, {Rol.CIUDADANO, Rol.RECICLADOR});
  bool get politicaDisponible => politica?.trim().isNotEmpty ?? false;
  @override
  void limpiarDatos() {
    unawaited(_lista?.cancel());
    _lista = null;
    lista = [];
    cargandoLista = false;
    noConfirmado = false;
    reconciliado = false;
  }

  @override
  Future<void> cargarDatos() async {
    final turno = generacion;
    await _lista?.cancel();
    if (cerrado || turno != generacion || usuario == null) return;
    lista = [];
    cargandoLista = true;
    final stream = usuario!.rol == Rol.CIUDADANO
        ? solicitudes.observarMisSolicitudes()
        : solicitudes.observarMisAsignaciones();
    _lista = stream.listen(
      (rows) {
        if (cerrado || turno != generacion) return;
        lista = rows;
        errorConexion = null;
        cargandoLista = false;
        notifyListeners();
      },
      onError: (Object e) {
        if (cerrado || turno != generacion) return;
        errorConexion = explicar(e);
        cargandoLista = false;
        notifyListeners();
      },
    );
  }

  Future<void> registrar(
    String nombre,
    String correo,
    String clave,
    bool acepta,
  ) => ejecutar(() async {
    exigir(
      politicaDisponible,
      'La política de tratamiento aún no está disponible',
    );
    exigir(acepta, 'Debes aceptar la política de tratamiento');
    final turno = generacion;
    final u = await auth.registrarCiudadano(
      nombre.trim(),
      correo.trim(),
      clave,
      acepta,
    );
    if (cerrado || turno != generacion) return;
    exigir(u.rol == Rol.CIUDADANO, 'Cuenta no habilitada');
    usuario = u;
    await cargarDatos();
  });
  Future<void> crear(
    List<TipoMaterial> materiales,
    String descripcion,
    bool usarGps,
    String direccion,
  ) => ejecutar(() async {
    exigir(usuario?.rol == Rol.CIUDADANO, 'Acceso no autorizado');
    exigir(
      !noConfirmado,
      'Revisa el resultado anterior antes de crear otra solicitud',
    );
    final turno = generacion;
    try {
      final creada = await solicitudes.registrarSolicitud(
        materiales,
        descripcion.isEmpty ? null : descripcion,
        usarGps ? gps : DireccionManualStrategy(direccion.trim()),
      );
      if (turno != generacion || cerrado) return;
      mensaje = 'Solicitud registrada: ${creada.id}';
      solicitudes.reconciliarVistas();
    } on Fallo catch (e) {
      if (turno != generacion || cerrado) return;
      if (e.tipo == TipoFallo.noConfirmado) {
        noConfirmado = true;
        reconciliado = false;
        mensaje =
            'Resultado no confirmado. Revisa tus solicitudes antes de reintentar.';
        await reconciliarAmbigua();
      }
      rethrow;
    }
  });
  Future<void> reconciliarAmbigua() async {
    final turno = generacion;
    try {
      final rows = await solicitudes.reconciliarCreacionNoConfirmada();
      if (cerrado || turno != generacion) return;
      lista = rows;
      reconciliado = true;
      error = null;
      notifyListeners();
    } catch (e) {
      if (cerrado || turno != generacion) return;
      error = explicar(e);
      reconciliado = false;
      notifyListeners();
    }
  }

  /// Solo desde la decisión explícita del usuario tras revisar la consulta autorizada.
  void resolverAmbigua() {
    if (!reconciliado) return;
    noConfirmado = false;
    mensaje =
        'Resultado revisado. Puedes registrar una nueva solicitud si corresponde.';
    notifyListeners();
  }

  Future<void> cancelar(Solicitud s) => ejecutar(() async {
    exigir(
      usuario?.rol == Rol.CIUDADANO &&
          s.estado == EstadoSolicitud.PENDIENTE &&
          s.ciudadanoId == usuario?.uid,
      'No puedes cancelar esta solicitud',
    );
    await _resultado(solicitudes.cancelarPendientePropia(s.id));
  });
  Future<void> recolectar(Solicitud s) => ejecutar(() async {
    exigir(
      usuario?.rol == Rol.RECICLADOR && s.estado == EstadoSolicitud.ASIGNADA,
      'No puedes cerrar esta solicitud',
    );
    await _resultado(solicitudes.marcarRecolectada(s.id));
  });
  Future<void> _resultado(Future<ResultadoTransicion> operacion) async {
    final turno = generacion;
    final r = await operacion;
    if (turno != generacion || cerrado) return;
    mensaje = r.confirmada
        ? 'Cambio confirmado'
        : 'La solicitud cambió a ${r.estadoActual.name}. Se actualizó la vista; no se repitió la operación.';
    solicitudes.reconciliarVistas();
  }

  Future<void> reentrar() async {
    if (await verificarSesion()) {
      solicitudes.reconciliarVistas();
    }
  }
}
