(() => {
  'use strict';
  const prefs = window.CoderaPrefs;
  const overlay = document.querySelector('#hudSettings'), content = document.querySelector('#settingsContent');
  const confirmOverlay = document.querySelector('#hudConfirm');
  let opened = false, activeTab = 'layout', confirmAction, confirmFocus, heartbeat;
  const pages = {
    map: { kicker: 'NAVIGATION', title: 'MAP & COMPASS', fields: [
      ['minimap', 'Minimap', 'toggle'], ['compass', 'Compass frame', 'toggle'],
      ['heading', 'Heading readout', 'toggle'], ['location', 'Location & street', 'toggle'],
      ['waypoint', 'Waypoint distance', 'toggle'], ['navBackdrop', 'Navigation text backdrop', 'toggle']
    ] },
    status: { kicker: 'CHARACTER', title: 'PLAYER STATUS', fields: [
      ['playerStatus', 'Player status', 'toggle'], ['stamina', 'Stamina bar', 'toggle'],
      ['money', 'Cash & bank balances', 'toggle']
    ] },
    vehicle: { kicker: 'DRIVING', title: 'VEHICLE', fields: [
      ['speedometer', 'Speedometer', 'toggle'], ['vehicleControls', 'Vehicle control hints', 'toggle'],
      ['speedUnit', 'Speed unit', 'select']
    ] },
    general: { kicker: 'PREFERENCES', title: 'GENERAL', fields: [
      ['hud', 'Show HUD', 'toggle'], ['snap', 'Snap to grid', 'toggle'], ['safeArea', 'Screen edge inset', 'range']
    ] }
  };
  function tab(id) {
    activeTab = id;
    for (const button of document.querySelectorAll('[data-tab]')) {
      const active = button.dataset.tab === id;
      button.setAttribute('aria-selected', String(active)); button.tabIndex = active ? 0 : -1;
    }
    content.setAttribute('aria-labelledby', `tab-${id}`);
    content.scrollTop = 0;
    document.querySelector('#settingsCategory').textContent = id === 'layout' ? 'HUD LAYOUT' : pages[id].title;
    if (id === 'layout') {
      content.innerHTML = `<div class="settings-page-heading"><small>POSITION &amp; SIZE</small><h2>CUSTOMIZE HUD LAYOUT</h2><p>Move HUD elements around the screen and resize them independently.</p></div>
        <section class="layout-callout"><div><small>LIVE SCREEN EDITOR</small><h3>DRAG, MOVE AND RESIZE</h3><p>Select a HUD element, move it, then use the size slider for precise scaling.</p></div><button id="openLayoutEditor" class="accent-button">OPEN LAYOUT EDITOR</button></section>
        <div class="layout-steps"><div><span>01</span>SELECT ELEMENT</div><div><span>02</span>DRAG ANYWHERE</div><div><span>03</span>ADJUST SIZE</div><div><span>04</span>SAVED AUTOMATICALLY</div></div>`;
      document.querySelector('#openLayoutEditor').addEventListener('click', () => {
        overlay.classList.add('hidden');
        window.CoderaEditor.open(() => { overlay.classList.remove('hidden'); document.querySelector('#openLayoutEditor')?.focus(); });
      });
      return;
    }
    const page = pages[id];
    content.innerHTML = `<div class="settings-page-heading"><small>${page.kicker}</small><h2>${page.title}</h2></div>`;
    for (const [key, label, type] of page.fields) {
      const row = document.createElement('div'); row.className = 'setting-row';
      const name = document.createElement('label'); name.htmlFor = `setting-${key}`; name.textContent = label; row.append(name);
      let input;
      if (type === 'select') {
        input = document.createElement('select');
        for (const unit of ['MPH', 'KMH']) input.add(new Option(unit, unit));
      } else {
        input = document.createElement('input'); input.type = type === 'toggle' ? 'checkbox' : 'range';
        if (type === 'range') { input.min = 0; input.max = 10; input.step = .5; }
      }
      input.id = `setting-${key}`; input.dataset.option = key;
      if (type === 'range') {
        const group = document.createElement('div'); group.className = 'setting-range';
        const output = document.createElement('output'); output.htmlFor = input.id; output.id = `value-${key}`;
        group.append(input, output); row.append(group);
      } else row.append(input);
      input.addEventListener(type === 'range' ? 'input' : 'change', () => {
        prefs.option(key, type === 'toggle' ? input.checked : type === 'range' ? Number(input.value) : input.value);
      });
      content.append(row);
    }
    sync();
  }
  function sync() {
    for (const input of content.querySelectorAll('[data-option]')) {
      const key = input.dataset.option, value = prefs.data.options[key];
      if (input.type === 'checkbox') input.checked = value;
      else input.value = value;
      const output = document.querySelector(`#value-${key}`);
      if (output) output.textContent = `${value}%`;
    }
  }
  function open() {
    if (opened || !prefs.ready) return;
    opened = true;
    overlay.classList.remove('hidden'); tab('layout');
    document.querySelector('#closeSettings').focus();
    if (prefs.native) heartbeat = setInterval(() => prefs.request('prefsHeartbeat').catch(() => close()), 2000);
  }
  async function close(notify = true) {
    opened = false;
    clearInterval(heartbeat);
    window.CoderaEditor.finish(false);
    cancelConfirm();
    overlay.classList.add('hidden');
    prefs.flush();
    if (notify) {
      try { await prefs.request('prefsClose'); }
      catch { setTimeout(() => prefs.request('prefsClose').catch(() => {}), 500); }
    }
  }
  function confirm(title, description, action) {
    confirmAction = action; confirmFocus = document.activeElement;
    document.querySelector('#confirmTitle').textContent = title;
    document.querySelector('#confirmText').textContent = description;
    confirmOverlay.classList.remove('hidden'); document.querySelector('#cancelReset').focus();
  }
  function cancelConfirm() {
    confirmAction = null; confirmOverlay.classList.add('hidden');
    if (opened) confirmFocus?.focus();
  }
  document.querySelector('#confirmReset').addEventListener('click', () => { const action = confirmAction; cancelConfirm(); action?.(); prefs.flush(); });
  document.querySelector('#cancelReset').addEventListener('click', cancelConfirm);
  document.querySelector('#closeSettings').addEventListener('click', () => close());
  document.querySelector('#resetHud').addEventListener('click', () => confirm('RESET HUD?', 'Restore all HUD positions and sizes? Your other settings will stay the same.', () => prefs.resetLayout()));
  document.querySelector('#resetSettings').addEventListener('click', () => confirm('RESET ALL SETTINGS?', 'Restore all HUD preferences, positions and sizes to their defaults?', () => prefs.resetAll()));
  for (const button of document.querySelectorAll('[data-tab]')) {
    button.addEventListener('click', () => tab(button.dataset.tab));
    button.addEventListener('keydown', event => {
      if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      const buttons = [...document.querySelectorAll('[data-tab]')], index = buttons.indexOf(button);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
      tab(buttons[next].dataset.tab); buttons[next].focus();
    });
  }
  document.addEventListener('keydown', event => {
    if (!opened) return;
    const confirming = !confirmOverlay.classList.contains('hidden');
    if (event.key === 'Escape') {
      if (!confirming && window.CoderaLayout.editing) return;
      event.preventDefault(); event.stopImmediatePropagation();
      if (confirming) cancelConfirm(); else close();
    }
    if (event.key === 'Tab') {
      const scope = confirming ? confirmOverlay : window.CoderaLayout.editing ? document.querySelector('#hudEditor') : overlay;
      const items = [...scope.querySelectorAll('button:not(:disabled),input,select')].filter(el => el.tabIndex >= 0 && el.getClientRects().length);
      if (!items.length) return;
      const index = items.indexOf(document.activeElement);
      if (index === -1 || (!event.shiftKey && index === items.length - 1) || (event.shiftKey && index === 0)) {
        event.preventDefault(); (event.shiftKey ? items.at(-1) : items[0]).focus();
      }
    }
    if (confirming && event.key.startsWith('Arrow')) event.stopImmediatePropagation();
  }, true);
  window.addEventListener('hud:preferences', sync);
  window.addEventListener('hud:save-state', ({ detail }) => { document.querySelector('#settingsSaveState').textContent = detail; });
  window.addEventListener('hud:settings-ready', () => { if (opened) close(false); window.CoderaLayout.resetNative(); });
  window.addEventListener('message', ({ data }) => {
    if (data?.action === 'prefsShow') open();
    if (data?.action === 'prefsHide') close(false);
  });
  window.addEventListener('pagehide', () => { prefs.flush(); if (opened) prefs.request('prefsClose').catch(() => {}); });
  window.CoderaSettings = { open, close, confirm, get opened() { return opened; } };
  if (!prefs.native && new URLSearchParams(location.search).has('settings')) setTimeout(open, 50);
})();
