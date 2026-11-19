import {handler,Backend,Datos,Fallo} from '../handler.ts';
function assert(v:unknown){if(!v)throw Error('Assertion failed');}
const datos={nombre:'Nombre',documento:'123',correo:'x@example.com',contrasena_inicial:'Password123'};
class Fake implements Backend {
 deleted:string[]=[];created=0;falloAdmin=false;falloAuth=false;falloPerfil=false;falloLectura=false;falloDelete=false;committed=false;
 admin(_t:string){if(this.falloAdmin)throw new Fallo('NO_AUTORIZADO',403);return Promise.resolve('admin');}
 crearCuenta(_d:Datos){if(this.falloAuth)throw new Fallo('DUPLICADO',409);this.created++;return Promise.resolve('new-only');}
 crearPerfil(_u:string,_a:string,_d:Datos){if(this.falloPerfil)throw new Fallo('VALIDACION',400);return Promise.resolve({id:'rec'});}
 consultarPerfil(_u:string){if(this.falloLectura)throw Error('network');return Promise.resolve(this.committed?{id:'rec'}:null);}
 eliminarCuenta(u:string){if(this.falloDelete)throw Error('network');this.deleted.push(u);return Promise.resolve();}
}
const call=(f:Fake,body:unknown=datos,token=true)=>handler(f)(new Request('http://local',{method:'POST',headers:token?{Authorization:'Bearer verified'}:{},body:JSON.stringify(body)}));
Deno.test('successful profile',async()=>{const f=new Fake();assert((await call(f)).status===201);assert(f.deleted.length===0);});
Deno.test('missing auth',async()=>{const f=new Fake();assert((await call(f,datos,false)).status===401);assert(f.created===0);});
Deno.test('non admin before mutation',async()=>{const f=new Fake();f.falloAdmin=true;assert((await call(f)).status===403);assert(f.created===0);});
Deno.test('role modality state cannot be chosen',async()=>{for(const k of ['rol','modalidad','estado']){const f=new Fake();assert((await call(f,{...datos,[k]:'ADMIN'})).status===400);assert(f.created===0);}});
Deno.test('Auth failure no compensation',async()=>{const f=new Fake();f.falloAuth=true;assert((await call(f)).status===409);assert(f.deleted.length===0);});
Deno.test('profile failure compensates exact new uid',async()=>{const f=new Fake();f.falloPerfil=true;assert((await call(f)).status===400);assert(f.deleted[0]==='new-only');});
Deno.test('lost response after commit reconciles',async()=>{const f=new Fake();f.falloPerfil=true;f.committed=true;assert((await call(f)).status===201);assert(f.deleted.length===0);});
Deno.test('unknown outcome not blindly deleted',async()=>{const f=new Fake();f.falloPerfil=true;f.falloLectura=true;assert((await(await call(f)).json()).codigo==='RESULTADO_NO_CONFIRMADO');assert(f.deleted.length===0);});
Deno.test('compensation failure explicit',async()=>{const f=new Fake();f.falloPerfil=true;f.falloDelete=true;assert((await(await call(f)).json()).codigo==='COMPENSACION_PENDIENTE');});

Deno.test('RPC incierta y lectura vacía no eliminan una cuenta en vuelo',async()=>{
 const f=new Fake(); f.crearPerfil=()=>{throw new Fallo('RESULTADO_NO_CONFIRMADO',503);};
 assert((await(await call(f)).json()).codigo==='RESULTADO_NO_CONFIRMADO');assert(f.deleted.length===0);
});
