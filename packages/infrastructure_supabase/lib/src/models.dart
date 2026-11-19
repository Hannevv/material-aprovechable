import 'package:domain/domain.dart';

DateTime fecha(dynamic v) => DateTime.parse(v as String);
Usuario usuarioDe(Map<String, dynamic> m, String correo) => Usuario(
  uid: m['uid'],
  correo: correo,
  nombre: m['nombre'],
  rol: Rol.values.byName(m['rol']),
  fechaAceptacionPolitica: m['fecha_aceptacion_politica'] == null
      ? null
      : fecha(m['fecha_aceptacion_politica']),
);
Reciclador recicladorDe(Map<String, dynamic> m) => Reciclador(
  id: m['id'],
  nombre: m['nombre'],
  documento: m['documento'],
  usuarioUid: m['usuario_uid'],
  telefono: m['telefono'],
  modalidad: ModalidadReciclador.values.byName(m['modalidad']),
  estado: EstadoReciclador.values.byName(m['estado']),
);
Solicitud solicitudDe(Map<String, dynamic> m) => Solicitud(
  id: m['id'],
  ciudadanoId: m['ciudadano_uid'],
  materiales: (m['solicitud_materiales'] as List)
      .map((x) => TipoMaterial.values.byName(x['tipo_material']))
      .toList(),
  descripcionMaterial: m['descripcion_material'],
  ubicacion: Ubicacion(
    direccion: m['direccion'],
    latitud: (m['latitud'] as num?)?.toDouble(),
    longitud: (m['longitud'] as num?)?.toDouble(),
  ),
  estado: EstadoSolicitud.values.byName(m['estado']),
  recicladorId: m['reciclador_id'],
  fechaCreacion: fecha(m['fecha_creacion']),
  fechaAsignacion: m['fecha_asignacion'] == null
      ? null
      : fecha(m['fecha_asignacion']),
);
HistorialEstado historialDe(Map<String, dynamic> m) => HistorialEstado(
  id: m['id'],
  solicitudId: m['solicitud_id'],
  estadoAnterior: EstadoSolicitud.values.byName(m['estado_anterior']),
  estadoNuevo: EstadoSolicitud.values.byName(m['estado_nuevo']),
  fechaHora: fecha(m['fecha_hora']),
  actor: Actor(m['usuario_ejecutor_uid'], Rol.values.byName(m['rol_ejecutor'])),
  recicladorId: m['reciclador_id'],
);
ResultadoTransicion resultadoDe(Map<String, dynamic> m) => ResultadoTransicion(
  m['confirmada'],
  EstadoSolicitud.values.byName(m['estado_actual']),
  m['codigo'] ?? 'CONFIRMADA',
);
