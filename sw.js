const CACHE = "quality-v117";
const CORE = ["./", "./index.html", "./manifest.json", "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png"];
// مكتبات خارجية تُحفظ في الجهاز ليعمل التطبيق والتقارير والطباعة بدون إنترنت
const EXT = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js",
  "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js",
  "https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js",
  "https://cdn.jsdelivr.net/npm/pptxgenjs@4.0.1/dist/pptxgen.bundle.js"
];
self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE).then(() => Promise.all(EXT.map(u => c.add(new Request(u, { mode: "cors" })).catch(() => {}))))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
const isLib = u => { try { return /cdnjs\.cloudflare\.com|cdn\.jsdelivr\.net|fonts\.(googleapis|gstatic)\.com/.test(new URL(u).hostname); } catch (e) { return false; } };
const cacheable = u => { try { const x = new URL(u); return x.origin === location.origin || isLib(u); } catch (e) { return false; } };
const put = (req, r) => { if (r && (r.ok || r.type === "opaque")) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return r; };
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const url = e.request.url;
  // طلبات قاعدة البيانات لا تُحفظ (يتولاها التطبيق نفسه)
  if (!cacheable(url)) return;
  // المكتبات بإصدار ثابت: من الجهاز أولاً (تعمل فوراً حتى مع شبكة بدون إنترنت)
  if (isLib(url)) {
    e.respondWith(caches.match(e.request).then(m => m || fetch(e.request).then(r => put(e.request, r))));
    return;
  }
  // ملفات المنصة: الشبكة أولاً، وإن تأخرت 6 ثوانٍ (واي فاي بدون إنترنت) تُفتح النسخة المحفوظة
  e.respondWith(new Promise(res => {
    let done = false;
    const fb = () => caches.match(e.request).then(m => m || (e.request.mode === "navigate" ? caches.match("./index.html") : null));
    const net = fetch(e.request).then(r => put(e.request, r));
    const t = setTimeout(() => fb().then(m => { if (m && !done) { done = true; res(m); } }), 6000);
    net.then(r => { if (!done) { done = true; clearTimeout(t); res(r); } }).catch(() => { clearTimeout(t); fb().then(m => { if (!done) { done = true; res(m || Response.error()); } }); });
  }));
});
