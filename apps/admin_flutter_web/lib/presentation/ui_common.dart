import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:domain/domain.dart';
import 'session_controller.dart';

class MapConfig {
  final String url, atribucion, userAgent;
  const MapConfig(this.url, this.atribucion, this.userAgent);
}

String fecha(DateTime d) => d.toLocal().toString().substring(0, 16);
String materiales(Solicitud s) => s.materiales
    .map(
      (m) => switch (m) {
        TipoMaterial.PAPEL => 'Papel',
        TipoMaterial.CARTON => 'Cartón',
        TipoMaterial.PLASTICO => 'Plástico',
        TipoMaterial.VIDRIO => 'Vidrio',
        TipoMaterial.METAL => 'Metal',
      },
    )
    .join(', ');
Future<bool> confirmar(
  BuildContext context,
  String titulo,
  String texto,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;

class Avisos extends StatelessWidget {
  final SessionController controller;
  const Avisos(this.controller, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.ocupado) const LinearProgressIndicator(),
      if (controller.errorConexion != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(controller.errorConexion!),
        ),
      if (controller.error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            semanticsLabel: 'Error: ${controller.error}',
          ),
        ),
      if (controller.mensaje != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(controller.mensaje!, semanticsLabel: controller.mensaje),
        ),
    ],
  );
}

class LocationCard extends StatelessWidget {
  final Ubicacion ubicacion;
  final MapConfig config;
  final TileProvider? tileProvider;
  const LocationCard(
    this.ubicacion,
    this.config, {
    super.key,
    this.tileProvider,
  });
  @override
  Widget build(BuildContext context) {
    if (!ubicacion.tieneCoordenadas)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Dirección: ${ubicacion.direccion}'),
      );
    final point = LatLng(ubicacion.latitud!, ubicacion.longitud!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Coordenadas: ${ubicacion.latitud}, ${ubicacion.longitud}'),
        if (config.url.isNotEmpty && config.atribucion.isNotEmpty) ...[
          SizedBox(
            height: 220,
            child: FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 15),
              children: [
                TileLayer(
                  urlTemplate: config.url,
                  tileProvider: tileProvider,
                  userAgentPackageName: config.userAgent,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(config.atribucion, style: Theme.of(context).textTheme.bodySmall),
        ] else
          const Text(
            'Mapa no disponible: falta configurar el proveedor y su atribución.',
          ),
      ],
    );
  }
}

class AccessPanel extends StatefulWidget {
  final SessionController controller;
  final String titulo;
  final String? politica;
  final Future<void> Function(String, String, String, bool)? registrar;
  const AccessPanel({
    super.key,
    required this.controller,
    required this.titulo,
    this.politica,
    this.registrar,
  });
  @override
  State<AccessPanel> createState() => _AccessPanelState();
}

class _AccessPanelState extends State<AccessPanel> {
  final form = GlobalKey<FormState>();
  final nombre = TextEditingController(),
      correo = TextEditingController(),
      clave = TextEditingController();
  bool registro = false, acepta = false;
  @override
  void dispose() {
    nombre.dispose();
    correo.dispose();
    clave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final disponible = widget.politica?.trim().isNotEmpty ?? false;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.recycling, size: 64),
                const SizedBox(height: 16),
                Text(
                  widget.titulo,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  registro
                      ? 'Crea tu cuenta ciudadana'
                      : 'Ingresa con tu cuenta',
                ),
                const SizedBox(height: 16),
                Avisos(c),
                Form(
                  key: form,
                  child: Column(
                    children: [
                      if (registro)
                        TextFormField(
                          controller: nombre,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                          ),
                          validator: (v) => v?.trim().isEmpty ?? true
                              ? 'Ingresa tu nombre'
                              : null,
                        ),
                      TextFormField(
                        controller: correo,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Correo'),
                        validator: (v) => v?.contains('@') ?? false
                            ? null
                            : 'Ingresa un correo válido',
                      ),
                      TextFormField(
                        controller: clave,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                        ),
                        validator: (v) => (v?.length ?? 0) < (registro ? 8 : 1)
                            ? (registro
                                  ? 'Mínimo 8 caracteres'
                                  : 'Ingresa tu contraseña')
                            : null,
                      ),
                      if (registro) ...[
                        TextButton(
                          onPressed: disponible
                              ? () => showDialog<void>(
                                  context: context,
                                  builder: (d) => AlertDialog(
                                    title: const Text(
                                      'Política de tratamiento de datos',
                                    ),
                                    content: SingleChildScrollView(
                                      child: Text(widget.politica!),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(d),
                                        child: const Text('Cerrar'),
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                          child: const Text('Leer política de tratamiento'),
                        ),
                        if (!disponible)
                          const Text(
                            'El registro estará disponible cuando la organización suministre la política de tratamiento.',
                          ),
                        CheckboxListTile(
                          value: acepta,
                          onChanged: disponible
                              ? (v) => setState(() => acepta = v ?? false)
                              : null,
                          title: const Text(
                            'He leído y acepto la política de tratamiento',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed:
                            c.ocupado || (registro && (!disponible || !acepta))
                            ? null
                            : () async {
                                if (!form.currentState!.validate()) return;
                                if (registro) {
                                  await widget.registrar!(
                                    nombre.text,
                                    correo.text,
                                    clave.text,
                                    acepta,
                                  );
                                } else {
                                  await c.entrar(correo.text, clave.text);
                                }
                              },
                        child: Text(registro ? 'Crear cuenta' : 'Ingresar'),
                      ),
                      if (widget.registrar != null)
                        TextButton(
                          onPressed: c.ocupado
                              ? null
                              : () => setState(() {
                                  registro = !registro;
                                  clave.clear();
                                  acepta = false;
                                }),
                          child: Text(
                            registro
                                ? 'Ya tengo cuenta'
                                : 'Registrarme como ciudadano',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
