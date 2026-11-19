import 'dart:async';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

Fallo traducirError(Object e, {bool mutacion = false}) {
  if (e is Fallo) return e;
  if (e is PostgrestException) {
    if (['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(e.code))
      return const Fallo(TipoFallo.autorizacion, 'No autorizado');
    if ((e.code ?? '').startsWith('22') || (e.code ?? '').startsWith('23'))
      return const Fallo(TipoFallo.validacion, 'Datos inválidos o duplicados');
  }
  if (e is AuthException)
    return const Fallo(TipoFallo.autorizacion, 'Acceso rechazado');
  if (e is FunctionException) {
    final details = e.details;
    final code = details is Map ? details['codigo'] : null;
    if (code == 'RESULTADO_NO_CONFIRMADO' || code == 'COMPENSACION_PENDIENTE')
      return const Fallo(
        TipoFallo.noConfirmado,
        'Operación no confirmada; requiere reconciliación',
      );
    if (e.status == 401 || e.status == 403)
      return const Fallo(TipoFallo.autorizacion, 'No autorizado');
    if (e.status == 400 || e.status == 409)
      return const Fallo(TipoFallo.validacion, 'Datos inválidos o duplicados');
  }
  if (e is TimeoutException || e is http.ClientException)
    return Fallo(
      mutacion ? TipoFallo.noConfirmado : TipoFallo.conectividad,
      mutacion
          ? 'Resultado no confirmado; no reintentar automáticamente'
          : 'Sin conexión',
    );
  return const Fallo(TipoFallo.servicio, 'Servicio no disponible');
}

Future<T> proteger<T>(
  Future<T> Function() action, {
  bool mutacion = false,
}) async {
  try {
    return await action();
  } catch (e) {
    throw traducirError(e, mutacion: mutacion);
  }
}
