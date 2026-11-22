import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:application/application.dart';
import 'package:infrastructure_supabase/infrastructure_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:infrastructure_mobile/infrastructure_mobile.dart';
import '../presentation/mobile_app.dart';
import '../presentation/mobile_controller.dart';
import '../presentation/ui_common.dart';

Future<void> iniciar() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Falta configurar la conexión de la aplicación. Contacta al administrador.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  final config =
      jsonDecode(await rootBundle.loadString('assets/config.json'))
          as Map<String, dynamic>;
  final client = SupabaseClient(
    url,
    key,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  final gateway = SupabaseGateway(client);
  final usuarios = SupabaseUsuarioRepository(gateway);
  final auth = AuthService(SupabaseAuthRepository(gateway, usuarios), usuarios);
  final repo = SupabaseSolicitudRepository(gateway);
  final solicitudes = SolicitudService(
    repo,
    SupabaseHistorialRepository(gateway),
  );
  final controller = MobileController(
    auth,
    solicitudes,
    GeolocalizacionStrategy(),
    politica: config['politica'] as String?,
  );
  runApp(
    _Runtime(
      client: client,
      repo: repo,
      controller: controller,
      maps: MapConfig(
        config['tiles_url'] as String? ?? '',
        config['tiles_atribucion'] as String? ?? '',
        config['tiles_user_agent'] as String? ??
            'co.popayan.material_aprovechable',
      ),
    ),
  );
}

class _Runtime extends StatefulWidget {
  final SupabaseClient client;
  final SupabaseSolicitudRepository repo;
  final MobileController controller;
  final MapConfig maps;
  const _Runtime({
    required this.client,
    required this.repo,
    required this.controller,
    required this.maps,
  });
  @override
  State<_Runtime> createState() => _RuntimeState();
}

class _RuntimeState extends State<_Runtime> {
  @override
  void dispose() {
    widget.controller.dispose();
    unawaited(widget.repo.dispose());
    unawaited(widget.client.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MobileApp(controller: widget.controller, maps: widget.maps);
}
