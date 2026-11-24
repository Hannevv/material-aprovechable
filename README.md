# Plataforma de Gestión de Material Aprovechable

Proyecto de grado orientado al desarrollo de una plataforma digital para la gestión de solicitudes de recolección de material aprovechable en la ciudad de Popayán.

La solución busca facilitar la coordinación entre ciudadanos, una organización recolectora y recicladores de oficio mediante una aplicación móvil y un panel administrativo web.

## Descripción general

La plataforma permite que un ciudadano registre una solicitud de recolección indicando los materiales disponibles y su ubicación. Posteriormente, un usuario administrador puede consultar las solicitudes, asignarlas manualmente a un reciclador activo y realizar seguimiento a su estado.

Los recicladores que utilizan la aplicación móvil pueden consultar las recolecciones que les han sido asignadas y marcar una solicitud como recolectada cuando finalizan el proceso.

También se contempla la gestión de recicladores que no cuentan con acceso a la aplicación, denominados `SIN_APP`. En estos casos, las operaciones correspondientes son realizadas desde el panel administrativo por un usuario autorizado.

## Actores del sistema

### Ciudadano

El ciudadano utiliza la aplicación móvil para:

- Registrarse e iniciar sesión.
- Crear solicitudes de recolección.
- Seleccionar uno o varios tipos de material.
- Registrar su ubicación mediante GPS o dirección manual.
- Consultar el estado de sus solicitudes.
- Cancelar una solicitud mientras se encuentre en estado permitido.

### Reciclador con aplicación

El reciclador con aplicación puede:

- Iniciar sesión.
- Consultar las solicitudes que le han sido asignadas.
- Visualizar la ubicación de una recolección.
- Marcar una solicitud como recolectada.

### Administrador

El administrador utiliza el panel web para:

- Consultar solicitudes.
- Consultar recicladores.
- Registrar recicladores con aplicación y sin aplicación.
- Activar o inactivar recicladores.
- Asignar solicitudes manualmente.
- Actualizar estados permitidos.
- Consultar el historial de cambios de las solicitudes.

## Estados de una solicitud

Las solicitudes utilizan una máquina de estados con los siguientes valores:

- `Pendiente`
- `Asignada`
- `Recolectada`
- `Cancelada`

Las principales transiciones permitidas son:

```text
Pendiente → Asignada
Pendiente → Cancelada
Asignada → Recolectada
Asignada → Cancelada
```

Los estados `Recolectada` y `Cancelada` son estados finales.

Las transiciones son controladas por el backend para evitar modificaciones no autorizadas desde el cliente.

## Tipos de material

El MVP contempla los siguientes tipos de material aprovechable:

- Papel
- Cartón
- Plástico
- Vidrio
- Metal

Una solicitud puede contener uno o varios tipos de material.

## Arquitectura

El proyecto utiliza una arquitectura basada en Clean Architecture con cuatro capas principales:

```text
Presentación
    ↓
Aplicación
    ↓
Dominio
    ↑
Contratos
    ↑
Infraestructura
    ↓
Supabase
```

### Presentación

Contiene las interfaces gráficas de la aplicación móvil y del panel administrativo.

Su responsabilidad principal es:

- mostrar información;
- recibir acciones del usuario;
- representar estados de carga, éxito y error;
- delegar las operaciones a la capa de aplicación.

### Aplicación

Coordina los casos de uso del sistema.

Incluye servicios relacionados con:

- autenticación;
- solicitudes;
- recicladores;
- sincronización de información mediante Streams.

Esta capa no depende directamente de implementaciones de Supabase.

### Dominio

Contiene las reglas principales del negocio.

Aquí se encuentran:

- entidades;
- Value Objects;
- estados de las solicitudes;
- reglas de transición;
- contratos Repository;
- patrones de dominio como State y Strategy.

El dominio busca mantenerse independiente de frameworks y tecnologías externas.

### Infraestructura

Implementa los contratos definidos por el dominio.

Esta capa contiene los adaptadores necesarios para interactuar con:

- Supabase Auth;
- PostgreSQL;
- RPC;
- Realtime / Postgres Changes;
- Edge Functions.

