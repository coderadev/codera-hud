(() => {
  'use strict';
  const native = typeof GetParentResourceName === 'function';
  const defaults = {
    hud: true, playerStatus: true, stamina: true, speedometer: true, minimap: true,
    compass: true, heading: true, location: true, money: false,
    waypoint: true, vehicleControls: true, navBackdrop: false,
    snap: true, safeArea: 0, speedUnit: 'MPH'
  };
  const limits = {
    minimap: [.75, 1.35],
    playerStatus: [.5, 1.75], stamina: [.5, 1.75], speedometer: [.5, 1.75],
    location: [.5, 1.75], money: [.5, 1.75],
    vehicleControls: [.5, 1.75]
  };
  let base = { ...defaults };
  let data = { version: 1, options: { ...base }, layout: {} };
  let profile = native ? null : 'browser';
  let ready = !native;
  let timer, dirty = false, saving = false, revision = 0, retryTimer;
  const emit = (name, detail) => window.dispatchEvent(new CustomEvent(name, { detail }));
  function sanitize(raw) {
    const clean = { version: 1, options: { ...base }, layout: {} };
    if (!raw || typeof raw !== 'object') return clean;
    for (const [key, fallback] of Object.entries(base)) {
      const value = raw.options?.[key];
      if (typeof fallback === 'boolean' && typeof value === 'boolean') clean.options[key] = value;
    }
    if (['MPH', 'KMH'].includes(raw.options?.speedUnit)) clean.options.speedUnit = raw.options.speedUnit;
    if (Number.isFinite(raw.options?.safeArea)) clean.options.safeArea = Math.max(0, Math.min(10, raw.options.safeArea));
    for (const [id, [min, max]] of Object.entries(limits)) {
      const value = raw.layout?.[id];
      if (value && ['x', 'y', 'scale'].every(k => Number.isFinite(value[k]))) {
        clean.layout[id] = {
          x: Math.max(0, Math.min(1, value.x)), y: Math.max(0, Math.min(1, value.y)),
          scale: Math.max(min, Math.min(max, value.scale))
        };
      }
    }
    return clean;
  }
  async function request(name, payload = {}) {
    if (!native) return { ok: true };
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    try {
      const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload), signal: controller.signal
      });
      if (!response.ok) throw new Error('HUD request failed');
      const result = await response.json();
      if (result.ok === false) throw new Error(result.error || 'HUD request rejected');
      return result;
    } finally { clearTimeout(timeout); }
  }
  async function flush() {
    clearTimeout(timer);
    if (!ready || !dirty || saving) return;
    saving = true;
    const current = revision;
    const currentProfile = profile;
    const snapshot = JSON.parse(JSON.stringify(data));
    emit('hud:save-state', 'Saving...');
    try {
      if (native) await request('prefsSave', { profile, settings: snapshot });
      else localStorage.setItem('codera-hud:settings:preview', JSON.stringify(snapshot));
      if (currentProfile === profile && current === revision) dirty = false;
      emit('hud:save-state', dirty ? 'Saving...' : 'Saved');
    } catch {
      emit('hud:save-state', 'Not saved. Retrying...');
      clearTimeout(retryTimer);
      retryTimer = setTimeout(flush, 3000);
    } finally {
      saving = false;
      if (dirty && current !== revision) timer = setTimeout(flush, 150);
    }
  }
  function changed(persist = true) {
    if (persist) {
      revision++;
      dirty = true;
      clearTimeout(timer);
      timer = setTimeout(flush, 400);
    }
    emit('hud:preferences', data);
  }
  function accept(message) {
    clearTimeout(timer);
    clearTimeout(retryTimer);
    base = { ...defaults, ...message.defaults };
    profile = message.profile;
    ready = !!profile;
    data = sanitize(message.settings);
    dirty = false;
    revision++;
    changed(false);
    emit('hud:settings-ready', message);
  }
  window.CoderaPrefs = {
    get data() { return data; }, get ready() { return ready; },
    get profile() { return profile; }, native, limits, request, flush,
    option(key, value) { data = sanitize({ ...data, options: { ...data.options, [key]: value } }); changed(); },
    position(id, value, persist = true) {
      if (!limits[id]) return;
      data = sanitize({ ...data, layout: { ...data.layout, [id]: value } });
      changed(persist);
    },
    commit() { changed(); },
    resetElement(id) { delete data.layout[id]; changed(); },
    resetLayout() { data.layout = {}; changed(); },
    resetAll() { data = sanitize({}); changed(); },
    sanitize
  };
  window.addEventListener('message', ({ data: message }) => {
    if (message?.action === 'prefsLoad') accept(message);
    if (message?.action === 'prefsSpeedUnit' && ['MPH', 'KMH'].includes(message.speedUnit)) {
      data.options.speedUnit = message.speedUnit;
      changed(false);
    }
  });
  if (native) {
    const initialize = () => request('prefsReady').then(accept).catch(() => setTimeout(initialize, 1500));
    initialize();
  } else {
    try { data = sanitize(JSON.parse(localStorage.getItem('codera-hud:settings:preview'))); } catch {  }
    setTimeout(() => changed(false), 0);
  }
})();
