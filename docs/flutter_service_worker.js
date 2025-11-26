'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "fdbc7fb125f1f4d18d98ce2d929f2f8e",
"assets/AssetManifest.bin.json": "50a0e77c02b71c73323e597046c5ed7c",
"assets/AssetManifest.json": "aa8240bc82d82205a4a41eac8a4fc998",
"assets/assets/icons/back.png": "28ecee206c95aac49ce496c4b81d0a7c",
"assets/assets/icons/weather/clear_day.png": "476249666a5d0fd39d4239627ec8fb27",
"assets/assets/icons/weather/clear_night.png": "fec6b2f469a045ce7ec396cb23851bcd",
"assets/assets/icons/weather/cloudy.png": "7f3205c079a002fe30d344e34e56a5eb",
"assets/assets/icons/weather/fog.png": "501729169dc9706029b46c3d6c16f7d3",
"assets/assets/icons/weather/neigeux.png": "b13517885fdb01da3640210e109ed676",
"assets/assets/icons/weather/nuageux%2520(1).png": "4ccad0517cf64aaede86df631df2d539",
"assets/assets/icons/weather/orage.png": "8d5deced27dcef26fd26bbdc5931765b",
"assets/assets/icons/weather/partly_cloudy_day.png": "2c5926b1a46dfeed2cc80266cabc4efa",
"assets/assets/icons/weather/partly_cloudy_night.png": "7f3205c079a002fe30d344e34e56a5eb",
"assets/assets/icons/weather/pluvieux.png": "570f7681cd1ff08fb2255223b3931873",
"assets/assets/icons/weather/rain_day.png": "82760089d66627f5b329ab0b5735e8b5",
"assets/assets/icons/weather/rain_night.png": "82760089d66627f5b329ab0b5735e8b5",
"assets/assets/icons/weather/snow_day.png": "b0f9275a0d3afeae75b50611d833cc24",
"assets/assets/icons/weather/snow_night.png": "68b96a7935475811e7fc3908c60724d0",
"assets/assets/icons/weather/storm_day.png": "1fca95d374b7f19c8a61e278cb9d7dd7",
"assets/assets/icons/weather/storm_night.png": "aaac991a707db5e621a1ecc7f36685f1",
"assets/assets/icons/weather/unknow.png": "fef35d00c9ad98c2ff41a21b3fdfd98f",
"assets/assets/image/3points.png": "7d16cd2e413fcb002c3f12c478dbe179",
"assets/assets/image/afficher.png": "8f0af7ca5bda6cc639de8104f8b6307b",
"assets/assets/image/back.png": "28ecee206c95aac49ce496c4b81d0a7c",
"assets/assets/image/battue_icone.png": "c6c02a0e4ef0024c4e7ce496ced7ac63",
"assets/assets/image/bavarder.png": "b4dd05674d3d0043e5c07589616e37d6",
"assets/assets/image/becasse.png": "7d5ec3a8f91086bf5fba0d80956060d9",
"assets/assets/image/canard.png": "901cb69758fbf8fa9dab9f2b67e829c7",
"assets/assets/image/carte_icone.png": "971b15dfad9455b22a535c11c6f2b257",
"assets/assets/image/cerf.png": "81924a7627833101707737d90de1ef63",
"assets/assets/image/deco.png": "3e199648d4db6c07813043bc725cbb30",
"assets/assets/image/delete.png": "294c818fa94e6e4d817f13d2ecb6ebf0",
"assets/assets/image/dessin.png": "f953219331eb02de4270d661ec36ee64",
"assets/assets/image/diagramme.png": "8140005d3347140cfc535d5a96bca6f0",
"assets/assets/image/edit.png": "6fd5abc84acdd5f96a6f85e18352c5d3",
"assets/assets/image/envoyer.png": "e192dd9da493f6c0439a99c567a54abc",
"assets/assets/image/erase.png": "9572d4a2464a450c00f829f6d694bd4a",
"assets/assets/image/groupe.png": "1f49d2ecf8498774c73aeba51bf39984",
"assets/assets/image/home_icone.png": "04d4efcd9c6345441db4217073f1331e",
"assets/assets/image/joindre.png": "72456e28f2a4a84415b8007ac496d78b",
"assets/assets/image/lapin.png": "6e2ea278095c8c45ad47b7f92c60a265",
"assets/assets/image/localisateur.png": "a59fda1ca8d6077ca8baa05c64bf606c",
"assets/assets/image/Logo_ChasseAlerte.png": "f5ed8a58c9b5dafc8fdb1150004c7876",
"assets/assets/image/Logo_ChasseAlerte.xcf": "7965a3ac7bb5d558679257b611e57197",
"assets/assets/image/marque.png": "e40afe7e64a645d3d61e823b6c166506",
"assets/assets/image/modifier.png": "8bee4c20d6c3cc2d165a7b2e810a438a",
"assets/assets/image/modifier2.png": "079a034d9d13ac30f1bef5368293ba3a",
"assets/assets/image/palombe.png": "a2901331862eca72c0ca88f95685fd48",
"assets/assets/image/perdri.png": "39f76a821e5bc7a98ac9717c942f408e",
"assets/assets/image/plus.png": "2231c630667a4a5bde505a2d01477293",
"assets/assets/image/profile.png": "d5694ad6317a3f1bfbc5b2ff8d8f756f",
"assets/assets/image/profil_icone.png": "b0e8215a8630969d7be6907bd173435c",
"assets/assets/image/recherche_icone.png": "0907f08e32a181c6a4df8d2044b5aaa3",
"assets/assets/image/Send.png": "32f2d358fe4a9c484f79d9b670294564",
"assets/assets/image/star.png": "0dff5ab27038246907aad2d68d6ccfc4",
"assets/assets/image/valider.png": "c25e40f17ccb0c0509acc431bd233458",
"assets/FontManifest.json": "3ddd9b2ab1c2ae162d46e3cc7b78ba88",
"assets/fonts/MaterialIcons-Regular.otf": "dd68e96d4bec3a9942f42682d76dee1c",
"assets/NOTICES": "22928127c500be33a9b371adefd6d078",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/font_awesome_flutter/lib/fonts/fa-brands-400.ttf": "15d54d142da2f2d6f2e90ed1d55121af",
"assets/packages/font_awesome_flutter/lib/fonts/fa-regular-400.ttf": "262525e2081311609d1fdab966c82bfc",
"assets/packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf": "269f971cec0d5dc864fe9ae080b19e23",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"flutter_bootstrap.js": "d4bf029456fa28c1cf42f16a7d418cb9",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "9944bdddc440f955841f4b9a022ae51e",
"/": "9944bdddc440f955841f4b9a022ae51e",
"main.dart.js": "2e8f2cc2eb328eb90f11e0fcb85dc9f6",
"manifest.json": "b22c3a0c42781f6f4afe57401691586d",
"version.json": "33bae9c73cc4629e2fedaf58b0afb52e"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
