import 'dart:async';
import 'gateway.dart';
import 'errors.dart';

// Una suscripción pertenece a una sola identidad. No reutiliza datos/canales al cambiar usuario.
Stream<List<T>> observarAutorizado<T>(
  Gateway gateway,
  Future<List<T>> Function() consultar, {
  Stream<void>? reconciliar,
}) {
  late StreamController<List<T>> out;
  StreamSubscription<void>? cambios;
  StreamSubscription<String?>? sesiones;
  StreamSubscription<void>? senales;
  final identidad = gateway.uid;
  bool activo = true, consultando = false, pendiente = false;
  Future<void> limpiar() async {
    activo = false;
    await cambios?.cancel();
    await sesiones?.cancel();
    await senales?.cancel();
  }

  Future<void> consultarAhora() async {
    if (!activo || gateway.uid != identidad) return;
    pendiente = true;
    if (consultando) return;
    consultando = true;
    while (pendiente && activo) {
      pendiente = false;
      try {
        final rows = await consultar();
        if (activo && gateway.uid == identidad)
          out.add(List.unmodifiable(rows));
      } catch (e, st) {
        if (activo && gateway.uid == identidad)
          out.addError(traducirError(e), st);
      }
    }
    consultando = false;
  }

  out = StreamController<List<T>>(
    onListen: () {
      if (identidad == null) {
        out.add([]);
        out.close();
        return;
      }
      sesiones = gateway.sesiones.listen((uid) {
        if (uid != identidad) {
          out.add([]);
          unawaited(limpiar());
          unawaited(out.close());
        } else {
          unawaited(consultarAhora());
        }
      });
      cambios = gateway.cambiosSolicitudes().listen(
        (_) {
          unawaited(consultarAhora());
        },
        onError: (Object e, StackTrace st) {
          if (activo) out.addError(traducirError(e), st);
        },
      );
      senales = reconciliar?.listen((_) {
        unawaited(consultarAhora());
      });
      unawaited(consultarAhora());
    },
    onCancel: limpiar,
  );
  return out.stream;
}
