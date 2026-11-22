const http=require('http'),proxy=require('http-proxy').createProxyServer({});
proxy.on('error',(e,req,res)=>{if(res.writeHead){res.writeHead(502);res.end('Upstream unavailable');}});
// CORS limitado al origen del panel local; este proxy nunca se despliega.
const browserOrigin='http://127.0.0.1:54328';
proxy.on('proxyRes',(upstream,req)=>{
 if(req.headers.origin===browserOrigin){
  upstream.headers['access-control-allow-origin']=browserOrigin;
  upstream.headers['access-control-expose-headers']='content-range';
 }
});
const sockets=new Set();let paused=false;
const server=http.createServer((req,res)=>{
 if(req.method==='OPTIONS' && req.headers.origin===browserOrigin){
  res.writeHead(204,{'Access-Control-Allow-Origin':browserOrigin,'Access-Control-Allow-Methods':'GET,POST,PATCH,DELETE,OPTIONS','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info,x-supabase-api-version,prefer,range,accept-profile,content-profile','Vary':'Origin'});res.end();return;
 }
 if(req.method==='POST' && req.url==='/__test/realtime/pause'){paused=true;for(const s of sockets)s.destroy();res.end('paused');return;}
 if(req.method==='POST' && req.url==='/__test/realtime/resume'){paused=false;res.end('resumed');return;}
 const routes=[['/auth/v1','http://127.0.0.1:54324'],['/rest/v1','http://127.0.0.1:54321'],['/functions/v1/crear_reciclador_con_app','http://127.0.0.1:54326']];
 const route=routes.find(([prefix])=>req.url.startsWith(prefix));
 if(!route){res.writeHead(404);res.end();return;}
 req.url=req.url.slice(route[0].length)||'/';proxy.web(req,res,{target:route[1]});
});
server.on('upgrade',(req,socket,head)=>{if(paused){socket.destroy();return;}sockets.add(socket);socket.on('close',()=>sockets.delete(socket));req.url=req.url.replace('/realtime/v1','/socket');req.headers.host='realtime-dev.localhost';proxy.ws(req,socket,head,{target:'ws://127.0.0.1:54325'});});
server.listen(54327,'127.0.0.1',()=>console.log('Test gateway :54327'));
