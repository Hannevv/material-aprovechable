import {handler} from './handler.ts';
import {SupabaseBackend} from './backend.ts';
const url=Deno.env.get('SUPABASE_URL');
const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if(!url || !key) throw new Error('Configuración de servidor incompleta');
Deno.serve(handler(new SupabaseBackend(`${url}/auth/v1`,`${url}/rest/v1`,key),
 (uid)=>console.error(JSON.stringify({evento:'alta_con_app_requiere_revision',cuenta_uid:uid}))));
