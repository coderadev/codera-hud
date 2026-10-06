(() => {
  'use strict';
  const layout = window.CoderaLayout, prefs = window.CoderaPrefs, math = window.HudLayoutMath;
  const panel = document.querySelector('#hudEditor');
  const scale = document.querySelector('#editorScale');
  const list = document.querySelector('#editorElements');
  const order = ['minimap', 'playerStatus', 'stamina', 'speedometer', 'location', 'money', 'vehicleControls'];

  const SNAP_INTERVAL = .005;
  let selected = 'playerStatus', controller, drag, panelDrag, onDone;
  function available(entry) { return !!entry && !entry.fixed && entry.enabled && (!entry.available || entry.available()); }
  function sync() {
    if (!layout.editing) return;
    for (const entry of layout.registry.values()) {
      entry.el.classList.toggle('hud-selected', entry.id === selected);
      const button = list.querySelector(`[data-select="${entry.id}"]`);
      if (button) {
        button.setAttribute('aria-pressed', String(entry.id === selected));
        button.disabled = !available(entry);
        button.title = available(entry) ? entry.label : 'No balance data from the framework';
      }
    }
    const entry = layout.registry.get(selected), pos = layout.position(selected);
    scale.min = entry.min * 100; scale.max = entry.max * 100; scale.value = Math.round(pos.scale * 100);
    document.querySelector('#editorScaleValue').textContent = `${Math.round(pos.scale * 100)}%`;
    document.querySelector('#editorCoordinates').textContent = `X ${(pos.x * 100).toFixed(1)}   Y ${(pos.y * 100).toFixed(1)}`;
    document.querySelector('#editorSnap').checked = prefs.data.options.snap;
  }
  function select(id) {
    const entry = layout.registry.get(id);
    if (!entry || !available(entry)) return;
    selected = id; sync();
  }
  function release(commit = true) {
    if (drag) {
      try { drag.el.releasePointerCapture(drag.pointerId); } catch {  }
      drag = null;
      if (commit) { prefs.commit(); prefs.flush(); }
    }
    if (panelDrag) {
      try { panel.releasePointerCapture(panelDrag.pointerId); } catch {  }
      panelDrag = null;
    }
    document.body.classList.remove('hud-dragging');
  }
  function pointerDown(event) {
    if (event.button !== 0 || !document.querySelector('#hudConfirm').classList.contains('hidden')) return;
    if (event.target.closest('#editorPanelHandle')) {
      const b = panel.getBoundingClientRect();
      panelDrag = { pointerId: event.pointerId, x: event.clientX - b.left, y: event.clientY - b.top };
      panel.setPointerCapture(event.pointerId); event.preventDefault(); return;
    }
    const el = event.target.closest('[data-hud-element]');
    if (!el) return;
    const id = el.dataset.hudElement, entry = layout.registry.get(id);
    if (!available(entry)) return;
    select(id);
    const bounds = layout.rect(entry);
    drag = {
      id, el, pointerId: event.pointerId, offset: { x: event.clientX - bounds.left, y: event.clientY - bounds.top },
      size: { width: bounds.width, height: bounds.height }, scale: layout.position(id).scale
    };
    el.setPointerCapture(event.pointerId);
    document.body.classList.add('hud-dragging');
    event.preventDefault(); event.stopPropagation();
  }
  function pointerMove(event) {
    if (panelDrag?.pointerId === event.pointerId) {
      const b = panel.getBoundingClientRect();
      panel.style.left = `${math.clamp(event.clientX - panelDrag.x, 0, Math.max(0, innerWidth - b.width))}px`;
      panel.style.top = `${math.clamp(event.clientY - panelDrag.y, 0, Math.max(0, innerHeight - b.height))}px`;
      panel.style.transform = 'none'; return;
    }
    if (drag?.pointerId !== event.pointerId) return;
    const next = math.drag({ x: event.clientX, y: event.clientY }, drag.offset, drag.size, layout.viewport(), drag.scale, layout.margin(), prefs.data.options.snap ? SNAP_INTERVAL : 0);
    layout.move(drag.id, next, false);
    event.preventDefault();
  }
  function keydown(event) {
    if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); finish(); return; }
    if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.key) || event.target.matches('input, select, textarea')) return;
    event.preventDefault(); event.stopPropagation();
    const pos = layout.position(selected), step = event.shiftKey ? .01 : .001;
    if (event.key === 'ArrowLeft') pos.x -= step;
    if (event.key === 'ArrowRight') pos.x += step;
    if (event.key === 'ArrowUp') pos.y -= step;
    if (event.key === 'ArrowDown') pos.y += step;
    layout.move(selected, math.place(pos, layout.rect(layout.registry.get(selected)), layout.viewport(), layout.margin()));
  }
  function finish(returnToSettings = true) {
    if (!layout.editing) return;
    release();
    controller?.abort();
    prefs.flush();
    for (const entry of layout.registry.values()) entry.el.classList.remove('hud-selected');
    panel.classList.add('hidden');
    document.querySelector('#editorHelp').classList.add('hidden');
    layout.setEditing(false);
    prefs.request('prefsEditorMode', { editing: false }).catch(() => {});
    if (returnToSettings) onDone?.();
  }
  function open(done) {
    if (layout.editing) return;
    onDone = done;
    controller = new AbortController();
    const options = { signal: controller.signal };
    list.replaceChildren();
    const ids = [...new Set([...order, ...layout.registry.keys()])];
    for (const id of ids) {
      const entry = layout.registry.get(id);
      if (!entry || entry.fixed) continue;
      const button = document.createElement('button');
      button.type = 'button'; button.textContent = entry.label.toUpperCase(); button.dataset.select = id;
      button.addEventListener('click', () => select(id), options);
      list.append(button);
    }
    panel.style.removeProperty('left'); panel.style.removeProperty('top'); panel.style.removeProperty('transform');
    panel.classList.remove('hidden');
    document.querySelector('#editorHelp').classList.remove('hidden');
    layout.setEditing(true); select('playerStatus');
    prefs.request('prefsEditorMode', { editing: true }).catch(() => window.CoderaSettings.close());
    document.addEventListener('pointerdown', pointerDown, options);
    document.addEventListener('pointermove', pointerMove, options);
    document.addEventListener('pointerup', releasePointer, options);
    document.addEventListener('pointercancel', releasePointer, options);
    document.addEventListener('keydown', keydown, options);
    window.addEventListener('blur', () => release(), options);
    window.addEventListener('hud:layout-applied', sync, options);
    window.addEventListener('resize', () => {
      release();
      panel.style.removeProperty('left'); panel.style.removeProperty('top'); panel.style.removeProperty('transform');
    }, options);
    scale.addEventListener('input', () => {
      const pos = layout.position(selected), bounds = layout.rect(layout.registry.get(selected));
      const ratio = Number(scale.value) / 100 / pos.scale;
      pos.scale = Number(scale.value) / 100;
      layout.move(selected, math.place(pos, { width: bounds.width * ratio, height: bounds.height * ratio }, layout.viewport(), layout.margin()));
    }, options);
    scale.addEventListener('change', () => prefs.flush(), options);
    document.querySelector('#editorSnap').addEventListener('change', event => prefs.option('snap', event.target.checked), options);
    document.querySelector('#resetElement').addEventListener('click', () => {
      window.CoderaSettings.confirm('RESET ELEMENT?', `Restore ${layout.registry.get(selected).label} to its original position and size?`, () => prefs.resetElement(selected));
    }, options);
    document.querySelector('#resetLayout').addEventListener('click', () => {
      window.CoderaSettings.confirm('RESET ALL POSITIONS?', 'Restore the position and size of every HUD element?', () => prefs.resetLayout());
    }, options);
    document.querySelector('#finishEditor').addEventListener('click', () => finish(), options);
    list.querySelector('[data-select="playerStatus"]').focus();
  }
  function releasePointer(event) {
    if (drag?.pointerId === event.pointerId || panelDrag?.pointerId === event.pointerId) release();
  }
  window.CoderaEditor = { open, finish, select };
})();
