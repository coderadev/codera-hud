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

    window.addEventListener('message', ({ data }) => {
        if (data.action === 'updateCompassHeading') {
            elements.compass.style.display = 'flex';
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
