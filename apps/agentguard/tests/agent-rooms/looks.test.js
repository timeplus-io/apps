import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { P, GLOW, SLAB, LOOK, TAG, STYLES, readStyle, lookKey, matSpec, clock, calloutBox } from '../../web/agent-rooms/src/looks.js';
import { LEGEND } from '../../web/agent-rooms/src/icons.js';

const KEYS = ['studio-dark', 'studio-light', 'sketch-light', 'sketch-dark'];

test('the style is the saved choice or Studio; the tone is the console theme', () => {
  assert.equal(readStyle('sketch'), 'sketch');
  for (const v of [null, undefined, '', 'studio', 'neon']) assert.equal(readStyle(v), 'studio');
  assert.equal(lookKey('sketch', 'light'), 'sketch-light');
  assert.equal(lookKey('studio', 'dark'), 'studio-dark');
  assert.equal(lookKey('neon', undefined), 'studio-dark');
  assert.deepEqual(STYLES.map(s => s[0]), ['studio', 'sketch']);
});

test('every look is complete', () => {
  assert.deepEqual(Object.keys(LOOK).sort(), [...KEYS].sort());
  for (const key of KEYS) {
    const L = LOOK[key];
    assert.deepEqual(Object.keys(L.signs).sort(), ['a', 'fail', 'fresh', 'n', 'o', 'old'], key);
    assert.notDeepEqual(L.signs.o, L.signs.a, key); assert.notDeepEqual(L.signs.o, L.signs.n, key); // the outgoing phone sign is its own face
    for (const pair of Object.values(L.signs)) for (const c of pair) assert.match(c, /^#[0-9A-F]{6}$/i, key);
    assert.match(L.icon, /^#[0-9A-F]{6}$/i);
    for (const k of ['gauge', 'hemi', 'sun', 'ink']) assert.equal(L[k].length, 2, key + ' ' + k);
  }
  assert.deepEqual(KEYS.filter(k => LOOK[k].solid), ['studio-dark']); // only Studio dark paints its own background
});

test('Studio dark draws the model colours as they are, with the floor one step lighter', () => {
  for (const c of [P.bg, P.wall, P.f1, P.f2, P.lite, P.white, P.pink, P.red, SLAB]) assert.equal(matSpec(c, 'studio-dark').color, c);
  assert.equal(matSpec(P.floor, 'studio-dark').color, 0x2E2A36);
  assert.deepEqual(matSpec(P.pink, 'studio-dark'), { color: P.pink, roughness: .5, metalness: 0, emissive: P.pink, emissiveIntensity: .55 });
  assert.equal(matSpec(P.bg, 'studio-dark').metalness, .5);
});
test('Studio light recolours the room but keeps the accent and failure colours', () => {
  assert.equal(matSpec(P.floor, 'studio-light').color, 0xE9E7EC);
  assert.equal(matSpec(P.pink, 'studio-light').color, P.pink);
  assert.equal(matSpec(P.red, 'studio-light').color, P.red);
});
test('Sketchbook is matt paper: no metal, a faint glow on the accent only', () => {
  for (const key of ['sketch-light', 'sketch-dark']) {
    for (const c of Object.values(P)) { const m = matSpec(c, key); assert.equal(m.roughness, 1); assert.equal(m.metalness, 0); assert.notEqual(m.color, undefined); }
    assert.equal(matSpec(P.wall, key).emissiveIntensity, 0);
    assert.equal(matSpec(GLOW, key).emissive, 0xffffff);
  }
  assert.deepEqual(matSpec(P.pink, 'sketch-light'), { color: 0xC0503A, roughness: 1, metalness: 0, emissive: 0xC0503A, emissiveIntensity: .15 });
  assert.equal(matSpec(P.pink, 'sketch-dark').emissiveIntensity, .3);
  assert.equal(matSpec(SLAB, 'sketch-dark').color, 0x4A3B2E);
  assert.equal(matSpec(SLAB, 'sketch-light').color, SLAB);
});

test('every object in the legend has a callout line', () => {
  for (const kind of LEGEND) assert.ok(TAG[kind], kind);
});

test('clock formats elapsed seconds', () => {
  assert.equal(clock(0), '0:00'); assert.equal(clock(75.9), '1:15'); assert.equal(clock(3599), '59:59');
  assert.equal(clock(3600), '1:00:00'); assert.equal(clock(90061), '25:01:01'); assert.equal(clock(-5), '0:00');
});

test('a callout sits on the roomier side of its object and stays on the stage', () => {
  const l = calloutBox(300, 400, 120, 50, 1000, 700); // object in the left half: box to its left
  assert.equal(l.left, true); assert.equal(l.lx, 300 - 64 - 120); assert.equal(l.sx, l.lx + 120 + 6); assert.equal(l.ex, l.sx + 22);
  assert.equal(l.ty, 400 - 60 - 25); assert.equal(l.y0, l.ty + 16);
  const r = calloutBox(700, 400, 120, 50, 1000, 700);
  assert.equal(r.left, false); assert.equal(r.lx, 764); assert.equal(r.sx, 758); assert.equal(r.ex, 736);
  const edge = calloutBox(40, 10, 120, 50, 1000, 700); // would leave the stage: clamped
  assert.equal(edge.lx, 16); assert.equal(edge.ty, 12);
  const far = calloutBox(990, 695, 120, 50, 1000, 700);
  assert.equal(far.lx, 1000 - 16 - 120); assert.equal(far.sx, far.lx - 6);
});

test('the page defines the palette for all four looks and ships every font it names', () => {
  const html = readFileSync(new URL('../../web/agent-rooms/index.html', import.meta.url), 'utf8');
  for (const sel of [':root{', ':root[data-theme=light]{', ':root[data-style=sketch]{', ':root[data-style=sketch][data-theme=dark]{']) assert.ok(html.includes(sel), sel);
  const fonts = [...html.matchAll(/url\("(vendor\/fonts\/[^"]+)"\)/g)].map(m => m[1]);
  assert.equal(fonts.length, 6); // Inter, Fraunces and Patrick Hand, latin and latin-ext each
  for (const fam of ['Inter', 'Fraunces', 'Patrick Hand']) assert.ok(html.includes("font-family:'" + fam + "'"), fam);
  for (const f of fonts) assert.ok(readFileSync(new URL('../../web/agent-rooms/' + f, import.meta.url)).length > 1000, f);
  assert.ok(!/id="tone"|prefers-color-scheme/.test(html), 'no light/dark control: the theme is the console\'s');
});
