const CACHE='scrabble-shell-v2';
const BASE_URL=new URL('./',self.registration.scope);
const APP_URL=BASE_URL.href;
const MANIFEST_URL=new URL('manifest.webmanifest',BASE_URL).href;
self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll([APP_URL,MANIFEST_URL])).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
  const request=event.request;
  const requestUrl=new URL(request.url);
  if(request.method!=='GET'||requestUrl.origin!==self.location.origin||!requestUrl.pathname.startsWith(new URL(BASE_URL).pathname))return;
  if(request.mode==='navigate'){
    event.respondWith(fetch(request).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(APP_URL,copy));}
      return response;
    }).catch(()=>caches.match(APP_URL)));
    return;
  }
  event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{
    if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}
    return response;
  })));
});
