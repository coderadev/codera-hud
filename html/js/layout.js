(() => {
  'use strict';
  const preferences = window.CoderaPrefs;
  const math = window.HudLayoutMath;
  const registry = new Map();
  let editing = false, frame, nativeTimer, lastNative = '', moneyAvailable = false;

  const viewport = () => ({ width: innerWidth, height: innerHeight });
  const hudScale = () => window.CoderaDisplay.layout.scale;
  const margin = () => {
    const s = window.CoderaDisplay.layout;
    const extra = Math.min(innerWidth, innerHeight) * preferences.data.options.safeArea / 100;
    return Object.fromEntries(['left', 'right', 'top', 'bottom'].map(k => [k, Math.max(s[k], extra) + 2 * hudScale()]));
  };
  function register(id, definition) {
    const el = document.querySelector(definition.selector);
    if (!el) return;
    const entry = { id, el, min: .5, max: 1.75, enabled: true, fixed: false, ...definition };
    el.dataset.hudElement = id;
    registry.set(id, entry);
    schedule();
  }
  function rect(entry) {
    const children = entry.bounds ? [...entry.el.querySelectorAll(entry.bounds)] : [];
    let boxes = children.filter(el => getComputedStyle(el).display !== 'none').map(el => el.getBoundingClientRect());
    if (entry.id === 'minimap') {
      const ring = entry.el.querySelector('.compass-ring').getBoundingClientRect();
      const extra = ring.width / 205 * 18;
      if (ring.width) boxes.push({ left: ring.left - extra, right: ring.right + extra,
        top: ring.top - extra, bottom: ring.bottom + extra });
      if (!preferences.data.layout.location) {
        const loc = entry.el.querySelector('.location').getBoundingClientRect();
        if (loc.width) boxes.push(loc);
      }
    }
    if (!boxes.length) return entry.el.getBoundingClientRect();
    const left = Math.min(...boxes.map(b => b.left)), top = Math.min(...boxes.map(b => b.top));
    const right = Math.max(...boxes.map(b => b.right)), bottom = Math.max(...boxes.map(b => b.bottom));
    return { x: left, y: top, left, top, right, bottom, width: right - left, height: bottom - top };
  }
  function position(id) {
    const entry = registry.get(id);
    const b = rect(entry);
    return { x: b.left / innerWidth, y: b.top / innerHeight, scale: preferences.data.layout[id]?.scale || 1 };
  }
  function applyEntry(entry, target, parentScale = 1, constrain = true) {
    entry.el.style.scale = String(target.scale / parentScale);
    let b = rect(entry);
    const edge = margin();
    const fit = Math.min(1, (innerWidth - edge.left - edge.right) / b.width,
      (innerHeight - edge.top - edge.bottom) / b.height);
    entry.appliedScale = target.scale * (Number.isFinite(fit) ? fit : 1);
    entry.el.style.scale = String(entry.appliedScale / parentScale);
    b = rect(entry);
    const bounded = constrain ? math.place(target, b, viewport(), edge) : target;
    entry.el.style.translate = `${(bounded.x * innerWidth - b.left) / hudScale() / parentScale}px ${(bounded.y * innerHeight - b.top) / hudScale() / parentScale}px`;
  }

  function apply() {
    frame = null;
    const options = preferences.data.options;
    for (const key of ['hud', 'playerStatus', 'stamina', 'speedometer', 'minimap', 'compass', 'heading', 'location', 'money', 'waypoint', 'vehicleControls']) {
      document.body.classList.toggle(`hud-hide-${key}`, !options[key]);
    }
    document.body.classList.toggle('hud-money-available', moneyAvailable);
    document.body.classList.toggle('hud-personal-backdrop', options.navBackdrop);
    document.documentElement.style.setProperty('--editor-safe-area', `${margin().top}px ${margin().right}px ${margin().bottom}px ${margin().left}px`);

    for (const entry of registry.values()) {
      entry.el.style.removeProperty('translate');
      entry.el.style.removeProperty('scale');
    }
    for (const entry of registry.values()) {
      const b = rect(entry);
      if (b.width && b.height) entry.default = { x: b.left / innerWidth, y: b.top / innerHeight, scale: 1 };
    }
    for (const entry of registry.values()) {
      const target = preferences.data.layout[entry.id];
      const parentScale = entry.id === 'location' ? registry.get('minimap')?.appliedScale || 1 : 1;

      if (entry.id === 'location' && !target) continue;
      if (entry.default) applyEntry(entry, target || entry.default, parentScale);
    }

    const controls = registry.get('vehicleControls');
    if (!preferences.data.layout.vehicleControls && controls) {
      const c = rect(controls);
      const others = ['playerStatus', 'speedometer'].map(id => rect(registry.get(id))).filter(b => b.width && b.height);
      if (c.width && others.some(b => c.left < b.right + 12 * hudScale() && c.right > b.left - 12 * hudScale()
          && c.top < b.bottom && c.bottom > b.top)) {
        const top = Math.min(...others.map(b => b.top)) - c.height - 14 * hudScale();
        controls.el.style.removeProperty('translate');
        applyEntry(controls, { x: c.left / innerWidth, y: top / innerHeight, scale: 1 });
      }
    }
    window.CoderaDisplay.syncRadar();
    nativePreview();
    window.dispatchEvent(new CustomEvent('hud:layout-applied'));
  }
  function nativePreview() {
    if (!preferences.native || !preferences.ready) return;
    if (nativeTimer) return;
    nativeTimer = setTimeout(() => {
      nativeTimer = null;
      const payload = { profile: preferences.profile, options: preferences.data.options };
      const signature = JSON.stringify(payload);
      if (signature === lastNative) return;
      lastNative = signature;
      preferences.request('prefsPreview', payload).catch(() => { lastNative = ''; });
    }, 40);
  }
  function schedule() { if (!frame) frame = requestAnimationFrame(apply); }
  register('minimap', { label: 'Minimap', selector: '#navigation', bounds: '.heading, .compass-ring, .waypoint-distance', min: .75, max: 1.35 });
  register('playerStatus', { label: 'Player Status', selector: '.player-status', bounds: '.voice, .meter, .minor-status' });
  register('stamina', { label: 'Stamina', selector: '#stamina' });
  register('speedometer', { label: 'Speedometer', selector: '#vehicleHud' });
  register('location', { label: 'Location', selector: '.location' });
  register('money', { label: 'Money', selector: '#moneyHud', available: () => moneyAvailable });
  register('vehicleControls', { label: 'Vehicle Controls', selector: '#vehicleControls' });
  window.CoderaLayout = {
    registry, register, rect, position, viewport, margin, schedule,
    get editing() { return editing; },
    setEditing(value) { editing = value; document.body.classList.toggle('hud-editing', value); apply(); },
    move(id, value, persist = true) { preferences.position(id, value, persist); },
    resetNative() { lastNative = ''; schedule(); }
  };
  let visibilitySignature = '';
  window.addEventListener('hud:render', ({ detail }) => {
    const signature = [detail.visible, detail.navigation, detail.inVehicle, detail.speedometer, detail.dev, Number(detail.stress) > 0, detail.oxygenVisible, Number(detail.oxygen ?? 100) < 99.5, Number(detail.stamina ?? 100) < 100, detail.zone, detail.street, detail.crossing, detail.waypoint, detail.waypointOffRadar].join('|');
    if (signature !== visibilitySignature) { visibilitySignature = signature; schedule(); }
  });
  window.addEventListener('message', ({ data }) => {
    if (data?.action === 'hudResync') { lastNative = ''; schedule(); return; }
    if (data?.action !== 'hudMoney') return;
    moneyAvailable = data.available === true;
    const format = n => new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(Math.max(0, Number(n) || 0));
    document.querySelector('#cashAmount').textContent = `$${format(data.cash)}`;
    document.querySelector('#bankAmount').textContent = `$${format(data.bank)}`;
    schedule();
  });
  window.addEventListener('hud:preferences', schedule);
  window.addEventListener('hud:settings-ready', () => { lastNative = ''; schedule(); });
  window.addEventListener('resize', schedule);
  window.addEventListener('hud:screen', schedule);
  document.fonts.ready.then(schedule);
})();
