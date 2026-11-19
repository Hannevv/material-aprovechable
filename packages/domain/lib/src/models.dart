import 'state.dart';

// Canonical wire values shared with PostgreSQL.
// ignore_for_file: constant_identifier_names
enum Rol { CIUDADANO, RECICLADOR, ADMIN }

enum ModalidadReciclador { CON_APP, SIN_APP }

enum EstadoReciclador { ACTIVO, INACTIVO }

enum EstadoSolicitud { PENDIENTE, ASIGNADA, RECOLECTADA, CANCELADA }

enum TipoMaterial { PAPEL, CARTON, PLASTICO, VIDRIO, METAL }

enum TipoFallo {
  autorizacion,
  conflicto,
  validacion,
  conectividad,
  noConfirmado,
  servicio,
}

class Fallo implements Exception {
  final TipoFallo tipo;
  final String mensaje;
  const Fallo(this.tipo, this.mensaje);
  @override
  String toString() => mensaje;
}

void exigir(bool condicion, String mensaje) {
  if (!condicion) throw Fallo(TipoFallo.validacion, mensaje);
}

class Usuario {
  final String uid, correo;
  final String? nombre;
  final Rol rol;
  final DateTime? fechaAceptacionPolitica;
  Usuario({
    required this.uid,
    required this.correo,
    required this.rol,
    this.nombre,
    this.fechaAceptacionPolitica,
  }) {
    exigir(
      rol == Rol.RECICLADOR || (nombre?.trim().isNotEmpty ?? false),
      'Nombre requerido',
    );
    exigir(
      rol != Rol.CIUDADANO || fechaAceptacionPolitica != null,
      'Aceptación requerida',
    );
  }
}

class Reciclador {
  final String id, nombre, documento;
  final String? usuarioUid, telefono;
  final ModalidadReciclador modalidad;
  final EstadoReciclador estado;
  Reciclador({
    required this.id,
    required this.nombre,
    required this.documento,
    required this.modalidad,
    required this.estado,
    this.usuarioUid,
    this.telefono,
  }) {
    exigir(
      nombre.trim().isNotEmpty && documento.trim().isNotEmpty,
      'Datos obligatorios',
    );
    exigir(
      (modalidad == ModalidadReciclador.CON_APP) == (usuarioUid != null),
      'Cuenta incompatible con modalidad',
    );
  }
  bool get esAsignable => estado == EstadoReciclador.ACTIVO;
  bool get tieneCuentaAcceso => usuarioUid != null;
}

class Ubicacion {
  final double? latitud, longitud;
  final String? direccion;
  Ubicacion({this.latitud, this.longitud, this.direccion}) {
    exigir(esValida, 'Ubicación inválida');
  }
  bool get tieneCoordenadas => latitud != null && longitud != null;
  bool get esValida =>
      (direccion != null &&
          direccion!.trim().isNotEmpty &&
          latitud == null &&
          longitud == null) ||
      (direccion == null &&
          tieneCoordenadas &&
          latitud!.isFinite &&
          longitud!.isFinite &&
          latitud! >= -90 &&
          latitud! <= 90 &&
          longitud! >= -180 &&
          longitud! <= 180);
}

class Actor {
  final String usuarioId;
  final Rol rol;
  const Actor(this.usuarioId, this.rol);
}

class ResultadoTransicion {
  final bool confirmada;
  final EstadoSolicitud estadoActual;
  final String mensaje;
  const ResultadoTransicion(this.confirmada, this.estadoActual, this.mensaje);
}

class HistorialEstado {
  final String id, solicitudId;
  final EstadoSolicitud estadoAnterior, estadoNuevo;
  final DateTime fechaHora;
  final Actor actor;
  final String? recicladorId;
  const HistorialEstado({
    required this.id,
    required this.solicitudId,
    required this.estadoAnterior,
    required this.estadoNuevo,
    required this.fechaHora,
    required this.actor,
    this.recicladorId,
  });
}

class Solicitud {
  final String id, ciudadanoId;
  final List<TipoMaterial> materiales;
  final String? descripcionMaterial;
  final Ubicacion ubicacion;
  final String? recicladorId;
  final DateTime fechaCreacion;
  final DateTime? fechaAsignacion;
  final EstadoSolicitudState estadoActual;
  Solicitud({
    required this.id,
    required this.ciudadanoId,
    required List<TipoMaterial> materiales,
    required this.ubicacion,
    required this.fechaCreacion,
    required EstadoSolicitud estado,
    this.descripcionMaterial,
    this.recicladorId,
    this.fechaAsignacion,
  }) : materiales = List.unmodifiable(materiales.toSet()),
       estadoActual = estadoDe(estado) {
    exigir(materiales.isNotEmpty, 'Seleccione materiales');
    exigir(
      descripcionMaterial == null || descripcionMaterial!.runes.length <= 250,
      'Descripción máxima 250 caracteres',
    );
    final sin = recicladorId == null && fechaAsignacion == null;
    final con = recicladorId != null && fechaAsignacion != null;
    exigir(switch (estado) {
      EstadoSolicitud.PENDIENTE => sin,
      EstadoSolicitud.ASIGNADA || EstadoSolicitud.RECOLECTADA => con,
      EstadoSolicitud.CANCELADA => sin || con,
    }, 'Asignación incoherente');
  }
  EstadoSolicitud get estado => estadoActual.nombre;
  // Predicción local inmutable; persistir siempre por Repository/RPC y aceptar la respuesta del servidor.
  Solicitud asignar(String reciclador, DateTime fecha) =>
      _copiar(estadoActual.asignar(), reciclador, fecha);
  Solicitud recolectar() =>
      _copiar(estadoActual.recolectar(), recicladorId, fechaAsignacion);
  Solicitud cancelar() =>
      _copiar(estadoActual.cancelar(), recicladorId, fechaAsignacion);
  Solicitud _copiar(EstadoSolicitud e, String? r, DateTime? f) => Solicitud(
    id: id,
    ciudadanoId: ciudadanoId,
    materiales: materiales,
    ubicacion: ubicacion,
    fechaCreacion: fechaCreacion,
    estado: e,
    descripcionMaterial: descripcionMaterial,
    recicladorId: r,
    fechaAsignacion: f,
  );
}
