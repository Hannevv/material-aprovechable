import 'dart:async';
import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'admin_controller.dart';
import 'ui_common.dart';

class AdminApp extends StatefulWidget {
  final AdminController controller;
  final MapConfig maps;
  const AdminApp({super.key, required this.controller, required this.maps});
  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> with WidgetsBindingObserver {
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
      title: 'Administración · Material aprovechable',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: widget.controller.usuario == null
          ? AccessPanel(controller: widget.controller, titulo: 'Administración')
          : _Panel(
              key: ValueKey(widget.controller.usuario!.uid),
              controller: widget.controller,
              maps: widget.maps,
            ),
    ),
  );
}

class _Panel extends StatefulWidget {
  final AdminController controller;
  final MapConfig maps;
  const _Panel({super.key, required this.controller, required this.maps});
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  int pagina = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Solicitudes'),
                      icon: Icon(Icons.list),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Recicladores'),
                      icon: Icon(Icons.people),
                    ),
                  ],
                  selected: {pagina},
                  onSelectionChanged: (v) {
                    setState(() => pagina = v.first);
                    unawaited(c.reentrar());
                  },
                ),
              ),
              Avisos(c),
              Expanded(
                child: pagina == 0
                    ? _Solicitudes(controller: c, maps: widget.maps)
                    : _Recicladores(controller: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Solicitudes extends StatelessWidget {
  final AdminController controller;
  final MapConfig maps;
  const _Solicitudes({required this.controller, required this.maps});
  Future<void> asignar(BuildContext context, Solicitud s) async {
    final c = controller;
    await c.ejecutar(c.cargarRecicladores);
    if (!context.mounted || c.usuario == null || c.error != null) return;
    String? elegido;
    final id = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Asignar solicitud'),
          content: SizedBox(
            width: 400,
            child: c.asignables.isEmpty
                ? const Text('No hay recicladores activos.')
                : DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Reciclador activo',
                    ),
                    items: [
                      for (final r in c.asignables)
                        DropdownMenuItem(
                          value: r.id,
                          child: Text(
                            '${r.nombre} · ${r.modalidad.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => set(() => elegido = v),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: elegido == null
                  ? null
                  : () => Navigator.pop(d, elegido),
              child: const Text('Confirmar asignación'),
            ),
          ],
        ),
      ),
    );
    if (id != null) await c.asignar(s, id);
  }

  Future<void> historial(BuildContext context, Solicitud s) async {
    await controller.verHistorial(s.id);
    if (!context.mounted ||
        controller.usuario == null ||
        controller.error != null)
      return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Historial de estados'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (controller.historial.isEmpty)
                  const Text('No hay transiciones registradas.'),
                for (final h in controller.historial)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${h.estadoAnterior.name} → ${h.estadoNuevo.name}\n${fecha(h.fechaHora)}\nEjecutor: ${h.actor.usuarioId} (${h.actor.rol.name})${h.recicladorId == null ? '' : '\nReciclador: ${h.recicladorId}'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<EstadoSolicitud>(
                isExpanded: true,
                initialValue: c.estado,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: [
                  for (final e in EstadoSolicitud.values)
                    DropdownMenuItem(value: e, child: Text(e.name)),
                ],
                onChanged: (e) {
                  if (e != null) unawaited(c.filtrar(e, c.material));
                },
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<TipoMaterial?>(
                isExpanded: true,
                initialValue: c.material,
                decoration: const InputDecoration(labelText: 'Material'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Todos los materiales'),
                  ),
                  for (final m in TipoMaterial.values)
                    DropdownMenuItem(value: m, child: Text(m.name)),
                ],
                onChanged: (m) => unawaited(c.filtrar(c.estado, m)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (c.cargandoLista)
          const Center(child: CircularProgressIndicator())
        else if (c.lista.isEmpty)
          const Text('No hay solicitudes con estos filtros.'),
        for (final s in c.lista)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    materiales(s),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText('Solicitud ${s.id}'),
                  Text('${s.estado.name} · ${fecha(s.fechaCreacion)}'),
                  if (s.descripcionMaterial?.isNotEmpty ?? false)
                    Text(s.descripcionMaterial!),
                  if (s.ubicacion.tieneCoordenadas)
                    ExpansionTile(
                      title: const Text('Ver ubicación en mapa'),
                      children: [LocationCard(s.ubicacion, maps)],
                    )
                  else
                    LocationCard(s.ubicacion, maps),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (s.estado == EstadoSolicitud.PENDIENTE)
                        FilledButton(
                          onPressed: c.ocupado
                              ? null
                              : () => asignar(context, s),
                          child: const Text('Asignar'),
                        ),
                      if (s.estado == EstadoSolicitud.ASIGNADA)
                        FilledButton(
                          onPressed: c.ocupado
                              ? null
                              : () async {
                                  if (await confirmar(
                                    context,
                                    'Confirmar recolección',
                                    '¿Deseas marcar esta solicitud como RECOLECTADA?',
                                  ))
                                    await c.recolectar(s);
                                },
                          child: const Text('Marcar Recolectada'),
                        ),
                      if (s.estado == EstadoSolicitud.PENDIENTE ||
                          s.estado == EstadoSolicitud.ASIGNADA)
                        OutlinedButton(
                          onPressed: c.ocupado
                              ? null
                              : () async {
                                  if (await confirmar(
                                    context,
                                    'Cancelar solicitud',
                                    'Estado observado: ${s.estado.name}. Si cambia, la cancelación será rechazada.',
                                  ))
                                    await c.cancelar(s);
                                },
                          child: const Text('Cancelar solicitud'),
                        ),
                      TextButton(
                        onPressed: c.ocupado
                            ? null
                            : () => historial(context, s),
                        child: const Text('Historial'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Recicladores extends StatelessWidget {
  final AdminController controller;
  const _Recicladores({required this.controller});
  Future<void> editar(BuildContext context, [Reciclador? r]) =>
      showDialog<void>(
        context: context,
        builder: (_) => _RecForm(controller: controller, original: r),
      );
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: c.ocupado ? null : () => editar(context),
            icon: const Icon(Icons.add),
            label: const Text('Registrar reciclador'),
          ),
        ),
        const SizedBox(height: 16),
        if (c.recicladoresLista.isEmpty)
          const Text('No hay recicladores registrados.'),
        for (final r in c.recicladoresLista)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.nombre,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('Documento: ${r.documento}'),
                  if (r.telefono != null) Text('Teléfono: ${r.telefono}'),
                  Text('${r.modalidad.name} · ${r.estado.name}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: c.ocupado ? null : () => editar(context, r),
                        child: const Text('Editar'),
                      ),
                      OutlinedButton(
                        onPressed: c.ocupado
                            ? null
                            : () async {
                                if (await confirmar(
                                  context,
                                  r.estado == EstadoReciclador.ACTIVO
                                      ? 'Inactivar reciclador'
                                      : 'Reactivar reciclador',
                                  '¿Confirmas el cambio de estado de ${r.nombre}?',
                                ))
                                  await c.cambiarActividad(r);
                              },
                        child: Text(
                          r.estado == EstadoReciclador.ACTIVO
                              ? 'Inactivar'
                              : 'Reactivar',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecForm extends StatefulWidget {
  final AdminController controller;
  final Reciclador? original;
  const _RecForm({required this.controller, this.original});
  @override
  State<_RecForm> createState() => _RecFormState();
}

class _RecFormState extends State<_RecForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController nombre, documento, telefono;
  final correo = TextEditingController(), clave = TextEditingController();
  ModalidadReciclador modalidad = ModalidadReciclador.SIN_APP;
  @override
  void initState() {
    super.initState();
    nombre = TextEditingController(text: widget.original?.nombre);
    documento = TextEditingController(text: widget.original?.documento);
    telefono = TextEditingController(text: widget.original?.telefono);
    modalidad = widget.original?.modalidad ?? ModalidadReciclador.SIN_APP;
  }

  @override
  void dispose() {
    for (final c in [nombre, documento, telefono, correo, clave]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return AlertDialog(
        title: Text(
          widget.original == null
              ? 'Registrar reciclador'
              : 'Editar reciclador',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Avisos(c),
                  TextFormField(
                    controller: nombre,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Campo obligatorio' : null,
                  ),
                  TextFormField(
                    controller: documento,
                    decoration: const InputDecoration(labelText: 'Documento'),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Campo obligatorio' : null,
                  ),
                  TextFormField(
                    controller: telefono,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (opcional)',
                    ),
                  ),
                  if (widget.original == null)
                    DropdownButtonFormField<ModalidadReciclador>(
                      initialValue: modalidad,
                      decoration: const InputDecoration(labelText: 'Modalidad'),
                      items: [
                        for (final m in ModalidadReciclador.values)
                          DropdownMenuItem(value: m, child: Text(m.name)),
                      ],
                      onChanged: (m) {
                        if (m != null) setState(() => modalidad = m);
                      },
                    )
                  else
                    Text('Modalidad: ${modalidad.name} (no editable)'),
                  if (widget.original == null &&
                      modalidad == ModalidadReciclador.CON_APP) ...[
                    TextFormField(
                      controller: correo,
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: (v) =>
                          v?.contains('@') ?? false ? null : 'Correo inválido',
                    ),
                    TextFormField(
                      controller: clave,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña inicial',
                      ),
                      validator: (v) =>
                          (v?.length ?? 0) < 8 ? 'Mínimo 8 caracteres' : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: c.ocupado ? null : () => Navigator.pop(context),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: c.ocupado
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    await c.guardarReciclador(
                      original: widget.original,
                      nombre: nombre.text,
                      documento: documento.text,
                      telefono: telefono.text.trim().isEmpty
                          ? null
                          : telefono.text.trim(),
                      modalidad: modalidad,
                      correo: correo.text.trim(),
                      clave: clave.text,
                    );
                    if (context.mounted && c.error == null)
                      Navigator.pop(context);
                  },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  );
}
