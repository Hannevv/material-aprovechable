import 'dart:async';
import 'package:supabase/supabase.dart';

class Consulta {
  final String tabla, columnas;
  final Map<String, Object> filtros;
  final String? orden;
  final bool ascendente;
  const Consulta(
    this.tabla, {
    this.columnas = '*',
    this.filtros = const {},
    this.orden,
    this.ascendente = true,
  });
}

abstract interface class Gateway {
  String? get uid;
  String? get correo;
  Stream<String?> get sesiones;
  Future<List<Map<String, dynamic>>> leer(Consulta consulta);
  Future<Map<String, dynamic>> rpc(String nombre, Map<String, dynamic> args);
  Future<Map<String, dynamic>> edge(String nombre, Map<String, dynamic> args);
  Future<void> registrar(String correo, String clave);
  Future<void> ingresar(String correo, String clave);
  Future<void> salir();
  Stream<void> cambiosSolicitudes();
}

class SupabaseGateway implements Gateway {
  final SupabaseClient client;
  SupabaseGateway(this.client);
  @override
  String? get uid => client.auth.currentUser?.id;
  @override
  String? get correo => client.auth.currentUser?.email;
  @override
  Stream<String?> get sesiones =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  @override
  Future<List<Map<String, dynamic>>> leer(Consulta q) async {
    var query = client.from(q.tabla).select(q.columnas);
    for (final entry in q.filtros.entries) {
      query = query.eq(entry.key, entry.value);
    }
    if (q.orden != null)
      return await query.order(q.orden!, ascending: q.ascendente);
    return await query;
  }

  @override
  Future<Map<String, dynamic>> rpc(String n, Map<String, dynamic> a) async =>
      Map<String, dynamic>.from(await client.rpc(n, params: a));
  @override
  Future<Map<String, dynamic>> edge(String n, Map<String, dynamic> a) async =>
      Map<String, dynamic>.from(
        (await client.functions.invoke(n, body: a)).data,
      );
  @override
  Future<void> registrar(String email, String clave) async {
    await client.auth.signUp(email: email, password: clave);
  }

  @override
  Future<void> ingresar(String email, String clave) async {
    await client.auth.signInWithPassword(email: email, password: clave);
  }

  @override
  Future<void> salir() async {
    await client.auth.signOut();
  }

  @override
  Stream<void> cambiosSolicitudes() {
    late StreamController<void> output;
    RealtimeChannel? channel;
    output = StreamController<void>(
      onListen: () {
        channel = client.channel(
          'solicitudes-${DateTime.now().microsecondsSinceEpoch}',
        );
        channel!
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'solicitudes',
              callback: (_) {
                if (!output.isClosed) output.add(null);
              },
            )
            .subscribe((status, error) {
              if (error != null && !output.isClosed) output.addError(error);
              if (status == RealtimeSubscribeStatus.subscribed &&
                  !output.isClosed)
                output.add(null); // También al reconectar.
            });
      },
      onCancel: () async {
        if (channel != null) await client.removeChannel(channel!);
      },
    );
    return output.stream;
  }
}
