const scene = document.querySelector('.scene');
const journey = document.querySelector('.journey');
const device = document.querySelector('.macbook');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const stage = document.querySelector('[data-stage]');
const panel = document.querySelector('#stage-panel');
const notch = document.querySelector('.notch');
const tourPlay = document.querySelector('[data-tour-play]');
const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const clockText = value => Math.floor(value / 60) + ':' + String(Math.floor(value) % 60).padStart(2, '0');

let zoom = 0;
let scrollFrame = 0;
let cameraTravel = 1;
function drawCamera() {
  scrollFrame = 0;
  const top = journey.getBoundingClientRect().top;
  const bar = document.querySelector('.bar').offsetHeight;
  const height = scene.clientHeight;
  const width = scene.clientWidth;
  const deviceWidth = device.offsetWidth;
  cameraTravel = Math.max(1, Math.min(journey.clientHeight - height, height * .68));
  zoom = clamp((bar - top) / cameraTravel);
  const t = reduced.matches ? Number(zoom >= .6) : zoom * zoom * (3 - 2 * zoom);
  const cap = Math.min(height * .58 / device.offsetHeight, 1);
  const initialScale = Math.min(cap, (width - 24) / deviceWidth);
  const closeScale = width <= 480 ? Math.min(1.30, (width - 20) / 286)
    : width <= 800 ? Math.min(1.44, (width - 20) / 350)
    : Math.min(2.25, (width - 50) / 500);
  const initialY = Math.max(height * (width <= 480 ? .31 : .245),
    document.querySelector('.hero-copy').offsetHeight + height * .056 + 18);
  scene.style.setProperty('--device-y', (initialY * (1 - t) + height * .041 * t).toFixed(2) + 'px');
  scene.style.setProperty('--device-scale', (initialScale * (1 - t) + closeScale * t).toFixed(3));
  scene.style.setProperty('--copy-opacity', (1 - clamp(t * 1.8)).toFixed(3));
}
function requestCamera() {
  if (!scrollFrame) scrollFrame = requestAnimationFrame(drawCamera);
}
window.addEventListener('scroll', requestCamera, { passive: true });
window.addEventListener('resize', requestCamera);
reduced.addEventListener('change', requestCamera);
drawCamera();

function moveCloser() {
  if (zoom < .96) {
    const top = window.scrollY + journey.getBoundingClientRect().top - document.querySelector('.bar').offsetHeight;
    window.scrollTo({ top: top + cameraTravel, behavior: reduced.matches ? 'auto' : 'smooth' });
  }
}
function setOpen(open) {
  stage.dataset.open = String(open);
  notch.setAttribute('aria-expanded', String(open));
  notch.title = open ? '收起灵动岛' : '展开灵动岛';
  if (!open && panel.contains(document.activeElement)) notch.focus({ preventScroll: true });
  panel.inert = !open;
}
function toggleIsland() {
  const open = stage.dataset.open !== 'true';
  setOpen(open);
  if (open) moveCloser();
}
notch.addEventListener('click', toggleIsland);
document.querySelector('.explore').addEventListener('click', event => {
  event.preventDefault();
  setOpen(true);
  moveCloser();
});
document.querySelector('[data-close]').addEventListener('click', () => setOpen(false));
scene.addEventListener('click', event => {
  if (!event.target.closest('.island, .scene-controls') && stage.dataset.open === 'true') setOpen(false);
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && stage.dataset.open === 'true' && scene.getBoundingClientRect().bottom > 0) setOpen(false);
});
function pressOnly(buttons, selected) {
  buttons.forEach(button => button.setAttribute('aria-pressed', String(button === selected)));
}
const modules = [...panel.querySelectorAll('[data-module]')];
function showModule(button) {
  pressOnly(modules, button);
  panel.querySelectorAll('[data-pane]').forEach(pane => pane.hidden = pane.dataset.pane !== button.dataset.module);
}
modules.forEach((button, index) => {
  button.addEventListener('click', () => showModule(button));
  button.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const next = modules[(index + (event.key === 'ArrowRight' ? 1 : modules.length - 1)) % modules.length];
    showModule(next);
    next.focus();
  });
});