## Composition Root

La aplicación móvil y el panel web cuentan con su propio Composition Root.

Estos puntos de entrada se encargan de:

- crear las dependencias;
- inicializar Supabase;
- conectar interfaces con implementaciones;
- inyectar repositorios y servicios.

Gracias a esto, la capa de aplicación no necesita conocer directamente las implementaciones de infraestructura.

## Tecnologías utilizadas

### Frontend

- Flutter
- Flutter Web
- Dart

### Backend

- Supabase
- PostgreSQL
- Supabase Auth
- Row Level Security
- RPC
- Edge Functions
- Postgres Changes

### Ubicación y mapas

- geolocator
- flutter_map
- OpenStreetMap o proveedor de teselas compatible

### Herramientas

- Git
- GitHub
- Android Studio
- Visual Studio Code
- Netlify para el despliegue del panel administrativo

## ¿Por qué Dart?

Dart es utilizado porque es el lenguaje principal del framework Flutter.

En este proyecto permite utilizar una misma tecnología tanto para la aplicación móvil como para el panel web.

Esto permite compartir código entre ambos clientes, principalmente:

- entidades;
- reglas de negocio;
- contratos;
- servicios de aplicación;
- repositorios;
- Streams;
- validaciones.

Dart también ofrece características importantes para este proyecto:

### Tipado estático

Permite detectar errores de tipos durante el desarrollo y modelar de forma clara elementos como estados, entidades y parámetros.

### Null Safety

Permite diferenciar explícitamente entre valores obligatorios y opcionales, reduciendo errores relacionados con valores nulos.

### Programación asíncrona

Dart incluye soporte nativo para:

```dart
Future
async
await
Stream
```

Esto resulta especialmente útil para operaciones como:

- autenticación;
- consultas a Supabase;
- llamadas RPC;
- geolocalización;
- suscripciones a cambios.

### Streams

Los Streams permiten implementar un comportamiento basado en Observer.

Cuando Supabase informa un cambio relevante, los componentes suscritos pueden actualizar la información automáticamente sin realizar consultas constantes.

## Patrones de diseño

### Repository

Se utiliza para desacoplar la lógica del negocio del mecanismo concreto de persistencia.

El dominio define contratos y la infraestructura los implementa utilizando Supabase.

Esto permite que las capas internas no dependan directamente de la tecnología de base de datos.

### State

Se utiliza para representar y controlar el comportamiento asociado a los diferentes estados de una solicitud.

Ejemplo:

```text
Pendiente
Asignada
Recolectada
Cancelada
```

Cada estado determina las operaciones que pueden realizarse.

### Strategy

Se utiliza para abstraer comportamientos que pueden tener distintas implementaciones.

Uno de los casos está relacionado con la obtención de ubicación, permitiendo separar la lógica del dominio de una implementación concreta como `geolocator`.

### Observer

Se implementa mediante Streams y suscripciones.

El flujo general es:

```text
Cambio en Supabase
        ↓
Postgres Changes
        ↓
Adaptador de infraestructura
        ↓
Stream
        ↓
Aplicación / Presentación
        ↓
Actualización de la interfaz
```

## Base de datos

Las tablas principales del sistema son:

### usuarios

Contiene la información asociada a los usuarios autenticados y su rol dentro del sistema.

### recicladores

Contiene la información de los recicladores.

Un reciclador puede ser:

- `CON_APP`
- `SIN_APP`

Los recicladores `SIN_APP` no necesitan una cuenta en Supabase Auth.

### solicitudes

Contiene las solicitudes de recolección registradas por los ciudadanos.

Incluye información como:

- ciudadano;
- reciclador asignado;
- descripción;
- ubicación;
- estado;
- fechas relevantes.

### solicitud_materiales

Relaciona una solicitud con uno o varios tipos de material.

### historial_estados

Registra los cambios de estado realizados sobre una solicitud.

Permite conservar trazabilidad sobre:

- estado anterior;
- estado nuevo;
- usuario que realizó la operación;
- rol;
- reciclador relacionado;
- fecha de cambio.

