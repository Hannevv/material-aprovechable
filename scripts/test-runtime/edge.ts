import {handler} from '../../supabase/functions/crear_reciclador_con_app/handler.ts';
import {SupabaseBackend} from '../../supabase/functions/crear_reciclador_con_app/backend.ts';
const key=Deno.env.get('TEST_SERVICE_KEY');if(!key)throw Error('TEST_SERVICE_KEY required');
Deno.serve({hostname:'127.0.0.1',port:54326},handler(new SupabaseBackend('http://127.0.0.1:54324','http://127.0.0.1:54321',key)));
