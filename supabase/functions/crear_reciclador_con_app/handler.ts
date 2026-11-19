export interface Datos { nombre: string; documento: string; telefono?: string | null; correo: string; contrasena_inicial: string }
export interface Backend {
  admin(token: string): Promise<string>;
  crearCuenta(datos: Datos): Promise<string>;
  crearPerfil(uid: string, admin: string, datos: Datos): Promise<Record<string, unknown>>;
  consultarPerfil(uid: string): Promise<Record<string, unknown> | null>;
  eliminarCuenta(uid: string): Promise<void>;
}
export class Fallo extends Error {
  constructor(public codigo: string, public status: number) { super(codigo); }
}
const headers = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*',
 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const respuesta = (status: number, body: unknown) => new Response(JSON.stringify(body), {status, headers});
export function handler(backend: Backend, registrar: (id: string) => void = () => {}) {
 return async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response(null, {status: 204, headers});
  if (req.method !== 'POST') return respuesta(405, {codigo: 'METODO_NO_PERMITIDO'});
  try {
   const token = req.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
   if (!token) throw new Fallo('NO_AUTORIZADO',401);
   const admin = await backend.admin(token); // Verifica JWT en Auth y rol protegido.
   let d: Datos;
   try { d = await req.json(); } catch { throw new Fallo('VALIDACION',400); }
   const keys = ['nombre','documento','telefono','correo','contrasena_inicial'];
   if (!d || typeof d !== 'object' || Object.keys(d).some(k => !keys.includes(k)) ||
       typeof d.nombre !== 'string' || !d.nombre.trim() || typeof d.documento !== 'string' || !d.documento.trim() ||
       typeof d.correo !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.correo) ||
       typeof d.contrasena_inicial !== 'string' || d.contrasena_inicial.length < 8 ||
       (d.telefono != null && typeof d.telefono !== 'string')) throw new Fallo('VALIDACION',400);
   const uid = await backend.crearCuenta(d);
   try {
    const perfil = await backend.crearPerfil(uid,admin,d);
    return respuesta(201,{reciclador:perfil});
   } catch (error) {
    // Una respuesta SQL perdida no implica rollback: verificar antes de compensar.
    let perfil: Record<string, unknown> | null;
    try { perfil = await backend.consultarPerfil(uid); }
    catch { registrar(uid); return respuesta(503,{codigo:'RESULTADO_NO_CONFIRMADO'}); }
    if (perfil) return respuesta(201,{reciclador:perfil});
    // Un SELECT vacío no prueba rollback de una RPC todavía en vuelo.
    if (error instanceof Fallo && error.codigo === 'RESULTADO_NO_CONFIRMADO') {
     registrar(uid); return respuesta(503,{codigo:'RESULTADO_NO_CONFIRMADO'});
    }
    try { await backend.eliminarCuenta(uid); }
    catch { registrar(uid); return respuesta(503,{codigo:'COMPENSACION_PENDIENTE'}); }
    throw error;
   }
  } catch (error) {
   if (error instanceof Fallo) return respuesta(error.status,{codigo:error.codigo});
   return respuesta(503,{codigo:'SERVICIO_NO_DISPONIBLE'});
  }
 };
}
