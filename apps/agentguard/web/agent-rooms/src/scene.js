// three.js scene: one room per session, a robot that acts out the session's event queue.
// Rooms hold no data of their own beyond animation state; everything they show comes from the Store.
import { META, iconCanvas } from './icons.js';

const P = { bg: 0x120F1A, floor: 0x231F2B, wall: 0x3A3741, f1: 0x514E58, f2: 0x7D7B82, lite: 0xB5B4B8, white: 0xF7F6F6, pink: 0xD53F8C, red: 0xD12D50 };
const GLOW = 0xFFFFFE;
// Stations: where a robot stands to use each object [x, z, faceX, faceZ].
const ST = { bench: [0, 1.6, 0, -1], benchR: [1.3, 1.6, 0, -1], chair: [0, 2.4, 0, -1], skill: [-3.2, -3.5, 0, -1], memory: [-0.6, -3.5, 0, -1], files: [-4.5, -3.75, -1, 0], board: [3.6, -3.6, 0, -1], shell: [-4.0, -1.5, -1, 0], mcp: [-4.9, 2.6, -1, 0], web: [-3.9, .7, -1, 0], phone: [5.25, -3.35, 0, -1], other: [-4.0, 4.1, -1, 0], door: [5.2, 4.3, 0, 1], sub0: [4.1, -0.2, 0, -1], sub1: [5.1, -0.2, 0, -1] };
// Aisle rectangle around the workbench that robots walk along.
const R = { x0: -2.9, x1: 2.9, z0: -2.6, z1: 1.6 }, RW = 5.8, RD = 4.2, RL = 2 * (RW + RD);
const proj = p => { let x = Math.min(R.x1, Math.max(R.x0, p.x)), z = Math.min(R.z1, Math.max(R.z0, p.z)); if (x === p.x && z === p.z) { const d = [x - R.x0, R.x1 - x, z - R.z0, R.z1 - z], m = Math.min(...d); if (m === d[0]) x = R.x0; else if (m === d[1]) x = R.x1; else if (m === d[2]) z = R.z0; else z = R.z1; } return { x, z }; };
const par = q => { const e = 1e-6; if (Math.abs(q.z - R.z0) < e) return q.x - R.x0; if (Math.abs(q.x - R.x1) < e) return RW + q.z - R.z0; if (Math.abs(q.z - R.z1) < e) return RW + RD + R.x1 - q.x; return 2 * RW + RD + R.z1 - q.z; };
const at = t => { t = ((t % RL) + RL) % RL; if (t < RW) return { x: R.x0 + t, z: R.z0 }; if (t < RW + RD) return { x: R.x1, z: R.z0 + t - RW }; if (t < 2 * RW + RD) return { x: R.x1 - (t - RW - RD), z: R.z1 }; return { x: R.x0, z: R.z1 - (t - 2 * RW - RD) }; };
const route = (a, b) => {
  const pa = proj(a), pb = proj(b), ta = par(pa), tb = par(pb), fw = ((tb - ta) % RL + RL) % RL, dir = fw <= RL / 2 ? 1 : -1, dist = dir > 0 ? fw : RL - fw, pts = [pa];
  [0, RW, RW + RD, 2 * RW + RD].map(c => ({ c, d: dir > 0 ? ((c - ta) % RL + RL) % RL : ((ta - c) % RL + RL) % RL })).filter(o => o.d > 1e-6 && o.d < dist - 1e-6).sort((m, n) => m.d - n.d).forEach(o => pts.push(at(o.c)));
  pts.push(pb, { x: b.x, z: b.z }); return pts;
};
// Icon sign placement per object [x, y, z, orientation, size].
const PL = { bench: [2.43, .72, 0, 'x', .62], skill: [0, 3.06, .05, 'z', .64], memory: [0, 2.6, -.42, 'z', .7], files: [0, 2.4, -.42, 'z', .7], board: [-1.05, 2.42, .1, 'z', .6], shell: [-.77, 2.62, 0, 'x', .7], mcp: [.08, 2.5, 0, 'x', .6], web: [.42, .45, 0, 'x', .6], phone: [.47, .42, 0, 'x', .6], other: [.69, .31, 0, 'x', .5], subbench: [-.75, 1.2, -.45, 'tent', .55] };
export const SLOTS = 6;
const STALE_MS = 600000;

