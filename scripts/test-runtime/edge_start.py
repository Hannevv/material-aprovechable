import os
from local_tokens import token
os.environ['TEST_SERVICE_KEY']=token('service_role')
os.environ['DENO_DIR']=os.environ.get('DENO_DIR','/workspace/work/deno-cache')
os.execv(os.environ.get('DENO_BIN','deno'),[os.environ.get('DENO_BIN','deno'),'run','--allow-env','--allow-net','scripts/test-runtime/edge.ts'])
