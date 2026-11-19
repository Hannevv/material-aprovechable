# Public constants for this isolated test runtime only; never production configuration.
import base64,hashlib,hmac,json,time
SECRET='local-test-jwt-secret-at-least-32-characters'
def token(role):
 def enc(x):return base64.urlsafe_b64encode(json.dumps(x,separators=(',',':')).encode()).decode().rstrip('=')
 message=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'role':role,'iss':'supabase-local','iat':int(time.time()),'exp':int(time.time())+7200})
 return message+'.'+base64.urlsafe_b64encode(hmac.new(SECRET.encode(),message.encode(),hashlib.sha256).digest()).decode().rstrip('=')
