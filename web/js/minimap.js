(() => {
    'use strict';

    const elements = {
        compass: document.getElementById('compass'),
        degree: document.getElementById('heading-degree'),
        street: document.getElementById('street'),
        zone: document.getElementById('zone'),
        letters: document.getElementById('compass-letters'),
        cardinalLetters: document.querySelectorAll('.compass__letter'),
        safezoneWarning: document.getElementById('safezone-warning'),
        waypoint: document.getElementById('compass-waypoint'),
        waypointArrow: document.getElementById('waypoint-arrow-icon'),
        waypointDistance: document.getElementById('waypoint-distance')
    };

    const directionAngles = {
        straight: 0,
        right: 90,
        left: -90,
        back: 180
    };

    let targetHeading = null;
    let renderedHeading = null;
    let displayedDegree = -1;
    let animationFrame = null;
    let lastFrameTime = null;

    const normalizeHeading = (heading) => ((heading % 360) + 360) % 360;
    const getShortestHeadingDelta = (from, to) => ((to - from + 540) % 360) - 180;

    const applyCompassHeading = (heading) => {
        const normalizedHeading = normalizeHeading(heading);
        const roundedHeading = Math.round(normalizedHeading) % 360;

        elements.letters.style.transform = `rotate(${-normalizedHeading}deg)`;
        elements.cardinalLetters.forEach((letter) => {
            letter.style.transform = `translate(-50%, -50%) rotate(${normalizedHeading}deg)`;
        });

        if (roundedHeading !== displayedDegree) {
            displayedDegree = roundedHeading;
            elements.degree.textContent = roundedHeading;
        }
    };

    const scheduleCompassFrame = () => {
        if (animationFrame === null) {
            animationFrame = requestAnimationFrame(renderCompassHeading);
        }
    };

    const renderCompassHeading = (timestamp) => {
        animationFrame = null;
        if (targetHeading === null) return;

        if (renderedHeading === null) {
            renderedHeading = targetHeading;
            applyCompassHeading(renderedHeading);
            lastFrameTime = null;
            return;
        }

        const elapsed = lastFrameTime === null ? 16.67 : Math.min(50, timestamp - lastFrameTime);
        lastFrameTime = timestamp;
        const delta = getShortestHeadingDelta(renderedHeading, targetHeading);

        if (Math.abs(delta) <= 0.02) {
            renderedHeading = targetHeading;
            applyCompassHeading(renderedHeading);
            lastFrameTime = null;
            return;
        }

        const blend = 1 - Math.exp(-elapsed / 28);
        renderedHeading = normalizeHeading(renderedHeading + (delta * blend));
        applyCompassHeading(renderedHeading);
        scheduleCompassFrame();
    };

    const updateCompassTarget = (heading) => {
        targetHeading = normalizeHeading(Number(heading) || 0);

        if (renderedHeading === null) {
            renderedHeading = targetHeading;
            applyCompassHeading(renderedHeading);
            return;
        }

        scheduleCompassFrame();
    };


    // ---------------------------------------------------------------------
    // Radar sync: measure the REAL compass ring in the browser and tell Lua
    // exactly where it is, so the GTA minimap always sits inside the circle
    // regardless of resolution, aspect ratio, safezone or HUD layout edits.
    // ---------------------------------------------------------------------
    const ring = document.querySelector('.compass__ring');
    const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'codera-hud';
    let screenRevision = null;
    let lastSent = null;
    let syncTimer = null;
    let retryCount = 0;

    const round5 = (value) => Math.round(value * 100000) / 100000;

    const post = (endpoint, body) => fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {})
    }).then((response) => response.json()).catch(() => null);

    const sendRadarLayout = async (force) => {
        if (!ring || elements.compass.style.display === 'none' || !elements.compass.style.display) return;
        if (screenRevision === null) return;

        const rect = ring.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return;

        const layout = {
            revision: screenRevision,
            cx: round5((rect.left + rect.width / 2) / window.innerWidth),
            cy: round5((rect.top + rect.height / 2) / window.innerHeight),
            diameter: round5(Math.max(rect.width, rect.height) / window.innerHeight),
            dx: round5(rect.width / window.innerWidth),
            dy: round5(rect.height / window.innerHeight),
            vw: window.innerWidth,
            vh: window.innerHeight,
            rw: Math.round(rect.width * 10) / 10,
            rh: Math.round(rect.height * 10) / 10,
            dpr: window.devicePixelRatio
        };

        if (!force && lastSent
            && lastSent.revision === layout.revision
            && Math.abs(lastSent.cx - layout.cx) < 0.0002
            && Math.abs(lastSent.cy - layout.cy) < 0.0002
            && Math.abs(lastSent.diameter - layout.diameter) < 0.0002) {
            return;
        }

        const reply = await post('hudRadarLayout', layout);
        if (reply && reply.ok) {
            lastSent = layout;
            retryCount = 0;
        } else if (reply && reply.screen && retryCount < 5) {
            // Screen changed while we were measuring: adopt the new revision and retry.
            retryCount += 1;
            screenRevision = reply.screen.revision;
            scheduleRadarSync(120, true);
        }
    };

    const scheduleRadarSync = (delay, force) => {
        clearTimeout(syncTimer);
        syncTimer = setTimeout(() => sendRadarLayout(force), delay);
    };

    const handleScreenChange = (screen) => {
        if (screen && typeof screen.revision === 'number') screenRevision = screen.revision;
        lastSent = null;
        retryCount = 0;
        // CEF resizes a moment after the game does; measure a few times to settle.
        [60, 300, 900].forEach((delay) => setTimeout(() => sendRadarLayout(true), delay));
    };

    window.addEventListener('resize', () => handleScreenChange(null));
    if (typeof ResizeObserver === 'function') {
        new ResizeObserver(() => scheduleRadarSync(150, false)).observe(document.documentElement);
    }
    // Layout editor moves/scales the compass through an inline transform.
    new MutationObserver(() => scheduleRadarSync(250, false))
        .observe(elements.compass, { attributes: true, attributeFilter: ['style'] });

    post('hudScreenReady').then((reply) => {
        if (reply && reply.screen) handleScreenChange(reply.screen);
    });

    window.addEventListener('message', ({ data }) => {
        if (data.action === 'hudScreen') {
            handleScreenChange(data.screen);
        } else if (data.action === 'updateCompassHeading') {
            if (elements.compass.style.display !== 'flex') {
                elements.compass.style.display = 'flex';
                scheduleRadarSync(50, true);
            }
            updateCompassTarget(data.heading);
        } else if (data.action === 'updateCompassDetails') {
            elements.street.textContent = data.street;
            elements.zone.textContent = data.zone;
        } else if (data.action === 'hideCompass') {
            elements.compass.style.display = 'none';
            targetHeading = null;
            renderedHeading = null;
            displayedDegree = -1;
            lastFrameTime = null;

            if (animationFrame !== null) {
                cancelAnimationFrame(animationFrame);
                animationFrame = null;
            }
        } else if (data.action === 'updateWaypoint') {
            elements.waypoint.style.display = 'flex';
            elements.waypointDistance.textContent = data.distance;
            const iconEl = elements.waypointArrow;
            iconEl.className = 'fa-solid fa-arrow-up compass__waypoint-icon';
            iconEl.style.transform = `rotate(${directionAngles[data.direction] ?? 0}deg)`;
        } else if (data.action === 'hideWaypoint') {
            elements.waypoint.style.display = 'none';
        } else if (data.action === 'showSafezoneWarning') {
            elements.safezoneWarning.style.display = 'flex';
        } else if (data.action === 'hideSafezoneWarning') {
            elements.safezoneWarning.style.display = 'none';
        }
    });
})();