export function createScene(THREE, { stage, canvas: cv, overlay: ov, store, onSelect }) {
  const renderer = new THREE.WebGLRenderer({ canvas: cv, antialias: true, preserveDrawingBuffer: true });
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFShadowMap; renderer.setClearColor(P.bg);
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xffffff, 0x3A3741, 1.5));
  const sun = new THREE.DirectionalLight(0xfff4ea, 2.6); sun.position.set(20, 34, 36); sun.target.position.set(12.5, 0, 20); scene.add(sun, sun.target);
  sun.castShadow = true; sun.shadow.mapSize.set(4096, 4096); sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.03;
  Object.assign(sun.shadow.camera, { left: -34, right: 34, top: 40, bottom: -40, near: 1, far: 130 }); sun.shadow.radius = 3;
  const camera = new THREE.PerspectiveCamera(26, 1, 1, 800);

  const mats = {}, M = c => mats[c] || (mats[c] = new THREE.MeshStandardMaterial(c === P.pink ? { color: c, emissive: c, emissiveIntensity: .55, roughness: .5 } : c === GLOW ? { color: c, emissive: 0xffffff, emissiveIntensity: 1 } : c === P.bg ? { color: c, roughness: .22, metalness: .5 } : c === P.f2 || c === P.lite ? { color: c, roughness: .42, metalness: .4 } : c === P.floor ? { color: 0x2E2A36, roughness: .7 } : { color: c, roughness: .85 }));
  const B = (par, w, h, d, c, x, y, z) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), M(c)); m.position.set(x, y, z); m.userData.base = c; m.castShadow = m.receiveShadow = true; par.add(m); return m; };
  const el = cls => { const d = document.createElement('div'); d.className = cls; ov.appendChild(d); return d; };
  const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

  function plate(kind, s) {
    const mk = (bg, fg) => { const t = new THREE.CanvasTexture(iconCanvas(kind, bg, fg)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return new THREE.MeshBasicMaterial({ map: t }); };
    const mN = mk('#120F1A', '#F7F6F6'), mA = mk('#D53F8C', '#FFFFFF'), g = new THREE.Group();
    B(g, s + .08, s + .08, .04, P.lite, 0, 0, 0); const face = new THREE.Mesh(new THREE.PlaneGeometry(s, s), mN); face.position.z = .026; g.add(face);
    g.face = face; g.mN = mN; g.mA = mA; return g;
  }
  function makeBot(scale, parent) {
    const g = new THREE.Group(); parent.add(g); g.scale.setScalar(scale);
    const G = (p, geo, c, x, y, z) => { const m = new THREE.Mesh(geo, M(c)); m.position.set(x, y, z); m.castShadow = true; m.userData.base = c; p.add(m); return m; };
    const leg = x => { const p = new THREE.Group(); p.position.set(x, .5, 0); G(p, new THREE.CapsuleGeometry(.11, .3, 4, 14), P.f2, 0, -.25, 0); G(p, new THREE.BoxGeometry(.24, .1, .36), P.f1, 0, -.45, .05); g.add(p); return p; };
    const arm = x => { const p = new THREE.Group(); p.position.set(x, 1.2, 0); G(p, new THREE.SphereGeometry(.12, 14, 10), P.f2, 0, 0, 0); G(p, new THREE.CapsuleGeometry(.085, .4, 4, 14), P.white, 0, -.28, 0); G(p, new THREE.SphereGeometry(.1, 12, 10), P.f2, 0, -.56, 0); g.add(p); return p; };
    const legL = leg(-.17), legR = leg(.17), armL = arm(-.46), armR = arm(.46);
    G(g, new THREE.CapsuleGeometry(.33, .22, 6, 22), P.white, 0, .88, 0); G(g, new THREE.CylinderGeometry(.3, .3, .08, 22), P.f2, 0, .56, 0); G(g, new THREE.BoxGeometry(.2, .12, .04), P.pink, 0, 1, .32);
    const head = new THREE.Group(); head.position.set(0, 1.3, 0); g.add(head);
    G(head, new THREE.CylinderGeometry(.12, .14, .12, 14), P.f2, 0, .02, 0);
    G(head, new THREE.SphereGeometry(.4, 28, 20), P.white, 0, .36, 0).scale.set(1.08, .84, .96);
    G(head, new THREE.SphereGeometry(.34, 28, 18), P.bg, 0, .36, .1).scale.set(1.02, .62, .9);
    const eyes = [G(head, new THREE.SphereGeometry(.055, 12, 10), GLOW, -.14, .37, .4), G(head, new THREE.SphereGeometry(.055, 12, 10), GLOW, .14, .37, .4)];
    G(head, new THREE.CylinderGeometry(.02, .02, .2, 8), P.f1, 0, .78, 0); const tip = G(head, new THREE.SphereGeometry(.07, 14, 10), P.f1, 0, .92, 0);
    const carry = B(g, .4, .04, .5, P.pink, 0, 1.02, .55); carry.visible = false;
    return { g, legL, legR, armL, armR, head, eyes, tip, carry };
  }

  class Actor {
    constructor(room, scale, at) { this.room = room; this.s = scale; this.bot = makeBot(scale, room.g); this.x = at[0]; this.z = at[1]; this.ry = 0; this.todo = []; this.cur = null; this.pose = 'idle'; this.t = Math.random() * 9; this.path = []; this.where = ''; this.bub = el('bub'); this.bub.style.display = 'none'; }
    q(...c) { this.todo.push(...c); }
    busy() { return !!this.cur || this.todo.length > 0; }
    face(fx, fz) { this.ry = Math.atan2(fx, fz); }
    setCarry(c, shape) { const m = this.bot.carry; m.visible = c != null; if (c != null) { m.material = M(c); const s = shape === 'book' ? [.75, 3.2, .8] : shape === 'note' ? [.6, 1, .55] : [1, 1, 1]; m.scale.set(s[0], s[1], s[2]); } }
    speed() { return (this.sub ? this.sub.queue.length >= 3 : this.room.rush) ? 2.2 : 1; }
    update(dt) {
      this.t += dt; const k = this.speed();
      for (let n = 0; n < 6 && !this.cur && this.todo.length; n++) {
        const c = this.todo.shift();
        if (c.call) { c.call(); continue; }
        if (c.go) { if (c.go === this.where) continue; const s = ST[c.go]; this.path = route({ x: this.x, z: this.z }, { x: s[0], z: s[1] }); this.dest = s; this.where = ''; }
        if (c.pose) this.pose = c.pose; if (c.op !== undefined) this.op = c.op;
        c.el = 0; c.begin && c.begin(); this.cur = c;
      }
      const c = this.cur;
      if (c && c.go) {
        this.pose = 'walk'; let step = 3.4 * dt * k;
        while (step > 0 && this.path.length) { const p = this.path[0], dx = p.x - this.x, dz = p.z - this.z, d = Math.hypot(dx, dz); if (d < 1e-4) { this.path.shift(); continue; } this.ry = Math.atan2(dx, dz); const m = Math.min(step, d); this.x += dx / d * m; this.z += dz / d * m; step -= m; if (m === d) this.path.shift(); }
        if (!this.path.length) { this.face(this.dest[2], this.dest[3]); this.pose = 'idle'; this.where = c.go; this.cur = null; }
      } else if (c) {
        c.el += dt * k; c.tick && c.tick(dt, c);
        if (c.wait != null ? c.el >= c.wait : c.el >= (c.min || 0) && c.until()) { c.end && c.end(); this.cur = null; }
      }
      this.draw();
    }
    draw() {
      const b = this.bot, t = this.t, p = this.pose, carrying = b.carry.visible; let y = 0;
      [b.legL, b.legR, b.armL, b.armR, b.head].forEach(o => o.rotation.set(0, 0, 0));
      b.eyes.forEach(e => e.scale.y = 1); b.tip.material = M(P.f1); b.g.rotation.z = 0;
      if (carrying) { b.armL.rotation.x = b.armR.rotation.x = -1; }
      if (p === 'walk') { const s = Math.sin(t * 12); b.legL.rotation.x = s * .7; b.legR.rotation.x = -s * .7; if (!carrying) { b.armL.rotation.x = -s * .5; b.armR.rotation.x = s * .5; } y = Math.abs(s) * .06; }
      else if (p === 'operate') { const o = this.op, s = Math.sin;
        if (o === 'skill') { b.armR.rotation.x = -2.6 + s(t * 3) * .1; b.head.rotation.x = -.25; }
        else if (o === 'memory' || o === 'files') { b.armL.rotation.x = b.armR.rotation.x = -1.25 + s(t * 3) * .2; b.head.rotation.x = .2; }
        else if (o === 'phone') { b.armR.rotation.set(-2.5, 0, -.5); b.head.rotation.z = -.15; }
        else if (o === 'web') { b.armR.rotation.set(-1.5, 0, s(t * 2.5) * .5); }
        else if (o === 'mcp') { b.armR.rotation.x = -1.45; }
        else if (o === 'board') { b.armR.rotation.set(-2.2 + s(t * 11) * .12, 0, s(t * 3) * .25); }
        else if (o === 'other') { b.armL.rotation.x = -.9 + s(t * 7) * .3; b.armR.rotation.x = -.9 - s(t * 7) * .3; b.head.rotation.x = .35; }
        else { b.armL.rotation.x = -1.2 + s(t * 18) * .18; b.armR.rotation.x = -1.2 - s(t * 18) * .18; } }
      else if (p === 'think') { b.head.rotation.z = Math.sin(t * 2) * .1; b.tip.material = M(Math.sin(t * 6) > 0 ? P.pink : P.f1); }
      else if (p === 'wait') { b.armL.rotation.set(-.7, 0, .8); b.armR.rotation.set(-.7, 0, -.8); }
      else if (p === 'talk') { b.armR.rotation.x = -1.6 + Math.sin(t * 8) * .3; b.tip.material = M(P.pink); }
      else if (p === 'error') { b.tip.material = M(P.red); b.g.rotation.z = Math.sin(t * 40) * .08; }
      else if (p === 'sleep') { b.legL.rotation.x = b.legR.rotation.x = -1.45; b.head.rotation.x = .3 + Math.sin(t * 1.5) * .05; b.eyes.forEach(e => e.scale.y = .15); y = .2; }
      b.g.position.set(this.x, y, this.z); b.g.rotation.y = this.ry;
    }
    bubble() {
      const p = this.pose, r = this.room;
      if (p === 'operate' && this.run) {
        if (this.burst) return ['×' + this.burst.n, ''];
        const open = this.run.find(c => !c.done), sec = open ? (Date.now() - open.ts) / 1000 : 0;
        if (sec >= 4) return ['running ' + Math.floor(sec / 60) + ':' + String(Math.floor(sec % 60)).padStart(2, '0'), ''];
      }
      return p === 'think' ? ['· · ·', ''] : p === 'sleep' ? ['z z z', ''] : p === 'error' ? ['!', 'err'] : p === 'talk' && r.speech && !this.sub ? [r.speech, ''] : p === 'wait' ? ['waiting', ''] : null;
    }
    remove() { this.room.g.remove(this.bot.g); this.bub.remove(); }
  }

  // ---------- rooms ----------
  const rooms = Array(SLOTS).fill(null);
  const slotPos = i => new THREE.Vector3((i % 2) * 25, 0, Math.floor(i / 2) * 21);

  function buildRoom(i, ses) {
    const g = new THREE.Group(); g.position.copy(slotPos(i)); scene.add(g);
    const room = { i, ses, g, f: {}, act: {}, subs: [], cards: [], placed: new Set(), subCards: [], slotTop: {}, state: 'Idle', detail: '', speech: '', ringing: false, answer: false, rush: false, sweep: null, clock: 0 };
    B(g, 12, .3, 10, P.floor, 0, -.15, 0).userData.pick = 'room';
    B(g, 12.3, 3.2, .3, P.wall, -.15, 1.6, -5.15); B(g, .3, 3.2, 10, P.wall, -6.15, 1.6, 0);
    const F = (kind, x, z, build) => { const o = new THREE.Group(); o.position.set(x, 0, z); o.userData.pick = kind; o.ind = []; g.add(o); build(o); room.f[kind] = o; const q = PL[kind], pl = plate(kind, q[4]); pl.position.set(q[0], q[1], q[2]); if (q[3] === 'x') pl.rotation.y = Math.PI / 2; else if (q[3] === 'tent') pl.rotation.x = -.32; o.add(pl); o.plate = pl; return o; };
    const I = (o, m) => { o.ind.push(m); return m; };
    F('bench', 0, 0, o => { B(o, 4.8, .22, 2.4, P.f1, 0, 1, 0); [[-2.2, -1], [2.2, -1], [-2.2, 1], [2.2, 1]].forEach(([x, z]) => B(o, .2, .9, .2, P.wall, x, .45, z)); I(o, B(o, 4.8, .06, .08, P.f2, 0, 1.02, 1.2)); B(o, 4.72, .52, .05, P.bg, 0, 1.37, -1.15); o.fill = B(o, 4.6, .4, .03, P.lite, 0, 1.37, -1.115); o.fill.castShadow = false; });
    const ch = new THREE.Group(); ch.position.set(0, 0, 2.4); g.add(ch); B(ch, .9, .14, .9, P.f1, 0, .6, 0); B(ch, .9, 1, .14, P.f1, 0, 1.1, .45); [[-.38, -.38], [.38, -.38], [-.38, .38], [.38, .38]].forEach(([x, z]) => B(ch, .12, .55, .12, P.wall, x, .27, z));
    F('skill', -3.2, -4.6, o => { B(o, 2.2, 2.7, .6, P.f1, 0, 1.35, 0); for (let r = 0; r < 3; r++) { B(o, 2, .06, .5, P.wall, 0, .5 + r * .8, .1); for (let k = 0; k < 7; k++) { const m = B(o, .2, .5 + (k * 7 + r * 3) % 3 * .08, .34, [P.lite, P.f2, P.white][(k + r) % 3], -.8 + k * .27, .8 + r * .8, .2); if (r === 1 && k === 3) { I(o, m); o.book = m; } } } });
    F('memory', -0.6, -4.55, o => { B(o, 1.2, 2, .7, P.f1, 0, 1, 0); for (let r = 0; r < 3; r++) { const d = new THREE.Group(); o.add(d); B(d, 1, .5, .06, P.f2, 0, .38 + r * .62, .37); I(o, B(d, .3, .08, .06, P.lite, 0, .38 + r * .62, .42)); if (r === 2) { B(d, .9, .36, .5, P.wall, 0, 1.6, .1); o.sheet = B(d, .5, .3, .03, P.white, 0, 1.8, .15); o.drawer = d; } } B(o, .5, .1, .4, P.white, 0, 2.05, 0); });
    F('files', -5.55, -3.75, o => { B(o, 1.5, 1.5, .7, P.f1, 0, .75, 0); for (let r = 0; r < 2; r++) { const d = new THREE.Group(); o.add(d); B(d, 1.3, .58, .06, P.f2, 0, .4 + r * .7, .37); I(o, B(d, .4, .08, .06, P.lite, 0, .4 + r * .7, .42)); if (r === 1) { B(d, 1.2, .44, .5, P.wall, 0, 1.08, .1); o.sheet = B(d, .6, .34, .03, P.white, 0, 1.32, .15); o.drawer = d; } } for (let k = 0; k < 4; k++) B(o, .06, .4, .5, [P.lite, P.white][k % 2], -.45 + k * .3, 1.68, 0); }).rotation.y = Math.PI / 2;
    F('board', 4, -4.95, o => { B(o, 3, 1.9, .1, P.lite, 0, 1.95, 0); B(o, 2.8, 1.7, .04, P.bg, 0, 1.95, .06); I(o, B(o, .22, .22, .03, P.f2, 1.1, 2.5, .09)); for (let k = 0; k < 4; k++) { const m = B(o, [2.4, 2, 2.3, 1.2][k], .08, .03, P.f1, [-.05, -.25, -.1, -.65][k], 1.74 - k * .2, .09); if (k === 3) o.pen = m; } });
    F('shell', -5.2, -1.5, o => { B(o, 1.3, .16, 2.4, P.f1, 0, .95, 0); [[-.5, -1.1], [.5, -1.1], [-.5, 1.1], [.5, 1.1]].forEach(([x, z]) => B(o, .14, .88, .14, P.wall, x, .44, z)); B(o, .16, 1, 1.4, P.f2, -.35, 1.6, 0); B(o, .04, .8, 1.2, P.bg, -.26, 1.6, 0); o.lines = []; for (let k = 0; k < 3; k++) o.lines.push(I(o, B(o, .03, .07, [.8, .5, .65][k], P.bg, -.235, 1.85 - k * .2, [.1, .25, .18][k]))); B(o, .4, .06, .9, P.lite, .25, 1.06, 0); });
    F('mcp', -5.95, 2.6, o => { B(o, .1, .8, 1, P.lite, 0, 1.5, 0); [-.22, .22].forEach(z => B(o, .04, .3, .2, P.bg, .06, 1.5, z)); o.plug = I(o, B(o, .3, .22, .22, P.f2, .5, 1.5, .22)); I(o, B(o, .1, 1.2, .1, P.f2, .3, .9, .22)); });
    F('web', -5, .7, o => { B(o, .8, .9, .8, P.f1, 0, .45, 0); const ring = new THREE.Mesh(new THREE.TorusGeometry(.48, .07, 12, 36), M(P.lite)); ring.userData.base = P.lite; ring.position.set(0, 1.75, 0); ring.rotation.y = Math.PI / 2; o.add(ring); I(o, ring); o.ring = ring; B(o, .12, .5, .12, P.f2, 0, 1.1, 0); });
    F('phone', 5.25, -4.3, o => { B(o, .9, .8, .9, P.f1, 0, .4, 0); B(o, .6, .14, .44, P.f2, 0, .87, 0); o.hand = I(o, B(o, .76, .13, .2, P.lite, 0, 1.02, 0)); });
    F('other', -5.2, 4.1, o => { B(o, 1.3, .6, .7, P.f2, 0, .3, 0); const lid = new THREE.Group(); lid.position.set(0, .6, -.37); o.add(lid); o.lid = lid; B(lid, 1.34, .1, .74, P.f1, 0, .05, .37); B(lid, .6, .08, .1, P.lite, 0, .16, .37); I(o, B(o, .24, .16, .06, P.lite, 0, .42, .37)); });
    F('subbench', 4.6, -1.5, o => { B(o, 2.3, .18, 1.4, P.f1, 0, .8, 0); [[-1, -.55], [1, -.55], [-1, .55], [1, .55]].forEach(([x, z]) => B(o, .16, .72, .16, P.wall, x, .36, z)); }).visible = false;
    room.title = el('lbl title'); room.titlePos = new THREE.Vector3(-6, 3.9, -5).add(g.position);
    room.actor = new Actor(room, 1, ST.chair); room.actor.face(0, -1); room.actor.pose = 'sleep'; room.actor.where = 'chair'; room.actor.bot.g.userData.pick = 'agent';
    ses.cards.slice(-54).forEach(c => place(room, c, false)); // what the session already holds
    return room;
  }
  const setState = (room, s, d = '') => { room.state = s; room.detail = d; };
  const setActive = (room, kind, on) => { room.act[kind] = Math.max(0, (room.act[kind] || 0) + (on ? 1 : -1)); const a = room.act[kind] > 0; room.f[kind].ind.forEach(m => m.material = M(a ? P.pink : m.userData.base)); const pl = room.f[kind].plate; pl.face.material = a ? pl.mA : pl.mN; };
  const GAUGE = [new THREE.MeshBasicMaterial({ color: 0xF7F6F6 }), new THREE.MeshBasicMaterial({ color: 0xD53F8C })];
  const cardMats = {}, cardMat = (kind, st) => { const key = kind + st; if (!cardMats[key]) { const [bg, fg, side] = st === 'fresh' ? ['#D53F8C', '#FFFFFF', P.pink] : st === 'fail' ? ['#D12D50', '#FFFFFF', P.red] : ['#F7F6F6', '#120F1A', P.white]; const t = new THREE.CanvasTexture(iconCanvas(kind, bg, fg)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; const top = new THREE.MeshStandardMaterial({ map: t, roughness: .9 }), s = M(side); cardMats[key] = [s, s, top, s, s, s]; } return cardMats[key]; };

  /** Put a context card on the workbench. Thickness is its token cost. */
  function place(room, card, fresh = true) {
    if (!card || room.placed.has(card)) return; room.placed.add(card);
    if (fresh) room.cards.forEach(k => { if (k.card.ok) k.mesh.material = cardMat(k.card.type, 'old'); });
    const slot = room.cards.length % 27, hgt = Math.min(.45, .04 + card.tok / 1000 * .035), base = room.slotTop[slot] || 1.11;
    const m = B(room.g, .4, hgt, .52, P.white, -2 + (slot % 9) * .5, base + hgt / 2, -.7 + Math.floor(slot / 9) * .7);
    room.slotTop[slot] = base + hgt; m.material = cardMat(card.type, !card.ok ? 'fail' : fresh ? 'fresh' : 'old'); m.userData.pick = 'card'; m.userData.card = card;
    room.cards.push({ card, mesh: m });
  }
  function clearCards(room) { room.cards.forEach(k => { room.g.remove(k.mesh); k.mesh.geometry.dispose(); }); room.cards = []; room.slotTop = {}; room.sweep = null; }

  function spawnSub(room, sub) {
    if (room.subs.some(x => x.sub === sub)) return;
    const j = room.subs.length, S = new Actor(room, .68, [ST.door[0] + j * .5, ST.door[1]]); S.sub = sub; S.home = 'sub' + (j % 2); room.subs.push(S); room.f.subbench.visible = true;
    S.q({ go: S.home }, { pose: 'think', wait: .6 });
  }
  function subNext(room, S) {
    const sub = S.sub, it = sub.queue.shift();
    if (it && it.t === 'call') {
      const c = it.call, k = c.kind === 'sub' ? 'other' : c.kind;
      S.q({ go: k }, { pose: 'operate', op: k, min: .7, begin: () => { setActive(room, k, true); S.run = [c]; }, until: () => c.done || Date.now() - c.ts > STALE_MS, end: () => { setActive(room, k, false); S.run = null; if (!c.unknown) S.setCarry(c.ok ? P.white : P.red); } },
        { go: S.home }, { call: () => { if (S.bot.carry.visible) { const i = room.subCards.length; room.subCards.push(B(room.g, .26, .05, .34, c.ok ? P.lite : P.red, 3.7 + (i % 6) * .36, .92 + Math.floor(i / 12) * .05, -1.9 + Math.floor(i / 6) % 2 * .45)); S.setCarry(null); } } });
    } else if (sub.ended || (sub.call && sub.call.done)) {
      const card = sub.call && sub.call.card;
      S.q({ call: () => { if (card) S.setCarry(card.ok ? P.pink : P.red); } }, { go: 'benchR' }, { call: () => { S.setCarry(null); place(room, card); } }, { go: 'door' },
        { call: () => { S.remove(); room.subs = room.subs.filter(x => x !== S); if (!room.subs.length) { room.subCards.forEach(m => { room.g.remove(m); m.geometry.dispose(); }); room.subCards = []; room.f.subbench.visible = false; } } });
    } else S.q({ pose: 'think', min: .3, until: () => sub.queue.length > 0 || sub.ended || (sub.call && sub.call.done) });
  }

  /** Nothing queued: think if something is expected, wait on sub-agents, or go and sleep. */
  function rest(room) {
    const A = room.actor, s = room.ses, more = () => s.queue.length > 0;
    if (room.subs.length) A.q({ go: 'bench' }, { pose: 'wait', min: .3, begin: () => setState(room, 'Waiting', 'on ' + room.subs.length + (room.subs.length > 1 ? ' sub-agents' : ' sub-agent')), until: () => more() || !room.subs.length });
    else if (store.resting(s)) A.q({ go: 'chair' }, { call: () => A.face(0, -1) }, { pose: 'sleep', min: .5, begin: () => setState(room, 'Idle', s.ended ? 'session ended' : 'asleep in the chair'), until: () => more() || !store.resting(s) });
    else A.q({ go: 'bench' }, { pose: 'think', min: .4, begin: () => setState(room, 'Thinking'), until: () => more() || store.resting(s) || room.subs.length > 0 });
  }

  /** Apply an item without animating it (used when far behind). */
  function skip(room, it) {
    if (it.t === 'prompt') place(room, it.card);
    else if (it.t === 'call') { const c = it.call; if (c.kind === 'sub') spawnSub(room, c.sub || store.ensureSub(room.ses, c)); else if (c.done) place(room, c.card); else return false; }
    else if (it.t === 'sub') spawnSub(room, it.sub);
    else if (it.t === 'compact') { if (!it.job.done) return false; clearCards(room); place(room, it.job.card); }
    else if (it.t === 'load') place(room, it.card);
    return true;
  }

  function next(room) {
    const A = room.actor, s = room.ses;
    while (s.queue.length > 40 && skip(room, s.queue[0])) s.queue.shift(); // hopelessly behind: jump ahead
    const it = s.queue.shift(); room.rush = s.queue.length >= 3;
    if (!it) return rest(room);
    if (it.t === 'prompt') {
      const asleep = A.pose === 'sleep';
      A.q({ pose: asleep ? 'sleep' : 'idle', wait: 1.2, begin: () => { room.ringing = true; setActive(room, 'phone', true); setState(room, 'Listening', 'phone is ringing'); } }, { go: 'phone' },
        { pose: 'operate', op: 'phone', wait: 1.3, begin: () => { room.answer = true; }, end: () => { room.answer = false; room.ringing = false; setActive(room, 'phone', false); A.setCarry(P.pink); } },
        { go: 'bench' }, { call: () => { A.setCarry(null); place(room, it.card); } }, { pose: 'think', wait: .8, begin: () => setState(room, 'Thinking') }, { go: 'board' },
        { pose: 'operate', op: 'board', wait: 1.2, begin: () => { setState(room, 'Operating', 'updating the board'); setActive(room, 'board', true); }, end: () => setActive(room, 'board', false) }, { go: 'bench' });
    } else if (it.t === 'call' && it.call.kind === 'sub' || it.t === 'sub') {
      const sub = it.t === 'sub' ? it.sub : it.call.sub || store.ensureSub(s, it.call);
      A.q({ call: () => { setState(room, 'Delegating', sub.name); spawnSub(room, sub); } }, { pose: 'talk', wait: .8 }, { go: 'bench' });
    } else if (it.t === 'call') {
      const kind = it.call.kind, group = [it.call];
      while (group.length < 20 && s.queue[0] && s.queue[0].t === 'call' && s.queue[0].call.kind === kind) group.push(s.queue.shift().call);
      const n = group.length, burst = n >= 3, label = burst ? n + ' calls in one burst' : group.map(c => c.label).join(' · ');
      const stale = c => Date.now() - c.ts > STALE_MS, got = () => group.filter(c => c.done && !c.unknown), bad = () => group.some(c => c.done && c.ok === false);
      A.q({ call: () => setState(room, 'Operating', label) }, { go: kind },
        { pose: 'operate', op: kind, min: burst ? n * .25 + .3 : .7, begin: () => { setActive(room, kind, true); A.run = group; A.burst = burst ? { n: 0 } : null; },
          tick: (dt, c) => { if (A.burst) A.burst.n = Math.min(group.filter(x => x.done).length, Math.floor(c.el / .25)); },
          until: () => group.every(c => c.done || stale(c)),
          end: () => { setActive(room, kind, false); A.run = null; A.burst = null; if (got().length) A.setCarry(bad() ? P.red : kind === 'skill' ? P.lite : P.white, burst || kind === 'skill' ? 'book' : kind === 'memory' ? 'note' : 'sheet'); } },
        { call: () => { if (bad()) A.q0({ pose: 'error', wait: .9, begin: () => setState(room, 'Error', group.find(c => c.ok === false).label) }); } },
        { go: 'bench' },
        { call: () => { A.setCarry(null); const cards = got().map(c => c.card).filter(Boolean); if (burst && cards.length > 1) { cards.forEach(c => room.placed.add(c)); place(room, { type: kind, label: cards.length + ' results from one burst', tok: cards.reduce((a, c) => a + c.tok, 0), ok: !bad(), ts: cards[cards.length - 1].ts, burst: cards.length }); } else cards.forEach(c => place(room, c)); } });
    } else if (it.t === 'say') {
      A.q({ go: 'bench' }, { call: () => A.face(.4, 1) }, { pose: 'talk', wait: 3.2, begin: () => { setState(room, 'Speaking'); room.speech = it.text; }, end: () => { room.speech = ''; A.face(0, -1); } });
    } else if (it.t === 'compact') {
      const job = it.job;
      A.q({ go: 'bench' }, { pose: 'operate', op: 'bench', min: 1.9, begin: () => { setState(room, 'Operating', 'tidying the workbench (compaction)'); room.sweep = { t: 0, from: room.cards.map(k => k.mesh.position.clone()) }; }, until: () => job.done || Date.now() - job.start > 300000, end: () => { clearCards(room); place(room, job.card); } });
    } else if (it.t === 'load') {
      A.q({ call: () => setState(room, 'Operating', it.label) }, { go: 'memory' },
        { pose: 'operate', op: 'memory', wait: 1, begin: () => setActive(room, 'memory', true), end: () => { setActive(room, 'memory', false); A.setCarry(P.white, 'note'); } },
        { go: 'bench' }, { call: () => { A.setCarry(null); place(room, it.card); } });
    } // 'end' needs no action: rest() walks to the chair
  }
  Actor.prototype.q0 = function (...c) { this.todo.unshift(...c); };

  function narr(room) {
    const A = room.actor, c = A.cur, d = room.detail;
    if (c && c.go) { if (c.go === 'bench') return A.bot.carry.visible ? 'Carrying the result back to Context.' : 'Walking back to Context.'; if (c.go === 'chair') return 'Nothing to do. Heading for the chair.'; if (META[c.go]) return 'Walking to ' + META[c.go][0] + (d ? ': ' + d : '') + '.'; }
    switch (room.state) {
      case 'Idle': return room.ses.ended ? 'Session ended. Asleep in the chair.' : 'Asleep in the chair. Nothing to do.';
      case 'Listening': return 'The phone is ringing: a new user instruction.';
      case 'Thinking': return 'Thinking about the next step.';
      case 'Operating': { const open = A.run && A.run.find(x => !x.done); return (A.pose === 'operate' && META[A.op] ? META[A.op][0] + ': ' : '') + d + (open && Date.now() - open.ts > 4000 ? ' · still running' : ''); }
      case 'Delegating': return 'Handing a task to ' + d + '.';
      case 'Waiting': return 'Waiting ' + d + '.';
      case 'Speaking': return 'Answering: ' + room.speech;
      case 'Error': return 'That failed: ' + d;
    }
    return '';
  }

  // ---------- public room management ----------
  const api = { rooms, focus: -1, paused: false, emptyText: 'No sessions yet. Waiting for events.', narr };
  api.attach = (ses, i) => { if (rooms[i]) api.detach(i); store.attach(ses); rooms[i] = buildRoom(i, ses); layout(); return rooms[i]; };
  api.detach = i => { const r = rooms[i]; if (!r) return; store.detach(r.ses); [r.actor, ...r.subs].forEach(a => a.bub.remove()); r.title.remove(); r.g.traverse(o => o.geometry && o.geometry.dispose()); scene.remove(r.g); rooms[i] = null; if (api.focus === i) api.focus = -1; layout(); };
  api.setFocus = i => { api.focus = rooms[i] ? i : -1; aim(); };

  // vacant slot outline
  const vg = new THREE.Group(); scene.add(vg); [[0, -5, 12, .2], [0, 5, 12, .2], [-6, 0, .2, 10], [6, 0, .2, 10]].forEach(([x, z, w, d]) => B(vg, w, .1, d, P.wall, x, 0, z));
  const vacant = el('lbl'); vacant.textContent = 'vacant · next session'; const vacantPos = new THREE.Vector3();
  let rows = 2;
  function layout() {
    const free = rooms.findIndex(r => !r), last = rooms.reduce((a, r, i) => r ? i : a, -1);
    vg.visible = free >= 0; if (free >= 0) { vg.position.copy(slotPos(free)); vacantPos.copy(vg.position).setY(.5); }
    rows = Math.max(2, Math.ceil((Math.max(last, free) + 1) / 2)); aim();
  }

  // ---------- camera ----------
  const camT = new THREE.Vector3(), camGoal = new THREE.Vector3(), camDir = new THREE.Vector3(1, .82, 1).normalize(); let camS = 21, camSGoal = 21, need = 26, snap = true;
  function aim() {
    if (api.focus < 0 || !rooms[api.focus]) { camGoal.set(12.5, 0, (rows - 1) * 10.5); camSGoal = 10.5 * rows; need = 13 * rows; }
    else { camGoal.copy(rooms[api.focus].g.position).add(new THREE.Vector3(-.3, 1.2, -.3)); camSGoal = 7; need = 8.8; }
    if (snap) { camT.copy(camGoal); camS = camSGoal; snap = false; }
  }
  layout();

  let W = 1, H = 1;
  function size() { W = stage.clientWidth || 1; H = stage.clientHeight || 1; renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1)); renderer.setSize(Math.max(2, W), Math.max(2, H), false); }
  new ResizeObserver(size).observe(stage); size();

  // ---------- picking ----------
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  const pickAt = e => {
    const live = rooms.filter(Boolean); if (!live.length) return null;
    const r = cv.getBoundingClientRect(); ndc.set((e.clientX - r.left) / r.width * 2 - 1, -(e.clientY - r.top) / r.height * 2 + 1); ray.setFromCamera(ndc, camera);
    const hit = ray.intersectObjects(live.map(x => x.g), true)[0]; if (!hit) return null;
    let o = hit.object, kind = null; while (o) { if (!kind && o.userData.pick) kind = o.userData.pick; if (live.some(x => x.g === o)) break; o = o.parent; }
    const room = live.find(x => x.g === o); return room ? { room, card: hit.object.userData.card, kind: kind || 'room', x: e.clientX - r.left, y: e.clientY - r.top } : null;
  };
  cv.addEventListener('click', e => { const p = pickAt(e); if (!p) return; if (api.focus !== p.room.i) { api.setFocus(p.room.i); onSelect({ slot: p.room.i, kind: 'room' }, true); } else onSelect({ slot: p.room.i, kind: p.kind, card: p.card }, false); });
  const tip = el('lbl'); tip.style.display = 'none'; tip.style.color = '#F7F6F6';
  cv.addEventListener('pointermove', e => { const p = pickAt(e); if (p && p.room.i === api.focus && p.kind !== 'room') { tip.textContent = p.kind === 'card' ? p.card.label : META[p.kind][0]; tip.style.display = ''; tip.style.transform = `translate(${p.x + 14}px,${p.y - 30}px)`; } else tip.style.display = 'none'; });
  cv.addEventListener('pointerleave', () => { tip.style.display = 'none'; });

  // ---------- frame loop ----------
  const v3 = new THREE.Vector3(), v3b = new THREE.Vector3();
  const put = (d, pos, show) => { if (!show) { d.style.display = 'none'; return; } v3.copy(pos).project(camera); d.style.display = ''; d.style.transform = `translate(${((v3.x * .5 + .5) * W).toFixed(1)}px,${((-v3.y * .5 + .5) * H).toFixed(1)}px) translate(-50%,-100%)`; };
  let lastT = performance.now(), clockT = 0, capTxt = null; const cap = stage.querySelector('#cap');
  function frame() {
    requestAnimationFrame(frame);
    const nowT = performance.now(), dt = api.paused ? 0 : Math.min(.05, (nowT - lastT) / 1000); lastT = nowT; clockT += dt;
    rooms.forEach(room => {
      if (!room) return;
      const A = room.actor; if (!api.paused && !A.busy()) next(room);
      A.update(dt); room.subs.slice().forEach(S => { if (!api.paused && !S.busy()) subNext(room, S); S.update(dt); });
      const f = room.f, q = Math.min(1, dt * 8);
      for (const kd in f) f[kd].a = (f[kd].a || 0) + ((room.act[kd] > 0 ? 1 : 0) - (f[kd].a || 0)) * q;
      [f.memory, f.files].forEach(o => { o.drawer.position.z = o.a * .45; o.sheet.visible = o.a > .3; });
      f.skill.book.position.z = .2 + f.skill.a * .32; f.skill.book.rotation.x = f.skill.a * .35;
      f.mcp.plug.position.x = .5 - f.mcp.a * .3; f.web.ring.position.y = 1.75 + f.web.a * .3; f.other.lid.rotation.x = -f.other.a * 1.1;
      f.shell.lines.forEach((m, n) => { m.scale.z = f.shell.a > .1 ? .35 + .65 * Math.abs(Math.sin(clockT * 3 + n * 1.7)) : 1; });
      f.board.pen.scale.x = f.board.a > .1 ? .15 + .85 * (clockT * 1.1 % 1) : 1;
      const hand = f.phone.hand; hand.position.y += ((room.answer ? 1.5 : 1.02) - hand.position.y) * q; hand.rotation.z = room.ringing && !room.answer ? Math.sin(clockT * 40) * .25 : 0;
      const pct = Math.min(1, room.ses.ctx / room.ses.ctxLimit); f.bench.fill.scale.x = Math.max(.002, pct); f.bench.fill.position.x = -2.3 + 2.3 * pct; f.bench.fill.material = pct >= .8 ? GAUGE[1] : GAUGE[0];
      if (room.sweep) { room.sweep.t = Math.min(1, room.sweep.t + dt / 1.7); const e = room.sweep.t * room.sweep.t; room.cards.forEach((c, j) => { const p0 = room.sweep.from[j]; if (p0) { c.mesh.position.set(p0.x * (1 - e), p0.y, p0.z * (1 - e)); c.mesh.scale.setScalar(1 - .7 * e); } }); }
      if (room.act.web > 0) f.web.ring.rotation.y += dt * 5;
    });
    camT.lerp(camGoal, .08); camS += (camSGoal - camS) * .08;
    camera.aspect = W / H; camera.updateProjectionMatrix();
    camera.position.copy(camT).addScaledVector(camDir, Math.max(camS, need / (W / H)) / Math.tan(13 * Math.PI / 180)); camera.lookAt(camT);
    renderer.render(scene, camera);
    const all = api.focus < 0;
    rooms.forEach(room => {
      if (!room) return; const on = api.focus === room.i;
      const html = `<span class="badge">${esc(room.ses.badge)}</span>${esc(room.ses.name)}<span style="color:#B5B4B8;font-weight:400">${room.state}</span>`;
      if (html !== room.titleHTML) room.title.innerHTML = room.titleHTML = html;
      put(room.title, room.titlePos, true);
      [room.actor, ...room.subs].forEach(S => { const b = S.bubble(); if (b) { S.bub.textContent = b[0]; S.bub.className = 'bub ' + b[1]; } put(S.bub, v3b.set(S.x, 2.3 * S.s + .3, S.z).add(room.g.position), !!b && (on || all && !S.sub)); });
    });
    put(vacant, vacantPos, all && vg.visible);
    const fr = all ? null : rooms[api.focus], any = rooms.some(Boolean);
    const txt = (fr ? narr(fr) : any ? 'All rooms. Click a room to follow its agent.' : api.emptyText) + (fr && fr.rush ? '|r' : '');
    if (txt !== capTxt) { capTxt = txt; const rush = txt.endsWith('|r'); cap.innerHTML = '<span class="k">Now</span><span>' + esc(rush ? txt.slice(0, -2) : txt) + '</span>' + (rush ? '<span class="rush">catching up</span>' : ''); }
  }
  frame();
  return api;
}