const tracks = [{
  title: '微光', length: 32, timed: true,
  cues: [[0, '窗外的灯'], [4.5, '把星光放在手心'], [8.7, '沿着夜色慢慢走'], [12.9, '等下一句响起'],
    [17.2, '让风把这段带走'], [21, '听见天亮的声音'], [25.4, '还想再唱一遍'], [29.2, '直到灯光渐远']]
}, {
  title: '夜航', length: 28, timed: false,
  cues: [[0, '风吹过窗沿'], [4, '夜色慢慢展开'], [8, '远处留一盏灯'], [12.2, '跟着光往前走'],
    [16.5, '沿途的声音'], [20.2, '都变成回声'], [24.3, '等天边微亮']]
}];
const compact = document.querySelector('[data-compact]');
const players = [...document.querySelectorAll('[data-player]')].map(holder => {
  holder.append(document.querySelector('#player-template').content.cloneNode(true));
  const root = holder.firstElementChild;
  return {
    root, rows: [...root.querySelectorAll('.lyrics-window p')], seek: root.querySelector('input'),
    track: root.querySelector('[data-track]'), time: root.querySelector('[data-time]'),
    left: root.querySelector('[data-remaining]'), play: root.querySelector('[data-play]'), glyphs: []
  };
});
let trackIndex = 0;
let position = 5.6;
let playing = !reduced.matches;
let hudActive = false;
let musicFrame = 0;
let lastTick = null;
let renderedIndex = -1;
let renderedTrack = -1;
let motionPreference = 'word';
let flow = 'rgb';
let compactRow;
let seeking = null;

function paintLine(index) {
  const { cues, timed } = tracks[trackIndex];
  const current = cues[index][1];
  const changedTrack = trackIndex !== renderedTrack;
  const delta = changedTrack ? 0 : Math.sign(index - renderedIndex);
  const usesWords = timed && motionPreference === 'word';
  const roles = ['before', 'previous', 'current', 'next', 'next-next', 'after'];
  for (const player of players) {
    player.glyphs = [];
    for (let rowIndex = index - 2; rowIndex <= index + 3; rowIndex++) {
      const offset = rowIndex - index + 2;
      const row = player.rows[(rowIndex + 6) % 6];
      const source = cues[rowIndex]?.[1];
      const role = roles[offset];
      const visible = offset >= 1 && offset <= 4 && Boolean(source);
      row.toggleAttribute('data-off', !visible);
      row.setAttribute('aria-hidden', String(!visible));
      row.style.setProperty('--row-y', ((offset - 1) * 28) + 'px');
      if (row.dataset.line !== String(rowIndex) || row.dataset.role === 'current' || role === 'current' || changedTrack) {
        row.dataset.line = rowIndex;
        row.textContent = source ?? '';
        if (role === 'current') {
          const text = document.createElement('span');
          text.className = 'current-text';
          if (usesWords) {
            for (const [offset, character] of Array.from(current).entries()) {
              const glyph = document.createElement('span');
              glyph.className = 'glyph';
              glyph.textContent = character;
              glyph.style.setProperty('--offset', offset * 24 + 'deg');
              text.append(glyph);
              player.glyphs.push(glyph);
            }
          } else text.textContent = current;
          row.replaceChildren(text);
        }
      }
      row.dataset.role = role;
    }
  }
  compact.textContent = current;
  compactRow?.cancel();
  if (delta && playing && !reduced.matches) {
    compactRow = compact.animate([{ transform: 'translateY(' + delta * 9 + 'px)', opacity: .4 },
      { transform: 'translateY(0)', opacity: 1 }], { duration: 290, easing: 'cubic-bezier(.22,.65,.2,1)' });
  }
  renderedIndex = index;
  renderedTrack = trackIndex;
}

