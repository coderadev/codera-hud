const $ = (selector) => document.querySelector(selector);
const FUEL_ICON = '<path d="M5.8 3.2h8.6c.8 0 1.3.6 1.3 1.4v15.8H4.5V4.6c0-.8.6-1.4 1.3-1.4Zm1.5 2.2v5.8h5.6V5.4H7.3Zm10.2.5 3.1 3.1v9.1a2 2 0 0 1-4 0v-4.9h-1v-2h2.8V9.7l-2.2-2.2 1.3-1.6Z" />';
const ELECTRIC_ICON = '<path d="M4.2 3.7h7.4c.7 0 1.1.5 1.1 1.2v15.3H3.1V4.9c0-.7.4-1.2 1.1-1.2Zm1.7 2.1v5h4V5.8h-4Zm3 6.6-3.2 4.4h2.2l-.5 2 3.2-4.5H8.4l.5-1.9Z" /><path d="M15.1 5h2v3.4h1.3V5h2v4.7l-1.9 1.9v3.2c0 2.8-1.6 4.4-4.4 4.4h-1.3V17h1.3c1.4 0 2.1-.7 2.1-2.1v-4.2l1.6-1.6h-2.7V5Z" />';
const LOCKED_ICON = '<path d="M6.1 10.1h11.8v10.6H6.1V10.1Zm2.2 0h2V7.2a1.7 1.7 0 0 1 3.4 0v2.9h2V7.2a3.7 3.7 0 0 0-7.4 0v2.9Z" />';
const UNLOCKED_ICON = '<path d="M6.1 10.1h11.8v10.6H6.1V10.1Zm2.2 0h2V7.2a1.7 1.7 0 0 1 3.1-1l1.6-1.2a3.7 3.7 0 0 0-6.7 2.2v2.9Z" />';
const state = { health: 100, armor: 100, hunger: 100, thirst: 100, stamina: 100, oxygen: 100, oxygenVisible: false, stress: 0, dev: false, talking: false, inVehicle: true, visible: true, navigation: true, speedometer: true, speed: 0, speedUnit: 'MPH', engine: true, rpm: .22, fuel: 100, electric: false, fuelType: 'gasoline', seatbelt: false, locked: false, waypoint: false, waypointDistance: 0, waypointUnit: 'mi', waypointBearing: 0, waypointOffRadar: false };

function buildRpmTicks() {
  const group = $('#rpmTicks');
  if (group.children.length) return;
  const tickCount = 28;
  const centerX = 74;
  const centerY = 75;
  const radius = 62;
  for (let index = 0; index < tickCount; index++) {
    const angle = 215 + (254 / (tickCount - 1)) * index;
    const radians = (angle - 90) * Math.PI / 180;
    const x = centerX + radius * Math.cos(radians);
    const y = centerY + radius * Math.sin(radians);
    const tick = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    tick.setAttribute('x', x - 4.7);
    tick.setAttribute('y', y - 2.05);
    tick.setAttribute('width', '9.4');
    tick.setAttribute('height', '4.1');
    tick.setAttribute('rx', '.35');
    tick.setAttribute('transform', `rotate(${angle} ${x} ${y})`);
    group.appendChild(tick);
  }
}

const COMPASS_RADIUS = 104;

const WAYPOINT_MARKER_RADIUS = 88;

const LOW_METER_THRESHOLD = 30;

function setWidth(selector, value) {
  const el = $(selector);
  const next = `${Math.max(0, Math.min(100, Number(value) || 0))}%`;
  if (el.style.width !== next) el.style.width = next;
}

function renderSpeed(value) {
  const speed = String(Math.max(0, Math.round(value))).padStart(3, '0');
  const firstLiveDigit = speed.search(/[1-9]/);
  const muted = firstLiveDigit === -1 ? speed.slice(0, 2) : speed.slice(0, firstLiveDigit);
  const live = firstLiveDigit === -1 ? speed.slice(2) : speed.slice(firstLiveDigit);
  $('#speed').innerHTML = `<span class="speed-muted">${muted}</span><span>${live}</span>`;
}

function gearLabel(value) {
  if (value === -1 || value === 'R') return 'R';
  if (value === 0 || value === '0' || value === 'N' || value === undefined || value === null) return 'N';
  return String(value);
}

function waypointLabel(distance, unit) {
  const value = Math.max(0, Number(distance) || 0);
  return unit === 'm' ? `${Math.round(value)} m` : `${value.toFixed(2)} mi`;
}

