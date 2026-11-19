import { Backend, Datos, Fallo } from './handler.ts';
export class SupabaseBackend implements Backend {
 constructor(private authUrl: string, private restUrl: string, private key: string, private transport: typeof fetch = fetch) {}
 private async call(url: string, method: string, token: string, body?: unknown): Promise<unknown> {
  let r: Response;
  try { r = await this.transport(url,{method,headers:{apikey:this.key,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
    body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)}); }
  catch { throw new Fallo('RESULTADO_NO_CONFIRMADO',503); }
  const data = await r.json().catch(()=>null);
  if (!r.ok) {
   const code=data?.code ?? data?.error_code;
   if (r.status===401 || r.status===403 || code==='42501') throw new Fallo('NO_AUTORIZADO',403);
   if (code==='23505' || data?.error_code==='email_exists' || data?.error_code==='user_already_exists') throw new Fallo('DUPLICADO',409);
   if (r.status<500) throw new Fallo('VALIDACION',400);
   throw new Fallo('SERVICIO_NO_DISPONIBLE',503);
  }
  return data;
 }
 async admin(token: string): Promise<string> {
  const user = await this.call(`${this.authUrl}/user`,'GET',token) as {id:string};
  if (!user?.id) throw new Fallo('NO_AUTORIZADO',401);
  const rows=await this.call(`${this.restUrl}/usuarios?uid=eq.${encodeURIComponent(user.id)}&select=rol`,'GET',token) as {rol:string}[];
  if (rows[0]?.rol!=='ADMIN') throw new Fallo('NO_AUTORIZADO',403);
  return user.id;
 }
 async crearCuenta(d: Datos): Promise<string> {
  const user=await this.call(`${this.authUrl}/admin/users`,'POST',this.key,{email:d.correo,password:d.contrasena_inicial,email_confirm:true}) as {id:string};
  if (!user?.id) throw new Fallo('RESULTADO_NO_CONFIRMADO',503);
  return user.id;
 }
 async crearPerfil(uid: string, admin: string, d: Datos): Promise<Record<string,unknown>> {
  const payload={ejecutor_uid:admin,cuenta_uid:uid,nombre:d.nombre,documento:d.documento,telefono:d.telefono??null};
  // Repetir solo la persistencia idempotente de la cuenta ya identificada, nunca el alta Auth.
  for(let attempt=0;;attempt++) {
   try { return await this.call(`${this.restUrl}/rpc/_crear_perfil_reciclador_con_app`,'POST',this.key,payload) as Record<string,unknown>; }
   catch(e) { if(attempt===0 && e instanceof Fallo && e.codigo==='RESULTADO_NO_CONFIRMADO') continue; throw e; }
  }
 }
 async consultarPerfil(uid: string) {
  const rows=await this.call(`${this.restUrl}/recicladores?usuario_uid=eq.${encodeURIComponent(uid)}&select=*`,'GET',this.key) as Record<string,unknown>[];
  return rows[0]??null;
 }
 async eliminarCuenta(uid: string) { await this.call(`${this.authUrl}/admin/users/${encodeURIComponent(uid)}`,'DELETE',this.key); }
}
