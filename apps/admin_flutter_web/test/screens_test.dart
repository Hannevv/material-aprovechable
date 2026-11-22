import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:domain/domain.dart';
import 'package:material_admin/presentation/admin_app.dart';
import 'package:material_admin/presentation/admin_controller.dart';
import 'package:material_admin/presentation/ui_common.dart';
import '../../../test_support/fakes.dart';

class Tiles extends TileProvider {
  @override
  ImageProvider getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    ),
  );
}

void main() {
  late Fixture f;
  late AdminController c;
  setUp(() {
    f = Fixture();
    f.auth.rol = Rol.ADMIN;
    c = AdminController(f.authService, f.solicitudService, f.recicladorService);
  });
  tearDown(() async {
    c.dispose();
    await flush();
    await f.dispose();
  });
  Future<void> app(WidgetTester t) async {
    await t.pumpWidget(
      AdminApp(controller: c, maps: const MapConfig('', '', 'test')),
    );
    await t.pumpAndSettle();
  }

  testWidgets('acceso ADMIN y rechazo de ciudadano visibles', (t) async {
    f.auth.rol = Rol.CIUDADANO;
    await app(t);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Correo'),
      'c@example.com',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      'Password123',
    );
    await t.tap(find.text('Ingresar'));
    await t.pumpAndSettle();
    expect(find.textContaining('no tiene acceso'), findsOneWidget);
    f.auth.rol = Rol.ADMIN;
    await t.tap(find.text('Ingresar'));
    await t.pumpAndSettle();
    expect(find.text('Solicitudes'), findsOneWidget);
    expect(find.text('No hay solicitudes con estos filtros.'), findsOneWidget);
  });
  testWidgets('lista no duplica materiales y filtra estado/material', (
    t,
  ) async {
    f.solicitudes.rows = [solicitud()];
    await c.entrar('a@example.com', 'p');
    await app(t);
    expect(find.text('Solicitud s'), findsOneWidget);
    expect(find.text('Papel, Metal'), findsOneWidget);
    expect(find.text('Dirección: Calle 1'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<TipoMaterial?>));
    await t.pumpAndSettle();
    await t.tap(find.text('METAL').last);
    await t.pumpAndSettle();
    expect(c.material, TipoMaterial.METAL);
    expect(find.text('Solicitud s'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<EstadoSolicitud>));
    await t.pumpAndSettle();
    await t.tap(find.text('ASIGNADA').last);
    await t.pumpAndSettle();
    expect(c.estado, EstadoSolicitud.ASIGNADA);
    expect(c.lista, isEmpty);
    expect(c.cargandoLista, isFalse);
    expect(find.text('No hay solicitudes con estos filtros.'), findsOneWidget);
  });
  testWidgets('asignación manual muestra solo activos y conserva conflicto', (
    t,
  ) async {
    f.solicitudes.rows = [solicitud()];
    f.solicitudes.conflicto = true;
    await c.entrar('a@example.com', 'p');
    await app(t);
    await t.tap(find.text('Asignar'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    expect(find.textContaining('SIN_APP'), findsOneWidget);
    await t.tap(find.textContaining('CON_APP').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmar asignación'));
    await t.pumpAndSettle();
    expect(f.solicitudes.asignaciones, 1);
    expect(find.textContaining('Conflicto:'), findsOneWidget);
  });
  testWidgets('cancelación conserva el estado de la confirmación e historial', (
    t,
  ) async {
    f.solicitudes.rows = [solicitud()];
    await c.entrar('a@example.com', 'p');
    await app(t);
    await t.tap(find.text('Historial'));
    await t.pumpAndSettle();
    expect(find.textContaining('Ejecutor: admin (ADMIN)'), findsOneWidget);
    await t.tap(find.text('Cerrar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar solicitud'));
    await t.pumpAndSettle();
    expect(find.textContaining('Estado observado: PENDIENTE'), findsOneWidget);
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(f.solicitudes.esperado, EstadoSolicitud.PENDIENTE);
  });
  testWidgets('gestión permite alta SIN_APP, edición y cambio de actividad', (
    t,
  ) async {
    await c.entrar('a@example.com', 'p');
    await app(t);
    await t.tap(find.text('Recicladores'));
    await t.pumpAndSettle();
    await t.tap(find.text('Registrar reciclador'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Nuevo');
    await t.enterText(find.widgetWithText(TextFormField, 'Documento'), '123');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(f.recicladores.creada, ModalidadReciclador.SIN_APP);
    await t.tap(find.text('Editar').first);
    await t.pumpAndSettle();
    expect(find.text('Modalidad: CON_APP (no editable)'), findsOneWidget);
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(f.recicladores.editado, 'r');
    await t.tap(find.text('Inactivar').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(f.recicladores.estado, EstadoReciclador.INACTIVO);
  });
  testWidgets('mapa usa marcador solo con coordenadas y atribución', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationCard(
            Ubicacion(latitud: 2.4, longitud: -76.6),
            const MapConfig(
              'https://tiles.invalid/{z}/{x}/{y}.png',
              'Tiles de prueba',
              'test',
            ),
            tileProvider: Tiles(),
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.byType(MarkerLayer), findsOneWidget);
    expect(find.text('Tiles de prueba'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
  testWidgets('responsive estrecho no desborda lista y controles', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    f.solicitudes.rows = [solicitud()];
    await c.entrar('a@example.com', 'p');
    await app(t);
    expect(t.takeException(), isNull);
    expect(find.text('Dirección: Calle 1'), findsOneWidget);
  });
}
