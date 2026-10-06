(() => {
  'use strict';
  const voice = document.querySelector('#voice');
  const input = document.querySelector('#chatInput');
  const panel = document.querySelector('#chatPanel');
  const messages = document.querySelector('#chatMessages');
  const suggestions = document.querySelector('#chatSuggestions');
  const native = typeof GetParentResourceName === 'function';
  const descriptions = new Map(), removed = new Set();
  let localCommands = [], serverCommands = [], matches = [], selected = 0;
  let opened = false, busy = false, recent = false, expiry, history = [], historyIndex = 0, draft = '';
  let config = { maxLength: 300, maxMessages: 60, messageLifetime: 8000 };
  const clean = value => String(value ?? '').replace(/\^[0-9]/g, '').slice(0, 4000);
  async function post(name, data = {}) {
    if (!native) return { ok: true };
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    try {
      const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data), signal: controller.signal
      });
      if (!response.ok) throw new Error('Chat request failed');
      return await response.json();
    } finally { clearTimeout(timeout); }
  }
  function layout() { window.CoderaLayout?.schedule(); }
  voice.addEventListener('transitionend', layout);
  function visibility() {
    panel.classList.toggle('hidden', !opened && !recent);
    suggestions.classList.toggle('hidden', !opened || !matches.length);
    messages.classList.toggle('hidden', !messages.children.length || (!opened && !recent));
  }
  function close() {
    opened = false;
    voice.classList.remove('chat-open');
    input.classList.add('hidden');
    input.blur(); input.value = '';
    matches = []; suggestions.replaceChildren();
    visibility(); layout();
  }
  function open() {
    opened = true; busy = false; selected = 0;
    historyIndex = history.length; draft = ''; input.value = '';
    voice.classList.add('chat-open'); input.classList.remove('hidden');
    renderSuggestions(); visibility(); layout();
    requestAnimationFrame(() => { if (opened) { input.focus(); messages.scrollTop = messages.scrollHeight; } });
  }
  function allSuggestions() {
    const combined = new Map();
    for (const item of [...localCommands, ...serverCommands]) {
      if (typeof item?.name === 'string') combined.set(item.name, item);
    }
    for (const [key, value] of descriptions) combined.set(key, value);
    return [...combined.values()].filter(item => !removed.has(item.name));
  }
  function complete(index = selected) {
    const match = matches[index];
    if (!match) return;
    input.value = match.name + ' '; selected = 0;
    input.focus(); renderSuggestions();
  }
  function renderSuggestions() {
    const query = input.value.trimStart().toLowerCase();
    const command = query.split(/\s/)[0];
    matches = query.startsWith('/') ? allSuggestions().filter(item =>
      query.includes(' ') ? item.name.toLowerCase() === command : item.name.toLowerCase().startsWith(command)
    ).sort((a, b) => a.name.localeCompare(b.name)).slice(0, 5) : [];
    selected = Math.max(0, Math.min(selected, matches.length - 1));
    suggestions.replaceChildren();
    matches.forEach((item, index) => {
      const row = document.createElement('button');
      row.type = 'button'; row.className = 'chat-suggestion'; row.tabIndex = -1;
      row.classList.toggle('selected', index === selected);
      row.setAttribute('role', 'option'); row.setAttribute('aria-selected', String(index === selected));
      const name = document.createElement('span'); name.className = 'chat-command'; name.textContent = clean(item.name);
      const help = document.createElement('span'); help.className = 'chat-help';
      help.textContent = `${clean(item.name)}${item.help ? ' - ' + clean(item.help) : ''}`;
      if (Array.isArray(item.params) && item.params.length) {
        const params = document.createElement('span'); params.className = 'chat-params';
        params.textContent = ' ' + item.params.map(p => `<${clean(p.name)}>${p.help ? ' ' + clean(p.help) : ''}`).join(' ');
        help.append(params);
      }
      row.append(name, help);
      row.addEventListener('mousedown', event => { event.preventDefault(); complete(index); });
      suggestions.append(row);
    });
    visibility();
  }
  function addMessage(raw) {
    const message = typeof raw === 'string' ? { args: [raw] } : raw;
    if (!message || !Array.isArray(message.args)) return;
    const args = message.args.map(clean);
    const row = document.createElement('div'); row.className = 'chat-message';
    if (args.length > 1) {
      const author = document.createElement('span'); author.className = 'chat-author';
      author.textContent = args.shift() + ': ';
      if (Array.isArray(message.color) && message.color.length === 3) {
        author.style.color = `rgb(${message.color.map(n => Math.max(0, Math.min(255, Number(n) || 0))).join(',')})`;
      }
      row.append(author);
    }
    row.append(document.createTextNode(args.join(' ')));
    messages.append(row);
    while (messages.children.length > config.maxMessages) messages.firstChild.remove();
    recent = true; clearTimeout(expiry);
    expiry = setTimeout(() => { recent = false; visibility(); }, config.messageLifetime);
    visibility(); messages.scrollTop = messages.scrollHeight;
  }
  input.addEventListener('input', () => { selected = 0; renderSuggestions(); });
  input.addEventListener('keydown', async event => {
    if (event.isComposing) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
      try { await post('coderaChatClose'); } catch {  }
    } else if (event.key === 'Enter') {
      event.preventDefault(); if (busy) return;
      const message = input.value.trim();
      if (!message) { close(); try { await post('coderaChatClose'); } catch {} return; }
      busy = true;
      try {
        const result = await post('coderaChatSubmit', { message });
        if (!result.ok) throw new Error('Chat unavailable');
        if (history.at(-1) !== message) history.push(message);
        if (history.length > 50) history.shift();
        if (!native && !message.startsWith('/')) addMessage({ args: ['YOU', message] });
        close();
      } catch { addMessage({ args: ['CHAT', 'Could not send. Please try again or press Escape.'] }); }
      finally { busy = false; }
    } else if (event.key === 'Tab') {
      event.preventDefault(); complete();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
      event.preventDefault(); const delta = event.key === 'ArrowUp' ? -1 : 1;
      if (matches.length && input.value.startsWith('/')) {
        selected = (selected + delta + matches.length) % matches.length; renderSuggestions();
      } else {
        if (historyIndex === history.length) draft = input.value;
        historyIndex = Math.max(0, Math.min(history.length, historyIndex + delta));
        input.value = historyIndex === history.length ? draft : history[historyIndex];
        renderSuggestions();
      }
    } else if (event.key === 'PageUp' || event.key === 'PageDown') {
      event.preventDefault(); messages.scrollTop += event.key === 'PageUp' ? -160 : 160;
    }
  });
  window.addEventListener('message', ({ data }) => {
    if (!data) return;
    switch (data.action) {
      case 'chatOpen': open(); break;
      case 'chatClose': close(); break;
      case 'chatConfig':
        config = { ...config, ...data.config };
        config.maxLength = Math.max(1, Math.min(1000, Number(config.maxLength) || 300));
        config.maxMessages = Math.max(1, Math.min(200, Number(config.maxMessages) || 60));
        config.messageLifetime = Math.max(1000, Number(config.messageLifetime) || 8000);
        input.maxLength = config.maxLength; break;
      case 'chatMessage': addMessage(data.message); break;
      case 'chatSuggestion': {
        const item = data.suggestion;
        if (typeof item?.name !== 'string') break;
        const previous = descriptions.get(item.name);
        descriptions.set(item.name, item.help || !previous ? item : previous);
        removed.delete(item.name); renderSuggestions(); break;
      }
      case 'chatCommands': localCommands = Array.isArray(data.commands) ? data.commands : []; renderSuggestions(); break;
      case 'chatServerCommands': serverCommands = Array.isArray(data.commands) ? data.commands : []; renderSuggestions(); break;
      case 'chatRemoveSuggestion': descriptions.delete(data.name); removed.add(data.name); renderSuggestions(); break;
      case 'chatClear': messages.replaceChildren(); recent = false; visibility(); break;
      case 'prefsShow': close(); break;
    }
  });
  setInterval(() => { if (opened) post('coderaChatHeartbeat').catch(() => {}); }, 2000);
  async function ready() {
    try { await post('coderaChatReady'); } catch { setTimeout(ready, 1000); }
  }
  ready();
})();
