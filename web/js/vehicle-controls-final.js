(() => {
    'use strict';

    const elements = {
        hud: document.getElementById('vehicle-hud'),
        rpmProgress: document.getElementById('rpm-progress-path'),
        fuel: document.getElementById('fuel-path'),
        fuelBg: document.getElementById('fuel-bg'),
        fuelIcon: document.getElementById('fuel-icon'),
        fuelTypeIcon: document.getElementById('fuel-type-icon'),
        speed: document.getElementById('vehicle-speed'),
        speedUnit: document.getElementById('vehicle-speed-unit'),
        gear: document.getElementById('vehicle-gear'),
        lights: document.getElementById('lights-icon'),
        seatbelt: document.getElementById('seatbelt-icon'),
        lock: document.getElementById('lock-icon'),
        engine: document.getElementById('engine-container'),
        engineFill: document.getElementById('engine-fill'),
        engineIcon: document.getElementById('engine-icon'),
        nos: document.getElementById('nos-container'),
        nosFill: document.getElementById('nos-fill'),
        nosIcon: document.getElementById('nos-icon'),
        controlsBar: document.getElementById('vehicle-controls'),
        vcEngineKey: document.getElementById('vc-engine-key'),
        vcEngineLabel: document.getElementById('vc-engine-label')
    };

    let lastEngineHealth = 1000;
    let engineShowTimer = null;
    let lastRendered = {};

    const setIcon = (element, classNames, iconClass) => {
        element.className = `speedometer__icon ${classNames}`.trim();
        element.innerHTML = `<i class="${iconClass}"></i>`;
    };

    const hideEngine = () => {
        elements.engine.style.display = 'none';
    };

    const updateNos = (hasNos, level) => {
        if (!hasNos) {
            elements.nos.style.display = 'none';
            return;
        }
        const percentage = Math.max(0, Math.min(100, Number(level) || 0));
        elements.nos.style.display = 'flex';
        elements.nosFill.style.width = `${percentage}%`;
        elements.nosIcon.style.color = percentage <= 15 ? '#e74c3c' : '#ffffff';
    };

    const updateEngine = (health) => {
        const damagedNow = health < lastEngineHealth && health < 995;
        lastEngineHealth = health;

        if (health >= 995) {
            hideEngine();
            if (engineShowTimer) clearTimeout(engineShowTimer);
            return;
        }

        const percentage = Math.max(0, Math.min(100, (health / 1000) * 100));
        elements.engineFill.style.width = `${percentage}%`;
        elements.engineIcon.style.color = percentage <= 10 ? '#e74c3c' : '#ffffff';

        if (percentage <= 10) {
            elements.engine.style.display = 'flex';
            if (engineShowTimer) clearTimeout(engineShowTimer);
        } else if (damagedNow) {
            elements.engine.style.display = 'flex';
            if (engineShowTimer) clearTimeout(engineShowTimer);

            engineShowTimer = setTimeout(() => {
                if (lastEngineHealth > 100) hideEngine();
            }, 3000);
        }
    };

    const engineIconSvg = (pointingDown) => {
        const inner = `
            <rect x="5" y="2" width="24" height="30" rx="11" stroke="currentColor" stroke-width="3"/>
            <line x1="17" y1="9" x2="17" y2="16" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>
            <polygon points="9.5,19.5 24.5,19.5 17,28.5" fill="currentColor"/>
            <rect x="11" y="40" width="12" height="4" rx="2" fill="currentColor"/>
        `;
        const flip = pointingDown ? '' : ' transform="translate(0,46) scale(1,-1)"';
        return `<svg viewBox="0 0 34 46" width="26" height="35" fill="none" xmlns="http://www.w3.org/2000/svg"><g${flip}>${inner}</g></svg>`;
    };

    const updateVehicleHud = (data) => {
        elements.hud.style.display = 'flex';
        elements.controlsBar.style.display = data.controlsEnabled === false ? 'none' : 'flex';

        const engineOn = data.engineOn !== false;
        if (engineOn !== lastRendered.engineOn) {
            elements.vcEngineLabel.textContent = engineOn ? 'Stop Engine' : 'Start Engine';
            elements.vcEngineKey.innerHTML = engineIconSvg(engineOn);
            lastRendered.engineOn = engineOn;
        }

        const maxSpeed = Number(data.maxSpeed) || 240;
        const currentSpeed = Math.max(0, Number(data.speed) || 0);
        const fuel = Math.max(0, Math.min(100, Number(data.fuel) || 0));

        if (currentSpeed !== lastRendered.speed || maxSpeed !== lastRendered.maxSpeed) {
            const speedPercent = Math.min(100, (currentSpeed / maxSpeed) * 100);
            const speedOffset = 100 - speedPercent;
            elements.rpmProgress.style.strokeDashoffset = speedOffset;
            elements.rpmProgress.setAttribute('stroke-dashoffset', String(speedOffset));

            const speedString = currentSpeed.toString().padStart(3, '0');
            let speedHtml = '';
            for (let i = 0; i < 3; i++) {
                const isDim = (currentSpeed <= 0)
                    || (currentSpeed < 10 && i < 2)
                    || (currentSpeed < 100 && i < 1);
                const dimClass = isDim ? ' speedometer__digit--dim' : '';
                speedHtml += `<span class="speedometer__digit${dimClass}">${speedString[i]}</span>`;
            }
            elements.speed.innerHTML = speedHtml;

            lastRendered.speed = currentSpeed;
            lastRendered.maxSpeed = maxSpeed;
        }

        if (fuel !== lastRendered.fuel) {
            const fuelColor = fuel <= 20 ? '#e74c3c' : '#ffffff';
            elements.fuel.style.strokeDashoffset = 100 - fuel;
            elements.fuel.style.stroke = fuelColor;
            elements.fuelIcon.classList.toggle('speedometer__fuel-icon--low', fuel <= 20);
            if (elements.fuelBg) elements.fuelBg.style.stroke = fuelColor;
            lastRendered.fuel = fuel;
        }

        const electric = Boolean(data.electric);
        if (electric !== lastRendered.electric) {
            elements.fuelTypeIcon.className = electric ? 'fa-solid fa-bolt' : 'fa-solid fa-gas-pump';
            lastRendered.electric = electric;
        }

        const speedUnit = data.speedUnit || 'MPH';
        if (speedUnit !== lastRendered.speedUnit) {
            elements.speedUnit.textContent = speedUnit;
            lastRendered.speedUnit = speedUnit;
        }

        if (data.gear !== lastRendered.gear) {
            elements.gear.textContent = data.gear;
            lastRendered.gear = data.gear;
        }

        const lightsOn = Boolean(data.lights);
        if (lightsOn !== lastRendered.lights) {
            elements.lights.classList.toggle('speedometer__icon--lights', lightsOn);
            lastRendered.lights = lightsOn;
        }

        const seatbeltOn = Boolean(data.seatbelt);
        if (seatbeltOn !== lastRendered.seatbelt) {
            setIcon(
                elements.seatbelt,
                seatbeltOn ? 'speedometer__icon--seatbelt-on' : 'speedometer__icon--seatbelt-off',
                seatbeltOn ? 'fa-solid fa-user-check' : 'fa-solid fa-user-slash'
            );
            lastRendered.seatbelt = seatbeltOn;
        }

        const locked = Boolean(data.locked);
        if (locked !== lastRendered.locked) {
            setIcon(
                elements.lock,
                locked ? 'speedometer__icon--locked' : 'speedometer__icon--muted',
                locked ? 'fa-solid fa-lock' : 'fa-solid fa-unlock'
            );
            lastRendered.locked = locked;
        }

        const engineHealth = Number(data.engine) || 0;
        if (engineHealth !== lastRendered.engine) {
            updateEngine(engineHealth);
            lastRendered.engine = engineHealth;
        }

        const hasNos = Boolean(data.hasNos);
        const nosLevel = Number(data.nos) || 0;
        if (hasNos !== lastRendered.hasNos || nosLevel !== lastRendered.nos) {
            updateNos(hasNos, nosLevel);
            lastRendered.hasNos = hasNos;
            lastRendered.nos = nosLevel;
        }
    };

    const hideVehicleHud = () => {
        elements.hud.style.display = 'none';
        elements.controlsBar.style.display = 'none';
        hideEngine();
        elements.nos.style.display = 'none';
        lastEngineHealth = 1000;
        lastRendered = {};

        if (engineShowTimer) {
            clearTimeout(engineShowTimer);
            engineShowTimer = null;
        }
    };

    window.addEventListener('message', ({ data }) => {
        if (data.action === 'updateVehicleHud') {
            updateVehicleHud(data);
        } else if (data.action === 'hideVehicleHud') {
            hideVehicleHud();
        }
    });
})();