## Seguridad

La seguridad del sistema se controla principalmente en el backend.

El cliente no es considerado una fuente confiable para determinar:

- identidad del usuario;
- rol;
- reciclador asociado;
- permisos.

Supabase obtiene la identidad autenticada mediante:

```sql
auth.uid()
```

A partir de esta identidad se consulta el rol almacenado en el sistema.

También se utiliza Row Level Security para limitar el acceso a los datos dependiendo del usuario autenticado.

## RPC y operaciones críticas

Las operaciones principales de negocio se realizan mediante funciones RPC.

Entre ellas se encuentran:

```text
crear_perfil_ciudadano
crear_solicitud
asignar_solicitud
marcar_recolectada
cancelar_solicitud
```

Esto permite centralizar las validaciones y reglas críticas en el servidor.

Por ejemplo, una asignación debe comprobar:

- que el usuario sea ADMIN;
- que la solicitud esté Pendiente;
- que el reciclador esté activo;
- que la transición sea válida.

Las operaciones críticas no dependen de un `UPDATE` directo enviado desde Flutter.

## Consistencia y concurrencia

Las actualizaciones importantes se ejecutan de forma controlada en el backend.

Cuando una solicitud cambia de estado, el cambio y su historial deben mantenerse consistentes.

El sistema también contempla situaciones de concurrencia, por ejemplo cuando dos usuarios intentan modificar la misma solicitud.

Para operaciones como cancelación se utiliza el estado esperado de la solicitud con el objetivo de detectar modificaciones concurrentes.

## Recicladores CON_APP y SIN_APP

### CON_APP

Un reciclador con aplicación cuenta con:

- usuario en Supabase Auth;
- registro en `usuarios`;
- registro en `recicladores`.

Puede iniciar sesión y operar desde la aplicación móvil.

### SIN_APP

Un reciclador sin aplicación cuenta únicamente con su registro operativo en `recicladores`.

No necesita credenciales de autenticación.

Las operaciones relacionadas con este reciclador son realizadas por el administrador desde el panel web.

## Edge Function

El registro de un reciclador con aplicación requiere operaciones administrativas que no deben ejecutarse directamente desde el cliente.

Para esto se utiliza una Edge Function encargada de coordinar la creación del usuario y del perfil correspondiente.

Entre sus responsabilidades se encuentran:

- validar la autorización;
- crear el usuario en Auth;
- registrar la información correspondiente;
- manejar errores parciales;
- utilizar credenciales privilegiadas únicamente en el entorno servidor.

## Flujo general de una solicitud

```text
CIUDADANO
    ↓
Aplicación móvil
    ↓
Presentación
    ↓
Servicio de aplicación
    ↓
Repository
    ↓
Infraestructura Supabase
    ↓
RPC crear_solicitud
    ↓
PostgreSQL
```

Posteriormente:

```text
ADMIN
   ↓
Panel Web
   ↓
RPC asignar_solicitud
   ↓
Solicitud: Pendiente → Asignada
   ↓
Historial
   ↓
Postgres Changes
   ↓
RECICLADOR recibe actualización
```

Finalmente:

```text
RECICLADOR
   ↓
Aplicación móvil
   ↓
RPC marcar_recolectada
   ↓
Solicitud: Asignada → Recolectada
   ↓
Historial
```

## Alcance del MVP

El proyecto está enfocado en la gestión básica de solicitudes de recolección.

No incluye dentro del alcance actual:

- optimización automática de rutas;
- asignación automática de recicladores;
- inteligencia artificial;
- pagos;
- recompensas;
- chat;
- geocodificación;
- agenda de recolecciones;
- reasignación automática;
- múltiples organizaciones;
- reportes estadísticos avanzados.

## Objetivo general

Desarrollar un prototipo funcional de una plataforma digital para gestionar solicitudes de recolección de material aprovechable, facilitando la coordinación entre ciudadanos, una organización recolectora y recicladores de oficio en la ciudad de Popayán.

## Autores

- Johan Eduardo Vivas Narváez
- Juan Sebastián Narváez Delgado

Proyecto académico de Ingeniería Informática.
