import 'models.dart';

abstract interface class UbicacionStrategy {
  Future<Ubicacion> obtenerUbicacion();
}

class DireccionManualStrategy implements UbicacionStrategy {
  final String direccionIngresada;
  const DireccionManualStrategy(this.direccionIngresada);
  @override
  Future<Ubicacion> obtenerUbicacion() async =>
      Ubicacion(direccion: direccionIngresada);
}

abstract interface class AuthRepository {
  Future<Usuario> registrarCiudadano(
    String nombre,
    String correo,
    String contrasena,
    bool aceptaPolitica,
  );
  Future<Usuario> iniciarSesion(String correo, String contrasena);
  Future<void> cerrarSesion();
  String? get uidActual;
  Stream<String?> get sesiones;
}

abstract interface class UsuarioRepository {
  Future<Usuario> obtenerActual();
  // Usuario.correo procede de Auth: no se consulta el correo de terceros desde clientes.
  Future<Usuario> obtenerPorUid(String uid);
}

abstract interface class SolicitudRepository {
  Future<Solicitud> crear(
    List<TipoMaterial> materiales,
    String? descripcion,
    Ubicacion ubicacion,
  );
  Future<Solicitud> obtenerPorId(String id);
  Future<ResultadoTransicion> asignar(String solicitudId, String recicladorId);
  Future<ResultadoTransicion> marcarRecolectada(String solicitudId);
  Future<ResultadoTransicion> cancelar(
    String solicitudId,
    EstadoSolicitud estadoEsperado,
  );
  Stream<List<Solicitud>> observarMisSolicitudes();
  Stream<List<Solicitud>> observarMisAsignaciones();
  Stream<List<Solicitud>> observarPorFiltro(
    EstadoSolicitud estado,
    TipoMaterial? material,
  );
  void reconciliarVistas();
  Future<List<Solicitud>> reconciliarCreacionNoConfirmada();
}

abstract interface class HistorialRepository {
  Future<List<HistorialEstado>> listarPorSolicitud(String solicitudId);
}

abstract interface class RecicladorRepository {
  Future<Reciclador> registrarConApp(
    String nombre,
    String documento,
    String? telefono,
    String correo,
    String contrasenaInicial,
  );
  Future<Reciclador> registrarSinApp(
    String nombre,
    String documento,
    String? telefono,
  );
  Future<void> actualizar(
    String id,
    String nombre,
    String documento,
    String? telefono,
  );
  Future<void> cambiarEstado(String id, EstadoReciclador estado);
  Future<List<Reciclador>> listar();
  Future<Reciclador> obtenerPorId(String id);
  Future<bool> existeDocumento(String documento);
}
