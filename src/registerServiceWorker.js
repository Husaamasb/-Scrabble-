export function registerServiceWorker() {
  if (!('serviceWorker' in navigator) || !import.meta.env.PROD) return;
  window.addEventListener('load', () => {
    const baseUrl = new URL(import.meta.env.BASE_URL, window.location.origin);
    const workerUrl = new URL('sw.js', baseUrl);
    navigator.serviceWorker.register(workerUrl, { scope: baseUrl.pathname }).catch(error => {
      console.error('Scrabble offline support could not be registered:', error);
    });
  }, { once:true });
}