function setFuelMode(data) {
  const electric = data.electric === true || data.fuelType === 'electric';
  const vehicleHud = $('#vehicleHud');
  const fuelIcon = $('#fuelIcon');
  const mode = electric ? 'electric' : 'gasoline';

  vehicleHud.classList.toggle('electric', electric);
  vehicleHud.classList.toggle('gasoline', !electric);

  if (fuelIcon.dataset.mode !== mode) {
    fuelIcon.innerHTML = electric ? ELECTRIC_ICON : FUEL_ICON;
    fuelIcon.dataset.mode = mode;
  }
}

function setLockState(locked) {
  const lockIcon = $('#lockIcon');
  const next = locked ? 'locked' : 'unlocked';

  lockIcon.classList.toggle('active', locked);
  lockIcon.classList.toggle('unlocked', !locked);
  if (lockIcon.dataset.state !== next) {
    lockIcon.innerHTML = locked ? LOCKED_ICON : UNLOCKED_ICON;
    lockIcon.dataset.state = next;
  }
}

let compassTarget = 0;
let compassCurrent = 0;
let compassLastFrame = 0;
let compassLastLabel = -1;

function angleDelta(from, to) {
  return ((to - from + 540) % 360) - 180;
}

function setCompassTarget(heading) {
  compassTarget = ((Number(heading) || 0) % 360 + 360) % 360;
}

function animateCompass(now) {

  const dt = compassLastFrame ? Math.min((now - compassLastFrame) / 1000, 0.1) : 0;
  compassLastFrame = now;

  const delta = angleDelta(compassCurrent, compassTarget);
  if (Math.abs(delta) < 0.05) {
    compassCurrent = compassTarget;
  } else {
    compassCurrent = (compassCurrent + delta * (1 - Math.exp(-14 * dt)) + 360) % 360;
  }

  const label = Math.round(compassCurrent) % 360;
  if (label !== compassLastLabel) {
    headingEl.textContent = String(label).padStart(3, '0');
    compassLastLabel = label;
  }

  compassFrameEl.style.setProperty('--frame-angle', `${240 - compassCurrent}deg`);

  cardinalEls.forEach((cardinal) => {
    const bearing = Number(cardinal.dataset.bearing);
    const angleDeg = angleDelta(compassCurrent, bearing);
    const radians = angleDeg * Math.PI / 180;
    const x = Math.sin(radians) * COMPASS_RADIUS;
    const y = -Math.cos(radians) * COMPASS_RADIUS;
    cardinal.style.transform = `translate3d(${x}px, ${y}px, 0)`;
    cardinal.style.setProperty('--flag-angle', `${angleDeg - 90}deg`);
  });

  if (state.waypoint) {
    const waypointAngle = angleDelta(compassCurrent, Number(state.waypointBearing) || 0);
    const radians = waypointAngle * Math.PI / 180;
    waypointMarkerEl.style.transform = `translate3d(${Math.sin(radians) * WAYPOINT_MARKER_RADIUS}px, ${-Math.cos(radians) * WAYPOINT_MARKER_RADIUS}px, 0)`;
    waypointArrowEl.style.transform = `rotate(${waypointAngle}deg)`;
  }
  requestAnimationFrame(animateCompass);
}

const cardinalEls = [...document.querySelectorAll('.cardinal')];
const headingEl = $('#heading');
const compassFrameEl = $('.compass-frame');
const waypointMarkerEl = $('#waypointMarker');
const waypointArrowEl = $('#waypointDistance i');

const CONTROLS_FADE_MS = 350;

let controlsTimer = null;
let controlsFadeTimer = null;
let controlsInVehicle = null;

function showControls(el) {
  clearTimeout(controlsFadeTimer);
  controlsFadeTimer = null;
  el.classList.remove('hidden');

  void el.offsetWidth;
  el.classList.remove('fade-out');
}

function fadeOutControls(el) {
  if (el.classList.contains('hidden')) return;
  el.classList.add('fade-out');
  clearTimeout(controlsFadeTimer);
  controlsFadeTimer = setTimeout(() => {
    controlsFadeTimer = null;
    el.classList.add('hidden');
  }, CONTROLS_FADE_MS);
}

function updateVehicleControls(inVehicle) {
  if (inVehicle === controlsInVehicle) return;
  controlsInVehicle = inVehicle;

  clearTimeout(controlsTimer);
  controlsTimer = null;

  const el = $('#vehicleControls');
  if (!inVehicle) {
    fadeOutControls(el);
    return;
  }

  showControls(el);

  const timeout = Number(state.controlsTimeout);
  if (!Number.isFinite(timeout) || timeout <= 0) return;

  controlsTimer = setTimeout(() => {
    controlsTimer = null;
    fadeOutControls(el);
  }, timeout);
}

