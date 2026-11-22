import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:domain/domain.dart';
import 'package:material_mobile/presentation/mobile_app.dart';
import 'package:material_mobile/presentation/mobile_controller.dart';
import 'package:material_mobile/presentation/ui_common.dart';
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
  late MobileController c;
  setUp(() {
    f = Fixture();
    c = MobileController(
      f.authService,
      f.solicitudService,
      f.gps,
      politica: 'Texto de política de prueba',
    );
  });
  tearDown(() async {
    c.dispose();
    await flush();
    await f.dispose();
  });
  Future<void> app(WidgetTester t) async {
    await t.pumpWidget(
      MobileApp(controller: c, maps: const MapConfig('', '', 'test')),
    );
    await t.pumpAndSettle();
  }

  testWidgets('registro muestra política y aceptación antes de crear cuenta', (
    t,
  ) async {
    await app(t);
    await t.tap(find.text('Registrarme como ciudadano'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Nombre');
    await t.enterText(
      find.widgetWithText(TextFormField, 'Correo'),
      'c@example.com',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      'Password123',
    );
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear cuenta'),
          )
          .onPressed,
      isNull,
    );
    await t.tap(find.text('Leer política de tratamiento'));
    await t.pumpAndSettle();
    expect(find.text('Texto de política de prueba'), findsOneWidget);
    await t.tap(find.text('Cerrar'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Crear cuenta'));
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(f.auth.registros, 1);
    expect(find.text('No hay solicitudes para mostrar.'), findsOneWidget);
  });
  testWidgets('login/logout limpia pantalla y credenciales', (t) async {
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
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    await t.tap(find.byTooltip('Cerrar sesión'));
    await t.pumpAndSettle();
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('c@example.com'), findsNothing);
  });
  testWidgets('formulario manual, selección múltiple y confirmación con id', (
    t,
  ) async {
    await c.entrar('c@example.com', 'p');
    await app(t);
    await t.tap(find.text('Nueva solicitud'));
    await t.pumpAndSettle();
    await t.tap(find.text('Papel'));
    await t.tap(find.text('Metal'));
    await t.tap(find.text('Usar ubicación GPS'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Dirección manual'),
      'Calle 1',
    );
    await t.ensureVisible(find.text('Registrar solicitud'));
    await t.tap(find.text('Registrar solicitud'));
    await t.pumpAndSettle();
    expect(f.solicitudes.recibidos, hasLength(2));
    expect(f.gps.llamadas, 0);
    expect(find.text('Solicitud registrada: nueva'), findsOneWidget);
  });
  testWidgets('cancelación pide confirmación y muestra conflicto', (t) async {
    f.solicitudes.rows = [solicitud()];
    f.solicitudes.conflicto = true;
    await c.entrar('c@example.com', 'p');
    await app(t);
    await t.tap(find.text('Cancelar solicitud'));
    await t.pumpAndSettle();
    expect(f.solicitudes.cancelaciones, 0);
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(f.solicitudes.cancelaciones, 1);
    expect(find.textContaining('La solicitud cambió'), findsOneWidget);
  });
  testWidgets('reciclador ve dirección manual sin mapa y marca recolectada', (
    t,
  ) async {
    f.auth.rol = Rol.RECICLADOR;
    f.solicitudes.rows = [solicitud(estado: EstadoSolicitud.ASIGNADA)];
    await c.entrar('r@example.com', 'p');
    await app(t);
    expect(find.text('Dirección: Calle 1'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    await t.tap(find.text('Marcar Recolectada'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(f.solicitudes.recolecciones, 1);
  });
  testWidgets('mapa con coordenadas muestra marcador y atribución', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationCard(
            Ubicacion(latitud: 2.4, longitud: -76.6),
            const MapConfig(
              'https://tiles.invalid/{z}/{x}/{y}.png',
              'Atribución de prueba',
              'test',
            ),
            tileProvider: Tiles(),
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(MarkerLayer), findsOneWidget);
    expect(find.text('Atribución de prueba'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
  testWidgets('foreground y reentrada invocan reconciliación', (t) async {
    await c.entrar('c@example.com', 'p');
    await app(t);
    final before = f.solicitudes.reconciliaciones;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(f.solicitudes.reconciliaciones, greaterThan(before));
    await t.tap(find.text('Nueva solicitud'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mis solicitudes').last);
    await t.pumpAndSettle();
    expect(f.solicitudes.reconciliaciones, greaterThan(before + 1));
  });
  testWidgets('cambio de sesión cierra diálogo y elimina datos anteriores', (
    t,
  ) async {
    f.solicitudes.rows = [solicitud()];
    await c.entrar('c@example.com', 'p');
    await app(t);
    await t.tap(find.text('Cancelar solicitud'));
    await t.pumpAndSettle();
    f.auth.cambiar('otro');
    await t.pumpAndSettle();
    expect(find.text('Confirmar'), findsNothing);
    expect(find.text('Solicitud s'), findsNothing);
    expect(find.text('Ingresar'), findsOneWidget);
  });
  testWidgets('ambigüedad mantiene envío deshabilitado hasta revisar', (
    t,
  ) async {
    await c.entrar('c@example.com', 'p');
    f.solicitudes.ambiguo = true;
    await c.crear([TipoMaterial.PAPEL], '', false, 'C');
    await app(t);
    expect(find.text('Ya revisé el resultado'), findsOneWidget);
    await t.tap(find.text('Nueva solicitud'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Registrar solicitud'));
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Registrar solicitud'),
          )
          .onPressed,
      isNull,
    );
    await t.tap(find.text('Ya revisé el resultado'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(c.noConfirmado, isFalse);
  });
}
