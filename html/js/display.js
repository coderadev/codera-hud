(() => {
  'use strict';
  const native = typeof GetParentResourceName === 'function';
  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  let screen = { safezone: 1, revision: 0 }, layout, timer, requestId = 0, last = '';
  function measure() {
    const width = innerWidth, height = innerHeight;
    const scale = clamp(Math.min(width / 1920, height / 1080), .70, 1.35);
    const contentWidth = Math.min(width, height * 16 / 9);
    const inset = (1 - clamp(screen.safezone ?? 1, 0, 1)) / 2;
    const safe = screen.safe || { left: inset, right: inset, top: inset, bottom: inset };
    const left = Math.max((width - contentWidth) / 2 + contentWidth * inset, width * safe.left);
    const right = Math.max((width - contentWidth) / 2 + contentWidth * inset, width * safe.right);
    const top = height * safe.top, bottom = height * safe.bottom;
    layout = { width, height, scale, left, right, top, bottom, revision: screen.revision };
    const style = document.documentElement.style;
    for (const [key, value] of Object.entries({
      'ui-scale': scale, 'screen-width': `${width}px`, 'screen-height': `${height}px`,
      'safe-left': `${left}px`, 'safe-right': `${right}px`, 'safe-top': `${top}px`, 'safe-bottom': `${bottom}px`,
      'hud-x': `${left}px`, 'hud-y': `${top}px`,
      'hud-width': `${(width - left - right) / scale}px`,
      'hud-height': `${(height - top - bottom) / scale}px`
    })) style.setProperty(`--${key}`, value);
    document.querySelector('#hud').style.transform = `translate(${left}px, ${top}px) scale(${scale})`;
    window.dispatchEvent(new CustomEvent('hud:screen'));
    return layout;
  }
  function accept(next) {
    if (!next || !Number.isFinite(next.revision) || next.revision < screen.revision) return;
    screen = next; last = ''; requestId++; measure();
  }
  async function post(name, data) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    try {
      const r = await fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data), signal: controller.signal
      });
      if (!r.ok) throw new Error('NUI callback failed');
      return await r.json();
    } finally { clearTimeout(timeout); }
  }
  function syncRadar() {
    if (!native || timer) return;
    timer = setTimeout(async () => {
      timer = null;
      const el = document.querySelector('.compass-ring');
      const b = el.getBoundingClientRect();
      if (!b.width || !b.height) return;

      const aperture = el.offsetWidth ? b.width * el.clientWidth / el.offsetWidth : b.width;
      const payload = { revision: screen.revision,
        cx: (b.left + b.width / 2) / innerWidth, cy: (b.top + b.height / 2) / innerHeight,
        diameter: aperture / innerHeight };
      const signature = JSON.stringify(payload);
      if (signature === last) return;
      last = signature;
      const id = ++requestId;
      try {
        const result = await post('displayRadarLayout', payload);
        if (id !== requestId) return;
        if (result.screen) accept(result.screen);
        if (!result.ok) { last = ''; syncRadar(); }
      } catch {
        if (id === requestId) { last = ''; timer = setTimeout(() => { timer = null; syncRadar(); }, 1000); }
      }
    }, 40);
  }
  async function ready() {
    try {
      const response = await post('displayReady', {});
      if (!response.screen) throw new Error('Screen is not ready');
      accept(response.screen);
    } catch { setTimeout(ready, 1000); }
  }
  window.CoderaDisplay = { get layout() { return layout; }, measure, syncRadar };
  window.addEventListener('message', ({ data }) => {
    if (data?.action === 'displayUpdate') accept(data.screen);
    if (data?.action === 'hudResync') { last = ''; measure(); }
  });
  window.addEventListener('resize', () => { last = ''; measure(); });
  measure();
  if (native) ready();
})();
