import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:application/application.dart';
import 'package:domain/domain.dart';

/// Estado de presentación; autorización efectiva permanece en el backend.
abstract class SessionController extends ChangeNotifier {
  final AuthService auth;
  final Set<Rol> roles;
  Usuario? usuario;
  bool ocupado = false;
  String? error, mensaje, errorConexion;
  bool cerrado = false;
  int generacion = 0;
  StreamSubscription<String?>? _sesion;
  SessionController(this.auth, this.roles) {
    _sesion = auth.sesiones.listen((uid) {
      if (cerrado) return;
      if (usuario != null && uid != usuario!.uid) {
        limpiarSesion();
        notifyListeners();
      }
    });
  }
  void limpiarDatos();
  Future<void> cargarDatos();
  void limpiarSesion() {
    generacion++;
    usuario = null;
    ocupado = false;
    error = null;
    errorConexion = null;
    mensaje = null;
    limpiarDatos();
  }

  String explicar(Object e) => e is Fallo
      ? e.mensaje
      : 'No se pudo completar la operación. Inténtalo de nuevo.';
  Future<void> entrar(String correo, String clave) async {
    if (ocupado) return;
    await ejecutar(() async {
      exigir(
        correo.contains('@') && clave.isNotEmpty,
        'Ingresa correo y contraseña',
      );
      final turno = generacion;
      final u = await auth.iniciarSesion(correo.trim(), clave);
      if (cerrado || turno != generacion) return;
      if (!roles.contains(u.rol)) {
        await auth.cerrarSesion();
        throw const Fallo(
          TipoFallo.autorizacion,
          'Esta cuenta no tiene acceso a esta aplicación',
        );
      }
      usuario = u;
      await cargarDatos();
    });
  }

  Future<void> salir() async {
    if (cerrado) return;
    limpiarSesion();
    notifyListeners();
    try {
      await auth.cerrarSesion();
    } catch (e) {
      if (!cerrado) {
        error = explicar(e);
        notifyListeners();
      }
    }
  }

  Future<void> ejecutar(Future<void> Function() accion) async {
    if (ocupado || cerrado) return;
    final turno = generacion;
    ocupado = true;
    error = null;
    mensaje = null;
    notifyListeners();
    try {
      await accion();
    } catch (e) {
      if (turno == generacion) error = explicar(e);
    } finally {
      if (!cerrado && turno == generacion) {
        ocupado = false;
        notifyListeners();
      }
    }
  }

  Future<bool> verificarSesion() async {
    final uid = usuario?.uid;
    if (uid == null) return false;
    try {
      final actual = await auth.obtenerUsuarioActual();
      if (cerrado || usuario?.uid != uid) return false;
      if (!roles.contains(actual.rol))
        throw const Fallo(TipoFallo.autorizacion, 'Cuenta no habilitada');
      usuario = actual;
      return true;
    } on Fallo catch (e) {
      if (cerrado || usuario?.uid != uid) return false;
      if (e.tipo == TipoFallo.autorizacion) {
        await salir();
        if (!cerrado) {
          error = e.mensaje;
          notifyListeners();
        }
        return false;
      }
      if (!cerrado) {
        error = e.mensaje;
        notifyListeners();
      }
      return false;
    } catch (e) {
      if (!cerrado) {
        error = explicar(e);
        notifyListeners();
      }
      return false;
    }
  }

  @override
  void dispose() {
    cerrado = true;
    generacion++;
    limpiarDatos();
    unawaited(_sesion?.cancel());
    super.dispose();
  }
}