function paintMusic() {
  const track = tracks[trackIndex];
  let index = track.cues.findIndex(([start]) => start > position) - 1;
  if (index < 0) index = track.cues.length - 1;
  if (index !== renderedIndex || trackIndex !== renderedTrack) paintLine(index);
  const lineStart = track.cues[index][0];
  const lineStop = track.cues[index + 1]?.[0] ?? track.length;
  const progress = clamp((position - lineStart) / (lineStop - lineStart));
  document.body.style.setProperty('--flow-position', ((1 - Math.cos(position * 1.25)) * 50).toFixed(1) + '%');
  document.body.style.setProperty('--flow-angle', (position * 77 % 360).toFixed(1) + 'deg');
  for (const player of players) {
    player.glyphs.forEach((glyph, i, glyphs) => {
      const p = clamp((progress * glyphs.length - i) * 1.55);
      glyph.style.setProperty('--sung', p.toFixed(2));
    });
    if (player.seek !== seeking) player.seek.value = position;
    const time = clockText(position);
    const left = '−' + clockText(Math.ceil(track.length - position));
    if (player.time.textContent !== time) player.time.textContent = time;
    if (player.left.textContent !== left) player.left.textContent = left;
  }
}
function loadTrack(next, start = 0) {
  trackIndex = (next + tracks.length) % tracks.length;
  position = start;
  const track = tracks[trackIndex];
  players.forEach(player => {
    player.root.dataset.trackId = trackIndex;
    player.track.textContent = track.title;
    player.seek.max = track.length;
    player.seek.value = position;
  });
  paintMusic();
}
function refreshPlayButtons() {
  scene.dataset.playing = String(playing);
  tourPlay.setAttribute('aria-pressed', String(playing));
  tourPlay.textContent = playing ? 'Ⅱ  暂停动画' : '▶  播放动画';
  players.forEach(({ play }) => {
    play.setAttribute('aria-label', playing ? '暂停播放' : '播放');
    play.textContent = playing ? 'Ⅱ' : '▶';
  });
}
function runMusic(now) {
  musicFrame = 0;
  if (!playing || document.hidden) return;
  if (lastTick !== null) {
    if (!seeking) position += (now - lastTick) / 1000;
    if (position >= tracks[trackIndex].length) loadTrack(trackIndex + 1);
    else paintMusic();
  }
  lastTick = now;
  musicFrame = requestAnimationFrame(runMusic);
}
function updateLoop() {
  cancelAnimationFrame(musicFrame);
  musicFrame = 0;
  lastTick = null;
  if (playing && !document.hidden) musicFrame = requestAnimationFrame(runMusic);
}
function setPlayback(enabled) {
  playing = enabled;
  if (playing && position >= tracks[trackIndex].length) loadTrack(trackIndex + 1);
  if (playing && compactRow?.playState === 'paused') compactRow.play();
  if (!playing && compactRow?.playState === 'running') compactRow.pause();
  refreshPlayButtons();
  updateLoop();
}
function togglePlay() { setPlayback(!playing); }
reduced.addEventListener('change', event => {
  if (event.matches) {
    compactRow?.cancel();
    setPlayback(false);
  }
});
document.addEventListener('visibilitychange', updateLoop);
tourPlay.addEventListener('click', togglePlay);
players.forEach(({ root, play, seek }) => {
  play.addEventListener('click', togglePlay);
  seek.addEventListener('pointerdown', () => seeking = seek);
  seek.addEventListener('input', () => {
    position = Number(seek.value);
    lastTick = null;
    paintMusic();
  });
  seek.addEventListener('change', endSeek);
  root.querySelectorAll('[data-skip]').forEach(button => button.addEventListener('click', () => loadTrack(trackIndex + Number(button.dataset.skip))));
});
function endSeek() {
  if (!seeking) return;
  seeking = null;
  lastTick = null;
}
window.addEventListener('pointerup', endSeek);
window.addEventListener('pointercancel', endSeek);
const flowButtons = [...document.querySelectorAll('[data-flow]')];
flowButtons.forEach(button => button.addEventListener('click', () => {
  flow = button.dataset.flow;
  document.body.dataset.flowMode = flow;
  pressOnly(flowButtons, button);
}));
document.querySelector('[data-timing]').addEventListener('change', event => {
  motionPreference = event.target.value;
  if (motionPreference === 'word' && !tracks[trackIndex].timed) loadTrack(0, position);
  renderedIndex = -1;
  paintMusic();
});
document.body.dataset.flowMode = flow;
loadTrack(0, position);
refreshPlayButtons();
updateLoop();

