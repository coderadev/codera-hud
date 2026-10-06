(() => {
    'use strict';

    /* ------------------------------------------------------------------
       NUI bridge
    ------------------------------------------------------------------ */
    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'codera-hud';

    const post = (name, body = {}) => fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body)
    })
        .then((response) => response.text())
        .then((text) => {
            try { return JSON.parse(text); } catch (error) { return text; }
        })
        .catch(() => null);

    /* ------------------------------------------------------------------
       State
    ------------------------------------------------------------------ */
    let settings = null;
    let zoom = { value: 0, min: 300, max: 1400 };
    let saveTimer = null;

    const $ = (id) => document.getElementById(id);
    const body = document.body;

    const menu = $('hs-menu');
    const editor = $('hs-editor');

    const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

    const getPath = (path) => path.split('.').reduce((node, key) => (node ? node[key] : undefined), settings);
    const setPath = (path, value) => {
        const keys = path.split('.');
        const last = keys.pop();
        const node = keys.reduce((parent, key) => parent[key], settings);
        node[last] = value;
    };

    /* ------------------------------------------------------------------
       Applying settings to the HUD
    ------------------------------------------------------------------ */
    // `true` in a setting means "visible"; a false value adds the hide class.
    const HIDE_CLASSES = {
        'map.showMinimap': 'hs-no-map',
        'map.showHeading': 'hs-no-heading',
        'map.showLocation': 'hs-no-location',
        'map.showWaypoint': 'hs-no-waypoint',
        'player.showVoice': 'hs-no-voice',
        'player.showNeeds': 'hs-no-needs',
        'player.showArmor': 'hs-no-armor',
        'player.showStamina': 'hs-no-stamina',
        'player.showAmmo': 'hs-no-ammo',
        'player.crosshair': 'hs-no-crosshair',
        'vehicle.showGear': 'hs-no-gear',
        'vehicle.showFuel': 'hs-no-fuel',
        'vehicle.showIcons': 'hs-no-icons'
    };

    // Every HUD block that can be moved. `origin` is the corner it is anchored to,
    // `base` / `baseScale` keep the transform the stylesheet already used.
    const ELEMENTS = [
        {
            id: 'compass',
            label: 'Minimap & compass',
            sel: '#compass',
            origin: 'left top',
            base: '',
            baseScale: 1,
            measure: [
                { sel: '.compass__ring' },
                { sel: '.compass__degree' },
                { sel: '.compass__zone' },
                { sel: '.compass__street', text: true },
                { sel: '.compass__waypoint' }
            ]
        },
        {
            id: 'player',
            label: 'Health, armor & needs',
            sel: '#player-hud',
            origin: 'left bottom',
            base: '',
            baseScale: 1,
            measure: [
                { sel: '#player-hud' },
                { sel: '.player-hud__need-item' }
            ]
        },
        {
            id: 'status',
            label: 'Stamina & oxygen bars',
            sel: '.center-status',
            origin: 'center bottom',
            base: 'translateX(-50%)',
            baseScale: 1
        },
        {
            id: 'weapon',
            label: 'Ammo counter',
            sel: '#weapon-hud',
            origin: 'right top',
            base: '',
            baseScale: 1
        },
        {
            id: 'vehicle',
            label: 'Speedometer',
            sel: '#vehicle-hud',
            origin: 'right bottom',
            base: '',
            baseScale: 0.88,
            measure: [
                { sel: '.speedometer__bg' },
                { sel: '.speedometer__icons' }
            ]
        }
    ];

    const round = (value, places = 4) => Math.round(value * (10 ** places)) / (10 ** places);

    const applyLayout = (definition) => {
        const node = document.querySelector(definition.sel);
        const layout = settings && settings.layout && settings.layout[definition.id];
        if (!node || !layout) return;

        const tx = layout.x * window.innerWidth;
        const ty = layout.y * window.innerHeight;
        const scale = definition.baseScale * layout.scale;

        node.style.transformOrigin = definition.origin;
        node.style.transform = `translate(${tx}px, ${ty}px) ${definition.base} scale(${scale})`;
    };

    const applyAll = () => {
        if (!settings) return;

        Object.entries(HIDE_CLASSES).forEach(([path, className]) => {
            body.classList.toggle(className, getPath(path) === false);
        });

        const opacity = clamp(Number(settings.general.opacity) || 100, 30, 100) / 100;
        body.style.setProperty('--hs-opacity', String(opacity));

        ELEMENTS.forEach(applyLayout);
    };

    window.addEventListener('resize', () => {
        ELEMENTS.forEach(applyLayout);
    });

    /* ------------------------------------------------------------------
       Saving (debounced, everything is stored on the Lua side)
    ------------------------------------------------------------------ */
    const stateLabel = $('hs-save-state');

    const setSaveState = (saving) => {
        stateLabel.textContent = saving ? 'Saving…' : 'Saved';
        stateLabel.classList.toggle('is-saving', saving);
    };

    const flushSave = () => {
        if (saveTimer) {
            clearTimeout(saveTimer);
            saveTimer = null;
        }
        if (!settings) return Promise.resolve();
        return post('hudsettings_save', settings).then(() => setSaveState(false));
    };

    const scheduleSave = () => {
        setSaveState(true);
        if (saveTimer) clearTimeout(saveTimer);
        saveTimer = setTimeout(flushSave, 350);
    };

    const change = (path, value) => {
        setPath(path, value);
        applyAll();
        scheduleSave();
    };

    /* ------------------------------------------------------------------
       Menu pages
    ------------------------------------------------------------------ */
    const PAGES = {
        map: {
            eyebrow: 'Minimap',
            title: 'Map & compass',
            desc: 'Choose what shows around the minimap.',
            rows: [
                { type: 'toggle', path: 'map.showMinimap', title: 'Minimap & compass', desc: 'Turns the whole minimap block on or off.' },
                { type: 'toggle', path: 'map.showHeading', title: 'Heading degrees', desc: 'The number above the compass ring.' },
                { type: 'toggle', path: 'map.showLocation', title: 'Street & zone', desc: 'Location names under the map.' },
                { type: 'toggle', path: 'map.showWaypoint', title: 'Waypoint distance', desc: 'Distance to your map marker.' },
                { type: 'action', action: 'calibrate', title: 'Calibrate minimap', desc: 'Fix the map if it is off-centre inside the ring.', button: 'Start calibration' }
            ]
        },
        player: {
            eyebrow: 'On foot',
            title: 'Player status',
            desc: 'Show only the status parts you want to see.',
            rows: [
                { type: 'toggle', path: 'player.showVoice', title: 'Voice indicator', desc: 'Microphone icon with proximity range.' },
                { type: 'toggle', path: 'player.showArmor', title: 'Armor bar', desc: 'Next to the health bar.' },
                { type: 'toggle', path: 'player.showNeeds', title: 'Hunger & thirst', desc: 'The two small need meters.' },
                { type: 'toggle', path: 'player.showStamina', title: 'Stamina bar', desc: 'Shown while you run.' },
                { type: 'toggle', path: 'player.showAmmo', title: 'Ammo counter', desc: 'Magazine and reserve ammo.' },
                { type: 'toggle', path: 'player.crosshair', title: 'Custom crosshair', desc: 'Off brings back the default GTA crosshair.' }
            ]
        },
        vehicle: {
            eyebrow: 'Driving',
            title: 'Vehicle',
            desc: 'Set up the speedometer.',
            rows: [
                {
                    type: 'segment',
                    path: 'vehicle.unit',
                    title: 'Speed unit',
                    desc: 'Auto follows the server setting.',
                    options: [['auto', 'Auto'], ['mph', 'MPH'], ['kmh', 'KM/H']]
                },
                { type: 'toggle', path: 'vehicle.showGear', title: 'Gear', desc: 'Current gear in the middle of the dial.' },
                { type: 'toggle', path: 'vehicle.showFuel', title: 'Fuel gauge', desc: 'Curved fuel bar and pump icon.' },
                { type: 'toggle', path: 'vehicle.showIcons', title: 'Status icons', desc: 'Lights, seatbelt and door lock.' }
            ]
        },
        general: {
            eyebrow: 'Everything else',
            title: 'General',
            desc: 'Settings that apply to the whole HUD.',
            rows: [
                { type: 'range', path: 'general.opacity', min: 30, max: 100, unit: '%', title: 'HUD opacity', desc: 'Lower it to make the HUD less distracting.' },
                { type: 'toggle', path: 'general.snap', title: 'Snap to grid', desc: 'Makes dragging in the layout editor land on even steps.' },
                { type: 'action', action: 'cinematic', title: 'Cinematic mode', desc: 'Hides the HUD and adds black bars. Run /cinematic to exit.', button: 'Toggle' }
            ]
        }
    };

    const dynamicPage = $('hs-page-dynamic');
    const layoutPage = $('hs-page-layout');
    const pageName = $('hs-page-name');
    let currentPage = 'layout';

    const el = (tag, className, text) => {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    };

    const paintRange = (input) => {
        const span = Number(input.max) - Number(input.min);
        const percent = span > 0 ? ((Number(input.value) - Number(input.min)) / span) * 100 : 0;
        input.style.setProperty('--p', `${percent}%`);
    };

    const buildControl = (row) => {
        const control = el('div', 'hs-row__control');

        if (row.type === 'toggle') {
            const button = el('button', 'hs-switch');
            button.type = 'button';
            button.setAttribute('role', 'switch');
            button.setAttribute('aria-label', row.title);
            const sync = () => button.setAttribute('aria-checked', String(getPath(row.path) !== false));
            sync();
            button.addEventListener('click', () => {
                change(row.path, getPath(row.path) === false);
                sync();
            });
            control.append(button);
        } else if (row.type === 'segment') {
            const group = el('div', 'hs-seg');
            group.setAttribute('role', 'group');
            group.setAttribute('aria-label', row.title);
            row.options.forEach(([value, label]) => {
                const button = el('button', '', label);
                button.type = 'button';
                button.dataset.value = value;
                button.addEventListener('click', () => {
                    change(row.path, value);
                    group.querySelectorAll('button').forEach((item) => {
                        item.setAttribute('aria-pressed', String(item.dataset.value === value));
                    });
                });
                group.append(button);
            });
            group.querySelectorAll('button').forEach((item) => {
                item.setAttribute('aria-pressed', String(item.dataset.value === getPath(row.path)));
            });
            control.append(group);
        } else if (row.type === 'range') {
            const wrap = el('div', 'hs-range');
            const input = el('input');
            input.type = 'range';
            input.min = row.min;
            input.max = row.max;
            input.step = 1;
            input.value = getPath(row.path);
            input.setAttribute('aria-label', row.title);
            const output = el('output', '', `${input.value}${row.unit || ''}`);
            paintRange(input);
            input.addEventListener('input', () => {
                output.textContent = `${input.value}${row.unit || ''}`;
                paintRange(input);
                change(row.path, Number(input.value));
            });
            wrap.append(input, output);
            control.append(wrap);
        } else if (row.type === 'zoom') {
            const wrap = el('div', 'hs-range');
            const input = el('input');
            input.type = 'range';
            input.min = zoom.min;
            input.max = zoom.max;
            input.step = 50;
            input.value = zoom.value > 0 ? zoom.value : 1100;
            input.setAttribute('aria-label', row.title);
            const output = el('output', '', zoom.value > 0 ? String(zoom.value) : 'Default');
            const reset = el('button', 'hs-btn hs-btn--line', 'Reset');
            reset.type = 'button';
            paintRange(input);
            input.addEventListener('input', () => {
                output.textContent = input.value;
                paintRange(input);
                post('hudsettings_zoom', { value: Number(input.value) });
            });
            reset.addEventListener('click', () => {
                input.value = 1100;
                output.textContent = 'Default';
                paintRange(input);
                post('hudsettings_zoom', { value: 0 });
            });
            wrap.append(input, output);
            control.append(wrap, reset);
        } else if (row.type === 'action') {
            const button = el('button', 'hs-btn hs-btn--line', row.button);
            button.type = 'button';
            button.addEventListener('click', () => {
                if (row.action === 'calibrate') post('hudsettings_calibrate');
                if (row.action === 'cinematic') post('hudsettings_cinematic');
            });
            control.append(button);
        }

        return control;
    };

    const renderPage = (key) => {
        const page = PAGES[key];
        dynamicPage.replaceChildren();

        const head = el('header', 'hs-page__head');
        head.append(el('span', 'hs-eyebrow', page.eyebrow), el('h2', '', page.title), el('p', '', page.desc));

        const rows = el('div', 'hs-rows');
        page.rows.forEach((row) => {
            const item = el('div', 'hs-row');
            const text = el('div', 'hs-row__text');
            text.append(el('strong', '', row.title), el('span', '', row.desc));
            item.append(text, buildControl(row));
            rows.append(item);
        });

        dynamicPage.append(head, rows);
    };

    const showPage = (key) => {
        currentPage = key;

        document.querySelectorAll('.hs-nav__item').forEach((item) => {
            const active = item.dataset.page === key;
            item.classList.toggle('is-active', active);
            item.setAttribute('aria-selected', String(active));
            if (active) pageName.textContent = item.querySelector('span').textContent;
        });

        const isLayout = key === 'layout';
        layoutPage.hidden = !isLayout;
        dynamicPage.hidden = isLayout;
        if (!isLayout) renderPage(key);
        $('hs-main').scrollTop = 0;
    };

    document.querySelectorAll('.hs-nav__item').forEach((item) => {
        item.addEventListener('click', () => showPage(item.dataset.page));
    });

    /* ------------------------------------------------------------------
       Reset buttons (two clicks: the first one arms it)
    ------------------------------------------------------------------ */
    const armable = (button, idleText, armedText, run) => {
        let timer = null;
        const disarm = () => {
            button.classList.remove('is-armed');
            button.textContent = idleText;
            timer = null;
        };
        button.addEventListener('click', async () => {
            if (!timer) {
                button.classList.add('is-armed');
                button.textContent = armedText;
                timer = setTimeout(disarm, 3000);
                return;
            }
            clearTimeout(timer);
            disarm();
            await run();
        });
    };

    const applyReply = (reply) => {
        if (!reply || typeof reply !== 'object' || !reply.settings) return;
        settings = reply.settings;
        if (reply.zoom) zoom = reply.zoom;
        applyAll();
        if (currentPage !== 'layout') renderPage(currentPage);
        setSaveState(false);
    };

    armable($('hs-reset-layout'), 'Reset HUD', 'Click again to confirm', async () => {
        if (saveTimer) await flushSave();
        applyReply(await post('hudsettings_reset', { scope: 'layout' }));
    });

    armable($('hs-reset-all'), 'Reset all settings', 'Click again to confirm', async () => {
        if (saveTimer) await flushSave();
        applyReply(await post('hudsettings_reset', { scope: 'all' }));
    });

    /* ------------------------------------------------------------------
       Layout editor
    ------------------------------------------------------------------ */
    const handlesRoot = $('hs-handles');
    const sizeInput = $('hs-size');
    const sizeOutput = $('hs-size-out');
    const selectedName = $('hs-sel-name');

    const handles = new Map();
    let selectedId = ELEMENTS[0].id;
    let drag = null;
    let frame = null;

    const HANDLE_PAD = 6;
    const SNAP_STEP = 0.005; // 0.5% of the screen

    // Bounding box of everything that visibly belongs to an element.
    const measure = (definition) => {
        const parts = definition.measure || [{ sel: definition.sel }];
        let left = Infinity;
        let top = Infinity;
        let right = -Infinity;
        let bottom = -Infinity;

        parts.forEach((part) => {
            document.querySelectorAll(part.sel).forEach((node) => {
                let rect;
                if (part.text) {
                    const range = document.createRange();
                    range.selectNodeContents(node);
                    rect = range.getBoundingClientRect();
                } else {
                    rect = node.getBoundingClientRect();
                }
                if (rect.width < 1 || rect.height < 1) return;
                left = Math.min(left, rect.left);
                top = Math.min(top, rect.top);
                right = Math.max(right, rect.right);
                bottom = Math.max(bottom, rect.bottom);
            });
        });

        return Number.isFinite(left) ? { left, top, right, bottom } : null;
    };

    const buildHandles = () => {
        handlesRoot.replaceChildren();
        handles.clear();

        ELEMENTS.forEach((definition) => {
            const handle = el('div', 'hs-handle');
            handle.dataset.id = definition.id;
            handle.append(el('span', '', definition.label));
            handle.addEventListener('pointerdown', (event) => startDrag(event, definition));
            handlesRoot.append(handle);
            handles.set(definition.id, handle);
        });
    };

    const positionHandles = () => {
        ELEMENTS.forEach((definition) => {
            const handle = handles.get(definition.id);
            const rect = measure(definition);
            if (!handle || !rect) return;

            handle.style.left = `${rect.left - HANDLE_PAD}px`;
            handle.style.top = `${rect.top - HANDLE_PAD}px`;
            handle.style.width = `${rect.right - rect.left + (HANDLE_PAD * 2)}px`;
            handle.style.height = `${rect.bottom - rect.top + (HANDLE_PAD * 2)}px`;
        });

        frame = requestAnimationFrame(positionHandles);
    };

    const select = (id) => {
        selectedId = id;
        const definition = ELEMENTS.find((item) => item.id === id);
        const layout = settings.layout[id];

        handles.forEach((handle, handleId) => handle.classList.toggle('is-selected', handleId === id));
        selectedName.textContent = definition.label;
        sizeInput.value = Math.round(layout.scale * 100);
        sizeOutput.textContent = `${sizeInput.value}%`;
        paintRange(sizeInput);
    };

    function startDrag(event, definition) {
        if (event.button !== 0) return;
        event.preventDefault();

        select(definition.id);

        const handle = handles.get(definition.id);
        handle.setPointerCapture(event.pointerId);
        handle.classList.add('is-dragging');

        const layout = settings.layout[definition.id];
        drag = {
            id: definition.id,
            pointerId: event.pointerId,
            startX: event.clientX,
            startY: event.clientY,
            originX: layout.x,
            originY: layout.y,
            rect: measure(definition)
        };
    }

    const moveDrag = (event) => {
        if (!drag || event.pointerId !== drag.pointerId) return;

        const definition = ELEMENTS.find((item) => item.id === drag.id);
        const layout = settings.layout[drag.id];
        const width = window.innerWidth;
        const height = window.innerHeight;

        let x = drag.originX + ((event.clientX - drag.startX) / width);
        let y = drag.originY + ((event.clientY - drag.startY) / height);

        if (settings.general.snap) {
            x = Math.round(x / SNAP_STEP) * SNAP_STEP;
            y = Math.round(y / SNAP_STEP) * SNAP_STEP;
        }

        // Keep the whole element on screen.
        if (drag.rect) {
            const dx = clamp((x - drag.originX) * width, -drag.rect.left, width - drag.rect.right);
            const dy = clamp((y - drag.originY) * height, -drag.rect.top, height - drag.rect.bottom);
            x = drag.originX + (dx / width);
            y = drag.originY + (dy / height);
        }

        layout.x = round(x);
        layout.y = round(y);
        applyLayout(definition);
    };

    const endDrag = (event) => {
        if (!drag || event.pointerId !== drag.pointerId) return;

        const handle = handles.get(drag.id);
        if (handle) handle.classList.remove('is-dragging');
        drag = null;
        scheduleSave();
    };

    handlesRoot.addEventListener('pointermove', moveDrag);
    handlesRoot.addEventListener('pointerup', endDrag);
    handlesRoot.addEventListener('pointercancel', endDrag);

    sizeInput.addEventListener('input', () => {
        const definition = ELEMENTS.find((item) => item.id === selectedId);
        settings.layout[selectedId].scale = round(Number(sizeInput.value) / 100);
        sizeOutput.textContent = `${sizeInput.value}%`;
        paintRange(sizeInput);
        applyLayout(definition);
        scheduleSave();
    });

    $('hs-el-reset').addEventListener('click', () => {
        const definition = ELEMENTS.find((item) => item.id === selectedId);
        settings.layout[selectedId] = { x: 0, y: 0, scale: 1 };
        applyLayout(definition);
        select(selectedId);
        scheduleSave();
    });

    const nudge = (dxPx, dyPx) => {
        const definition = ELEMENTS.find((item) => item.id === selectedId);
        const layout = settings.layout[selectedId];
        layout.x = round(layout.x + (dxPx / window.innerWidth));
        layout.y = round(layout.y + (dyPx / window.innerHeight));
        applyLayout(definition);
        scheduleSave();
    };

    const openEditor = () => {
        menu.hidden = true;
        editor.hidden = false;
        body.classList.add('layout-editing');
        buildHandles();
        select(selectedId);
        if (frame === null) frame = requestAnimationFrame(positionHandles);
        editor.focus({ preventScroll: true });
    };

    const closeEditor = () => {
        if (frame !== null) {
            cancelAnimationFrame(frame);
            frame = null;
        }
        drag = null;
        editor.hidden = true;
        body.classList.remove('layout-editing');
        menu.hidden = false;
        flushSave();
        $('hs-panel').focus({ preventScroll: true });
    };

    $('hs-open-editor').addEventListener('click', openEditor);
    $('hs-editor-done').addEventListener('click', closeEditor);

    /* ------------------------------------------------------------------
       Open / close
    ------------------------------------------------------------------ */
    const requestClose = () => {
        flushSave();
        post('hudsettings_close');
    };

    $('hs-close').addEventListener('click', requestClose);

    document.addEventListener('keydown', (event) => {
        if (menu.hidden && editor.hidden) return;

        if (event.key === 'Escape') {
            event.preventDefault();
            if (!editor.hidden) closeEditor(); else requestClose();
            return;
        }

        if (!editor.hidden && event.target === document.body) {
            const step = event.shiftKey ? 10 : 1;
            const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
            if (moves[event.key]) {
                event.preventDefault();
                nudge(...moves[event.key]);
            }
        }
    });

    // Arrow keys also work while a handle or the toolbar button has focus,
    // except on the range input where they change the size.
    editor.addEventListener('keydown', (event) => {
        if (event.target === sizeInput || event.target === document.body) return;
        const step = event.shiftKey ? 10 : 1;
        const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
        if (moves[event.key]) {
            event.preventDefault();
            nudge(...moves[event.key]);
        }
    });

    const setBrand = (brand) => {
        $('hs-brand').textContent = `${String(brand || 'CODERA HUD').toUpperCase()} / Personal settings`;
    };

    window.addEventListener('message', ({ data }) => {
        if (data.action === 'hudSettingsOpen') {
            settings = data.settings;
            if (data.zoom) zoom = data.zoom;
            setBrand(data.brand);
            applyAll();
            setSaveState(false);
            showPage('layout');
            editor.hidden = true;
            body.classList.remove('layout-editing');
            menu.hidden = false;
            $('hs-panel').focus({ preventScroll: true });
        } else if (data.action === 'hudSettingsClose') {
            editor.hidden = true;
            body.classList.remove('layout-editing');
            menu.hidden = true;
            if (frame !== null) {
                cancelAnimationFrame(frame);
                frame = null;
            }
        }
    });

    /* ------------------------------------------------------------------
       Initial load: fetch the saved settings from the client script.
    ------------------------------------------------------------------ */
    const loadSettings = (attempt = 0) => {
        post('hudsettings_get').then((reply) => {
            if (reply && typeof reply === 'object' && reply.settings) {
                settings = reply.settings;
                if (reply.zoom) zoom = reply.zoom;
                setBrand(reply.brand);
                applyAll();
            } else if (attempt < 10) {
                setTimeout(() => loadSettings(attempt + 1), 1000);
            }
        });
    };

    loadSettings();
})();
