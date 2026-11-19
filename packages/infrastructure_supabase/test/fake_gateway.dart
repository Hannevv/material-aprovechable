import 'dart:async';
import 'package:infrastructure_supabase/infrastructure_supabase.dart';

class FakeGateway implements Gateway {
  String? user = 'u';
  @override
  String? get uid => user;
  @override
  String? get correo => 'c@example.com';
  final sessions = StreamController<String?>.broadcast(sync: true);
  late final changes = StreamController<void>.broadcast(
    onCancel: () {
      canceled++;
    },
  );
  int canceled = 0, reads = 0, rpcs = 0;
  String? rpcName;
  Map<String, dynamic>? args;
  Consulta? query;
  Object? failure;
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> result = {};
  Future<List<Map<String, dynamic>>> Function()? reader;
  @override
  Stream<String?> get sesiones => sessions.stream;
  @override
  Future<List<Map<String, dynamic>>> leer(Consulta q) async {
    reads++;
    query = q;
    return reader == null ? rows : await reader!();
  }

  @override
  Future<Map<String, dynamic>> rpc(String n, Map<String, dynamic> a) async {
    rpcs++;
    rpcName = n;
    args = a;
    if (failure != null) throw failure!;
    return result;
  }

  @override
  Future<Map<String, dynamic>> edge(String n, Map<String, dynamic> a) =>
      rpc(n, a);
  @override
  Stream<void> cambiosSolicitudes() => changes.stream;
  @override
  Future<void> registrar(String c, String p) async {}
  @override
  Future<void> ingresar(String c, String p) async {}
  @override
  Future<void> salir() async {
    user = null;
    sessions.add(null);
  }

  Future<void> dispose() async {
    await changes.close();
    await sessions.close();
  }
}

Map<String, dynamic> solicitudRow({String estado = 'PENDIENTE'}) => {
  'id': 's',
  'ciudadano_uid': 'u',
  'descripcion_material': null,
  'direccion': 'Calle',
  'latitud': null,
  'longitud': null,
  'estado': estado,
  'reciclador_id': estado == 'PENDIENTE' ? null : 'r',
  'fecha_creacion': '2026-01-01T00:00:00Z',
  'fecha_asignacion': estado == 'PENDIENTE' ? null : '2026-01-02T00:00:00Z',
  'solicitud_materiales': [
    {'tipo_material': 'PAPEL'},
  ],
};
