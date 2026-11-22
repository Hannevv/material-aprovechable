import 'package:domain/domain.dart';

class AuthService {
  final AuthRepository auth;
  final UsuarioRepository usuarios;
  AuthService(this.auth, this.usuarios);
  Future<Usuario> registrarCiudadano(
    String nombre,
    String correo,
    String contrasena,
    bool aceptaPolitica,
  ) {
    exigir(aceptaPolitica, 'Debe aceptar la política');
    exigir(
      nombre.trim().isNotEmpty && contrasena.length >= 8,
      'Datos inválidos',
    );
    return auth.registrarCiudadano(nombre, correo, contrasena, aceptaPolitica);
  }

  Future<Usuario> iniciarSesion(String correo, String contrasena) =>
      auth.iniciarSesion(correo, contrasena);
  Future<void> cerrarSesion() => auth.cerrarSesion();
  Stream<String?> get sesiones => auth.sesiones;
  Future<Usuario> obtenerUsuarioActual() => usuarios.obtenerActual();
}

class SolicitudService {
  final SolicitudRepository solicitudes;
  final HistorialRepository historial;
  SolicitudService(this.solicitudes, this.historial);
  Future<Solicitud> registrarSolicitud(
    List<TipoMaterial> materiales,
    String? descripcion,
    UbicacionStrategy estrategia,
  ) async {
    exigir(materiales.isNotEmpty, 'Seleccione materiales');
    exigir(
      descripcion == null || descripcion.runes.length <= 250,
      'Descripción máxima 250 caracteres',
    );
    return solicitudes.crear(
      materiales,
      descripcion,
      await estrategia.obtenerUbicacion(),
    );
  }

  Future<ResultadoTransicion> cancelarPendientePropia(String id) =>
      solicitudes.cancelar(id, EstadoSolicitud.PENDIENTE);
  Future<ResultadoTransicion> cancelarComoAdmin(
    String id,
    EstadoSolicitud observado,
  ) => solicitudes.cancelar(id, observado);
  Future<ResultadoTransicion> asignar(String id, String reciclador) =>
      solicitudes.asignar(id, reciclador);
  Future<ResultadoTransicion> marcarRecolectada(String id) =>
      solicitudes.marcarRecolectada(id);
  Future<List<HistorialEstado>> consultarHistorial(String id) =>
      historial.listarPorSolicitud(id);
  Stream<List<Solicitud>> observarMisSolicitudes() =>
      solicitudes.observarMisSolicitudes();
  Stream<List<Solicitud>> observarMisAsignaciones() =>
      solicitudes.observarMisAsignaciones();
  Stream<List<Solicitud>> observarSolicitudes(
    EstadoSolicitud e,
    TipoMaterial? m,
  ) => solicitudes.observarPorFiltro(e, m);
  void reconciliarVistas() => solicitudes.reconciliarVistas();
  Future<List<Solicitud>> reconciliarCreacionNoConfirmada() =>
      solicitudes.reconciliarCreacionNoConfirmada();
}

class RecicladorService {
  final RecicladorRepository recicladores;
  RecicladorService(this.recicladores);
  Future<Reciclador> registrar(
    String nombre,
    String documento,
    String? telefono,
    ModalidadReciclador modalidad, {
    String? correo,
    String? contrasenaInicial,
  }) {
    exigir(
      nombre.trim().isNotEmpty && documento.trim().isNotEmpty,
      'Datos obligatorios',
    );
    if (modalidad == ModalidadReciclador.SIN_APP)
      return recicladores.registrarSinApp(nombre, documento, telefono);
    exigir(
      correo != null && contrasenaInicial != null,
      'Credenciales requeridas',
    );
    return recicladores.registrarConApp(
      nombre,
      documento,
      telefono,
      correo!,
      contrasenaInicial!,
    );
  }

  Future<void> editar(
    String id,
    String nombre,
    String documento,
    String? telefono,
  ) => recicladores.actualizar(id, nombre, documento, telefono);
  Future<void> inactivar(String id) =>
      recicladores.cambiarEstado(id, EstadoReciclador.INACTIVO);
  Future<void> reactivar(String id) =>
      recicladores.cambiarEstado(id, EstadoReciclador.ACTIVO);
  Future<List<Reciclador>> listar() => recicladores.listar();
}
