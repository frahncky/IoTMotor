// Compartilha uma unica conexao MQTT entre os modulos da pagina.
// Cada modulo recebe um cliente virtual com a mesma interface que usa hoje,
// mas apenas um WebSocket e um socket TCP chegam ao broker publico.
(function (root) {
  'use strict';

  function topicMatches(filter, topic) {
    const f = String(filter).split('/');
    const t = String(topic).split('/');
    for (let i = 0; i < f.length; i++) {
      if (f[i] === '#') return i === f.length - 1;
      if (i >= t.length || (f[i] !== '+' && f[i] !== t[i])) return false;
    }
    return f.length === t.length;
  }

  function installSharedMqtt(target) {
    const mqtt = target?.mqtt;
    if (!mqtt?.connect || mqtt.__iotmotorShared) return false;
    const originalConnect = mqtt.connect.bind(mqtt);
    const pools = new Map();

    function virtualClient(pool) {
      const handlers = new Map();
      const filters = new Set();
      let ended = false;
      const client = {
        get connected() { return !ended && pool.physical.connected === true; },
        on(event, callback) {
          if (!handlers.has(event)) handlers.set(event, new Set());
          handlers.get(event).add(callback);
          return client;
        },
        subscribe(topics, options, callback) {
          const list = Array.isArray(topics) ? topics : [topics];
          for (const topic of list) filters.add(String(topic));
          pool.physical.subscribe(topics, options, callback);
          return client;
        },
        publish(...args) { return pool.physical.publish(...args); },
        end(force) {
          if (ended) return client;
          ended = true;
          pool.clients.delete(client);
          if (!pool.clients.size) {
            pools.delete(pool.url);
            pool.physical.end(force);
          }
          return client;
        },
        _emit(event, ...args) {
          if (ended) return;
          for (const callback of handlers.get(event) || []) callback(...args);
        },
        _accepts(topic) {
          for (const filter of filters) if (topicMatches(filter, topic)) return true;
          return false;
        }
      };
      pool.clients.add(client);
      if (pool.physical.connected) setTimeout(() => client._emit('connect'), 0);
      return client;
    }

    mqtt.connect = function sharedConnect(url, options) {
      const key = String(url);
      let pool = pools.get(key);
      if (!pool) {
        const physical = originalConnect(url, options);
        pool = {url: key, physical, clients: new Set(), dropTimer: null};
        pools.set(key, pool);
        physical.on('connect', (...args) => {
          if (pool.dropTimer) clearTimeout(pool.dropTimer);
          pool.dropTimer = null;
          for (const client of [...pool.clients]) client._emit('connect', ...args);
        });
        const delayedDrop = () => {
          if (pool.dropTimer) return;
          pool.dropTimer = setTimeout(() => {
            pool.dropTimer = null;
            if (!physical.connected) for (const client of [...pool.clients]) client._emit('offline');
          }, 8000);
        };
        for (const event of ['reconnect', 'offline', 'close']) physical.on(event, delayedDrop);
        physical.on('error', (...args) => { for (const client of [...pool.clients]) client._emit('error', ...args); });
        physical.on('message', (topic, payload, packet) => {
          for (const client of [...pool.clients]) {
            if (client._accepts(topic)) client._emit('message', topic, payload, packet);
          }
        });
      }
      return virtualClient(pool);
    };
    mqtt.__iotmotorShared = true;
    mqtt.__iotmotorPools = pools;
    return true;
  }

  if (root?.mqtt) installSharedMqtt(root);
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {installSharedMqtt, topicMatches};
  }
})(typeof window !== 'undefined' ? window : undefined);
