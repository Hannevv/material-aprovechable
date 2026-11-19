import 'models.dart';

sealed class EstadoSolicitudState {
  const EstadoSolicitudState();
  EstadoSolicitud get nombre;
  EstadoSolicitud asignar() => _invalida();
  EstadoSolicitud recolectar() => _invalida();
  EstadoSolicitud cancelar() => _invalida();
  Never _invalida() =>
      throw const Fallo(TipoFallo.conflicto, 'Transición no permitida');
}

final class EstadoPendiente extends EstadoSolicitudState {
  const EstadoPendiente();
  @override
  EstadoSolicitud get nombre => EstadoSolicitud.PENDIENTE;
  @override
  EstadoSolicitud asignar() => EstadoSolicitud.ASIGNADA;
  @override
  EstadoSolicitud cancelar() => EstadoSolicitud.CANCELADA;
}

final class EstadoAsignada extends EstadoSolicitudState {
  const EstadoAsignada();
  @override
  EstadoSolicitud get nombre => EstadoSolicitud.ASIGNADA;
  @override
  EstadoSolicitud recolectar() => EstadoSolicitud.RECOLECTADA;
  @override
  EstadoSolicitud cancelar() => EstadoSolicitud.CANCELADA;
}

final class EstadoRecolectada extends EstadoSolicitudState {
  const EstadoRecolectada();
  @override
  EstadoSolicitud get nombre => EstadoSolicitud.RECOLECTADA;
}

final class EstadoCancelada extends EstadoSolicitudState {
  const EstadoCancelada();
  @override
  EstadoSolicitud get nombre => EstadoSolicitud.CANCELADA;
}

EstadoSolicitudState estadoDe(EstadoSolicitud e) => switch (e) {
  EstadoSolicitud.PENDIENTE => const EstadoPendiente(),
  EstadoSolicitud.ASIGNADA => const EstadoAsignada(),
  EstadoSolicitud.RECOLECTADA => const EstadoRecolectada(),
  EstadoSolicitud.CANCELADA => const EstadoCancelada(),
};
