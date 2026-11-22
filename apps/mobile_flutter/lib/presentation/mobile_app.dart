import 'dart:async';
import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'mobile_controller.dart';
import 'ui_common.dart';

class MobileApp extends StatefulWidget {
  final MobileController controller;
  final MapConfig maps;
  const MobileApp({super.key, required this.controller, required this.maps});
  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      unawaited(widget.controller.reentrar());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => MaterialApp(
      key: ValueKey(widget.controller.usuario?.uid ?? 'sin-sesion'),
      debugShowCheckedModeBanner: false,
      title: 'Material aprovechable',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: widget.controller.usuario == null
          ? AccessPanel(
              controller: widget.controller,
              titulo: 'Material aprovechable',
              politica: widget.controller.politica,
              registrar: widget.controller.registrar,
            )
          : _Home(
              key: ValueKey(widget.controller.usuario!.uid),
              controller: widget.controller,
              maps: widget.maps,
            ),
    ),
  );
}

class _Home extends StatefulWidget {
  final MobileController controller;
  final MapConfig maps;
  const _Home({super.key, required this.controller, required this.maps});
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int pagina = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ciudadano = c.usuario!.rol == Rol.CIUDADANO;
    return Scaffold(
      appBar: AppBar(
        title: Text(ciudadano ? 'Mis solicitudes' : 'Mis recolecciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: c.reentrar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: c.salir,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Avisos(c),
          if (c.noConfirmado)
            MaterialBanner(
              content: Text(
                c.reconciliado
                    ? 'Consulta actualizada. Revisa si tu solicitud aparece antes de enviar otra.'
                    : 'Resultado no confirmado. No vuelvas a enviar hasta consultar tus solicitudes.',
              ),
              actions: [
                TextButton(
                  onPressed: c.reconciliarAmbigua,
                  child: const Text('Consultar solicitudes'),
                ),
                if (c.reconciliado)
                  TextButton(
                    onPressed: () async {
                      if (await confirmar(
                        context,
                        'Revisar resultado',
                        '¿Revisaste las solicitudes y resolviste si el registro anterior existe? Solo envía otro si corresponde.',
                      )) {
                        c.resolverAmbigua();
                      }
                    },
                    child: const Text('Ya revisé el resultado'),
                  ),
              ],
            ),
          Expanded(
            child: pagina == 1 && ciudadano
                ? _Crear(controller: c)
                : RefreshIndicator(
                    onRefresh: c.reentrar,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (c.cargandoLista)
                          const Center(child: CircularProgressIndicator())
                        else if (c.lista.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No hay solicitudes para mostrar.'),
                          ),
                        for (final s in c.lista)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    materiales(s),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text('Solicitud ${s.id}'),
                                  Text('Estado: ${s.estado.name}'),
                                  Text('Creada: ${fecha(s.fechaCreacion)}'),
                                  if (s.descripcionMaterial?.isNotEmpty ??
                                      false)
                                    Text(s.descripcionMaterial!),
                                  if (!ciudadano) ...[
                                    Text(
                                      'Asignada: ${fecha(s.fechaAsignacion!)}',
                                    ),
                                    LocationCard(s.ubicacion, widget.maps),
                                  ],
                                  if (ciudadano &&
                                      s.estado == EstadoSolicitud.PENDIENTE)
                                    TextButton(
                                      onPressed: c.ocupado
                                          ? null
                                          : () async {
                                              if (await confirmar(
                                                context,
                                                'Cancelar solicitud',
                                                '¿Deseas cancelar esta solicitud pendiente?',
                                              ))
                                                await c.cancelar(s);
                                            },
                                      child: const Text('Cancelar solicitud'),
                                    ),
                                  if (!ciudadano)
                                    FilledButton(
                                      onPressed: c.ocupado
                                          ? null
                                          : () async {
                                              if (await confirmar(
                                                context,
                                                'Confirmar recolección',
                                                '¿Ya recolectaste los materiales de esta solicitud?',
                                              ))
                                                await c.recolectar(s);
                                            },
                                      child: const Text('Marcar Recolectada'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: ciudadano
          ? NavigationBar(
              selectedIndex: pagina,
              onDestinationSelected: (i) {
                setState(() => pagina = i);
                if (i == 0) unawaited(c.reentrar());
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.list),
                  label: 'Mis solicitudes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add),
                  label: 'Nueva solicitud',
                ),
              ],
            )
          : null,
    );
  }
}

class _Crear extends StatefulWidget {
  final MobileController controller;
  const _Crear({required this.controller});
  @override
  State<_Crear> createState() => _CrearState();
}

class _CrearState extends State<_Crear> {
  final form = GlobalKey<FormState>(),
      descripcion = TextEditingController(),
      direccion = TextEditingController();
  final seleccion = <TipoMaterial>{};
  bool gps = true;
  @override
  void dispose() {
    descripcion.dispose();
    direccion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Nueva solicitud',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text('Selecciona uno o varios materiales'),
        Wrap(
          spacing: 8,
          children: [
            for (final m in TipoMaterial.values)
              FilterChip(
                label: Text(switch (m) {
                  TipoMaterial.PAPEL => 'Papel',
                  TipoMaterial.CARTON => 'Cartón',
                  TipoMaterial.PLASTICO => 'Plástico',
                  TipoMaterial.VIDRIO => 'Vidrio',
                  TipoMaterial.METAL => 'Metal',
                }),
                selected: seleccion.contains(m),
                onSelected: (v) => setState(() {
                  v ? seleccion.add(m) : seleccion.remove(m);
                }),
              ),
          ],
        ),
        Form(
          key: form,
          child: Column(
            children: [
              TextFormField(
                controller: descripcion,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional, máximo 250 caracteres)',
                ),
                validator: (v) => (v?.runes.length ?? 0) > 250
                    ? 'Máximo 250 caracteres'
                    : null,
              ),
              SwitchListTile(
                title: const Text('Usar ubicación GPS'),
                subtitle: Text(
                  gps
                      ? 'Se solicitará permiso para obtener coordenadas'
                      : 'Se guardará solo la dirección escrita',
                ),
                value: gps,
                onChanged: (v) => setState(() => gps = v),
              ),
              if (!gps)
                TextFormField(
                  controller: direccion,
                  decoration: const InputDecoration(
                    labelText: 'Dirección manual',
                  ),
                  validator: (v) =>
                      v?.trim().isEmpty ?? true ? 'Ingresa la dirección' : null,
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: c.ocupado || c.noConfirmado
                    ? null
                    : () async {
                        if (form.currentState!.validate())
                          await c.crear(
                            seleccion.toList(),
                            descripcion.text,
                            gps,
                            direccion.text,
                          );
                      },
                child: const Text('Registrar solicitud'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
