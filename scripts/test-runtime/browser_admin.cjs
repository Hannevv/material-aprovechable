// Requiere Playwright y Chromium instalados. Solo backend local de pruebas.
const fs=require('fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const data=JSON.parse(fs.readFileSync(process.env.LIVE_FIXTURES||'.test-artifacts/phase567.json','utf8'));
 const browser=await chromium.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const checks=[],runtimeErrors=[],consoleErrors=[];
 try{
  const page=await browser.newPage({viewport:{width:1100,height:800}});page.setDefaultTimeout(15000);
  page.on('pageerror',e=>runtimeErrors.push(e.name));
  page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.type());});
  await page.goto(process.env.WEB_TEST_URL||'http://127.0.0.1:54328');
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached'});
  await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
  await page.getByRole('textbox',{name:'Correo',exact:true}).waitFor();checks.push('arranque, carga inicial y formulario de login');
  async function login(role){
   for(const [label,key] of [['Correo','email'],['Contraseña','password']]){
    const field=page.getByRole('textbox',{name:label,exact:true});
    await field.click({position:{x:30,y:25}});await page.waitForTimeout(200);
    await page.keyboard.press('Control+A');await page.keyboard.type(data[role][key],{delay:25});
    await page.waitForTimeout(200);assert.ok(await field.inputValue()===data[role][key],'El campo no recibió la entrada completa');
   }
   await page.getByRole('button',{name:'Ingresar',exact:true}).click();
  }
  await login('ciudadano');await page.getByText('Esta cuenta no tiene acceso a esta aplicación').waitFor();checks.push('autenticación CIUDADANO rechazada por el panel');
  await login('admin');await page.getByRole('radio',{name:'Solicitudes',exact:true}).waitFor();checks.push('autenticación ADMIN y acceso al panel');
  await page.getByRole('radio',{name:'Recicladores',exact:true}).click();await page.getByRole('button',{name:'Registrar reciclador',exact:true}).waitFor();
  await page.getByRole('radio',{name:'Solicitudes',exact:true}).click();await page.getByText('PENDIENTE').first().waitFor();checks.push('navegación Solicitudes → Recicladores → Solicitudes');
  await page.screenshot({path:process.env.BROWSER_SCREENSHOT||'/workspace/work/admin-browser-panel89.png'});
  await page.getByRole('button',{name:'Cerrar sesión',exact:true}).click();await page.getByRole('button',{name:'Ingresar',exact:true}).waitFor();
  assert.equal(await page.getByRole('textbox',{name:'Correo',exact:true}).inputValue(),'');checks.push('logout y limpieza del formulario');
  assert.deepEqual(runtimeErrors,[]);assert.deepEqual(consoleErrors,[]);checks.push('sin errores de runtime ni errores de consola');
  console.log(JSON.stringify({checks,passed:checks.length,runtimeErrors:runtimeErrors.length,consoleErrors:consoleErrors.length},null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error('Prueba Chromium fallida: '+e.name+' '+e.message.slice(0,400));process.exitCode=1;});