const hud = document.querySelector('.hud-demo');
const hudLevel = document.querySelector('#hud-level');
const levels = { volume: 62, brightness: 74 };
const hudButtons = [...hud.querySelectorAll('[data-hud]')];
function paintHud() {
  const mode = hud.dataset.mode;
  const value = levels[mode] + '%';
  hud.querySelector('[data-hud-icon]').textContent = mode === 'volume' ? '♪' : '☼';
  hudLevel.setAttribute('aria-label', mode === 'volume' ? '演示音量' : '演示亮度');
  hudLevel.value = levels[mode];
  hud.querySelector('[data-hud-fill]').style.width = value;
  hud.querySelector('[data-hud-value]').textContent = value;
}
hudButtons.forEach(button => button.addEventListener('click', () => {
  hud.dataset.mode = button.dataset.hud;
  pressOnly(hudButtons, button);
  paintHud();
}));
hudLevel.addEventListener('input', () => {
  levels[hud.dataset.mode] = Number(hudLevel.value);
  paintHud();
});
paintHud();

const timers = [...document.querySelectorAll('[data-timer]')].map(holder => {
  holder.append(document.querySelector('#timer-template').content.cloneNode(true));
  return holder.firstElementChild;
});
let remaining = 0;
let deadline = null;
let interval = 0;
let finished = false;
function stopCountdown() {
  deadline = null;
  clearInterval(interval);
}
function paintCountdown() {
  for (const timer of timers) {
    const setup = timer.querySelector('[data-presets]');
    const active = timer.querySelector('[data-active-timer]');
    const button = timer.querySelector('[data-timer-play]');
    const enabled = remaining > 0;
    if (enabled && setup.contains(document.activeElement)) {
      active.hidden = false;
      button.focus({ preventScroll: true });
    } else if (!enabled && active.contains(document.activeElement)) {
      setup.hidden = false;
      setup.querySelector('button').focus({ preventScroll: true });
    }
    setup.hidden = enabled;
    active.hidden = !enabled;
    timer.querySelector('[data-clock]').textContent = clockText(remaining).padStart(5, '0');
    button.textContent = deadline === null ? '继续' : '暂停';
    const notice = timer.querySelector('[data-finished]');
    const message = finished ? '倒计时结束' : '';
    if (notice.textContent !== message) notice.textContent = message;
  }
}
function tickCountdown() {
  remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
  if (!remaining) {
    finished = true;
    stopCountdown();
  }
  paintCountdown();
}
function runCountdown() {
  deadline = Date.now() + remaining * 1000;
  interval = setInterval(tickCountdown, 250);
  paintCountdown();
}
for (const timer of timers) {
  timer.querySelectorAll('[data-minutes]').forEach(button => button.addEventListener('click', () => {
    stopCountdown();
    finished = false;
    remaining = Number(button.dataset.minutes) * 60;
    runCountdown();
  }));
  timer.querySelector('[data-timer-play]').addEventListener('click', () => {
    if (deadline === null) runCountdown();
    else {
      tickCountdown();
      stopCountdown();
      paintCountdown();
    }
  });
  timer.querySelector('[data-add]').addEventListener('click', () => {
    if (deadline !== null) {
      deadline += 60000;
      tickCountdown();
    } else {
      remaining += 60;
      paintCountdown();
    }
  });
  timer.querySelector('[data-end]').addEventListener('click', () => {
    stopCountdown();
    remaining = 0;
    paintCountdown();
  });
}

const glass = document.querySelector('[data-glass]');
const glassModes = [...glass.querySelectorAll('[data-glass-mode]')];
glassModes.forEach(button => button.addEventListener('click', () => {
  glass.dataset.material = stage.dataset.material = button.dataset.glassMode;
  pressOnly(glassModes, button);
}));

if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => {
    entries.filter(entry => entry.isIntersecting).forEach(({ target }) => {
      target.classList.add('arrived');
      observer.unobserve(target);
    });
  }, { threshold: .12 });
  document.querySelectorAll('.feature-grid').forEach(section => observer.observe(section));
}