function render(data) {
  Object.assign(state, data);
  $('#hud').classList.toggle('hidden', !state.visible);
  setWidth('#healthFaceFill', state.health);
  setWidth('#armorFaceFill', state.armor);
  $('.meter.health').classList.toggle('low', Number(state.health) <= LOW_METER_THRESHOLD);
  $('.meter.armor').classList.toggle('low', Number(state.armor) <= LOW_METER_THRESHOLD);
  setWidth('#hungerBar', state.hunger);
  setWidth('#thirstBar', state.thirst);
  const stamina = Math.max(0, Math.min(100, Number(state.stamina ?? 100) || 0));
  setWidth('#staminaFill', stamina);
  $('#stamina').classList.toggle('hidden', stamina >= 100);
  $('#staminaIcon').classList.toggle('low', stamina < 20);
  const stress = Math.max(0, Math.min(100, Number(state.stress) || 0));
  const stressShown = stress > 0;
  const oxygen = Math.max(0, Math.min(100, Number(state.oxygen ?? 100) || 0));
  const oxygenShown = !!state.oxygenVisible || oxygen < 99.5;
  $('#stressStatus').classList.toggle('active', stressShown);
  $('#stressStatus').classList.toggle('hidden', !stressShown);
  $('#stressStatus').style.setProperty('--stress-fill', `${stress}%`);
  $('#oxygenStatus').classList.toggle('hidden', !oxygenShown);
  $('#oxygenStatus').classList.toggle('after-stress', stressShown);
  $('#oxygenStatus').style.setProperty('--oxygen-fill', `${100 - oxygen}%`);
  $('#devStatus').classList.toggle('hidden', !state.dev);
  $('#devStatus').classList.toggle('first', !stressShown && !oxygenShown);
  $('#devStatus').classList.toggle('after-one', stressShown !== oxygenShown);
  $('#statusDivider').classList.toggle('hidden', !stressShown && !oxygenShown && !state.dev);
  $('#voice').classList.toggle('talking', !!state.talking);
  updateVehicleControls(!!state.inVehicle);
  $('#vehicleHud').classList.toggle('hidden', !state.inVehicle || !state.speedometer);
  $('#navigation').classList.toggle('hidden', !state.navigation);
  $('#waypointDistance').classList.toggle('hidden', !state.waypoint);
  $('#waypointMarker').classList.toggle('hidden', !state.waypoint || !state.waypointOffRadar);
  if (state.waypoint) $('#waypointDistanceText').textContent = waypointLabel(state.waypointDistance, state.waypointUnit);
  if (data.speed !== undefined) renderSpeed(data.speed);
  if (data.speedUnit !== undefined) $('#speedUnit').textContent = String(data.speedUnit).toUpperCase();
  if (data.gear !== undefined) $('#gear').textContent = gearLabel(data.gear);
  if (data.electric !== undefined || data.fuelType !== undefined) setFuelMode(data);
  if (data.rpm !== undefined) {
    const rpm = Math.max(0, Math.min(1, Number(data.rpm) || 0));
    const activeTicks = Math.round(rpm * 28);
    [...$('#rpmTicks').children].forEach((tick, index) => tick.classList.toggle('active', index < activeTicks));
  }
  if (data.fuel !== undefined) {
    const fuel = Math.max(0, Math.min(100, Number(data.fuel) || 0));
    $('#fuelIcon').classList.toggle('low', fuel <= 20);
    $('#fuelArc').style.strokeDashoffset = String(100 * (1 - fuel / 100));
  }
  if (data.lights !== undefined) $('#lightsIcon').classList.toggle('active', data.lights > 0);
  if (data.locked !== undefined) setLockState(!!data.locked);
  if (data.seatbelt !== undefined) {
    $('#beltIcon').classList.toggle('active', !!data.seatbelt);
    $('#beltIcon').classList.toggle('alert', !data.seatbelt);
  }
  if (data.engine !== undefined) $('#engineLabel').textContent = data.engine ? 'STOP ENGINE' : 'START ENGINE';
  if (data.heading !== undefined) setCompassTarget(data.heading);
  if (data.navBackdrop !== undefined) $('#navigation').classList.toggle('backdrop', !!data.navBackdrop);
  if (data.zone !== undefined && data.zone) $('#zone').textContent = data.zone;
  if (data.street !== undefined && data.street) $('#street').textContent = data.crossing ? `${data.street} / ${data.crossing}` : data.street;
  window.dispatchEvent(new CustomEvent('hud:render', { detail: state }));
}

window.addEventListener('message', ({ data }) => {
  if (!data || !data.action) return;
  if (data.action === 'update' || data.action === 'sections' || data.action === 'status' || data.action === 'vehicle' || data.action === 'compass') render(data);
  if (data.action === 'visible') render({ visible: data.visible });
});

buildRpmTicks();
setCompassTarget(Number(headingEl.textContent));
compassCurrent = compassTarget;
requestAnimationFrame(animateCompass);

render(state);
