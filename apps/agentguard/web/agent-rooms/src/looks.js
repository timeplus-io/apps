// The four looks of the page: a visual style (Studio or Sketchbook) in the console's light or
// dark theme. The style is the viewer's choice; the theme always comes from the console.
// Everything here is data and pure functions; scene.js applies it to three.js, index.html
// holds the matching CSS variables under :root[data-style][data-theme].

export const STYLES = [['studio', 'Studio'], ['sketch', 'Sketchbook']];
/** The saved style choice, or Studio. */
export const readStyle = saved => (saved === 'sketch' ? 'sketch' : 'studio');
export const lookKey = (style, tone) => readStyle(style) + '-' + (tone === 'light' ? 'light' : 'dark');

// The scene is modelled in the Studio dark colours; the other looks map each one to the colour to draw.
export const P = { bg: 0x120F1A, floor: 0x231F2B, wall: 0x3A3741, f1: 0x514E58, f2: 0x7D7B82, lite: 0xB5B4B8, white: 0xF7F6F6, pink: 0xD53F8C, red: 0xD12D50 };
export const GLOW = 0xFFFFFE, SLAB = 0x8B6F52;
const PAL = {
  'studio-dark': {},
  'studio-light': { 0x120F1A: 0x2A2633, 0x231F2B: 0xE9E7EC, 0x3A3741: 0xD9D6DE, 0x514E58: 0xB9B6C0, 0x7D7B82: 0x8E8B95, 0xB5B4B8: 0xCFCDD3 },
  // Sketchbook: paper and watercolour tones.
  'sketch-light': { 0x120F1A: 0x4A4F57, 0x231F2B: 0xE6D5B5, 0x3A3741: 0xE9E1D0, 0x514E58: 0xC9A97E, 0x7D7B82: 0x8FA8B8, 0xB5B4B8: 0xA9BFA0, 0xF7F6F6: 0xFBF8F1, 0xD53F8C: 0xC0503A, 0xD12D50: 0xB23A3A },
  'sketch-dark': { 0x120F1A: 0x2A2E36, 0x231F2B: 0x6B5A45, 0x3A3741: 0x3A3F4A, 0x514E58: 0x8C7457, 0x7D7B82: 0x5F7A8C, 0xB5B4B8: 0x7F9677, 0xF7F6F6: 0xE9E2D2, 0xD53F8C: 0xE07A5F, 0xD12D50: 0xD0524E, 0x8B6F52: 0x4A3B2E }
};

/** How to draw the model colour `c` in a look: the properties of its MeshStandardMaterial. */
export function matSpec(c, key) {
  const pal = PAL[key] || {}, pink = c === P.pink, glow = c === GLOW;
  if (key.startsWith('sketch')) return { color: pal[c] ?? c, roughness: 1, metalness: 0, emissive: pink ? pal[c] : glow ? 0xffffff : 0, emissiveIntensity: pink ? (key === 'sketch-dark' ? .3 : .15) : glow ? .7 : 0 };
  const shiny = c === P.f2 || c === P.lite;
  return {
    color: pal[c] ?? (c === P.floor ? 0x2E2A36 : c),
    roughness: pink ? .5 : c === P.bg ? .22 : shiny ? .42 : c === P.floor ? .7 : glow ? 1 : .85,
    metalness: c === P.bg ? .5 : shiny ? .4 : 0,
    emissive: pink ? c : glow ? 0xffffff : 0,
    emissiveIntensity: pink ? .55 : glow ? 1 : 0
  };
}

// Per look. gauge: [normal, nearly full] bar on the bench. hemi: [intensity, ground colour].
// sun: [intensity, colour]. ink: [colour, opacity] of the Sketchbook outlines. icon: line colour of
// the side-panel icons. signs: [background, line] of an icon sign (n normal, a active, o the phone
// while the agent is the one talking: told apart from `a` by lightness, not hue) and of the top of
// a context card (fresh, fail, old). solid: the canvas paints its own background.
export const LOOK = {
  'studio-dark': { solid: true, gauge: [0xF7F6F6, 0xD53F8C], hemi: [1.5, 0x3A3741], sun: [2.6, 0xFFF4EA], ink: [0x3B3631, .55], icon: '#F7F6F6',
    signs: { o: ['#F7F6F6', '#D53F8C'], n: ['#120F1A', '#F7F6F6'], a: ['#D53F8C', '#FFFFFF'], fresh: ['#D53F8C', '#FFFFFF'], fail: ['#D12D50', '#FFFFFF'], old: ['#F7F6F6', '#120F1A'] } },
  'studio-light': { solid: false, gauge: [0x5E5B66, 0xD53F8C], hemi: [2.0, 0xD9D6DE], sun: [2.2, 0xFFF4EA], ink: [0x3B3631, .55], icon: '#120F1A',
    signs: { o: ['#120F1A', '#FFFFFF'], n: ['#FFFFFF', '#120F1A'], a: ['#D53F8C', '#FFFFFF'], fresh: ['#D53F8C', '#FFFFFF'], fail: ['#D12D50', '#FFFFFF'], old: ['#FFFFFF', '#120F1A'] } },
  'sketch-light': { solid: false, gauge: [0x6E655A, 0xC0503A], hemi: [2.3, 0xD9CCB4], sun: [1.6, 0xFFF4EA], ink: [0x3B3631, .55], icon: '#3B3631',
    signs: { o: ['#3B3631', '#FBF8F1'], n: ['#FBF8F1', '#3B3631'], a: ['#B5452F', '#FFFFFF'], fresh: ['#B5452F', '#FFFFFF'], fail: ['#B23A3A', '#FFFFFF'], old: ['#FBF8F1', '#3B3631'] } },
  'sketch-dark': { solid: false, gauge: [0xA9A194, 0xE07A5F], hemi: [1.3, 0x2A2E36], sun: [1.5, 0xD6DEFF], ink: [0xEDE6D6, .3], icon: '#EDE6D6',
    signs: { o: ['#EDE6D6', '#1C1F26'], n: ['#2A2E36', '#EDE6D6'], a: ['#E07A5F', '#1C1F26'], fresh: ['#E07A5F', '#1C1F26'], fail: ['#D0524E', '#FFFFFF'], old: ['#E9E2D2', '#1C1F26'] } }
};

// Sketchbook callouts: what each object is, in a few handwritten words.
export const TAG = { bench: 'what it knows right now', phone: 'the conversation with the user', board: 'the standing orders', skill: 'how-tos on the shelf', memory: 'what it keeps', files: 'the files on disk', shell: 'where commands run', web: 'out to the web', mcp: 'plugged-in tools', other: 'everything else', subbench: 'helpers work here' };

/** m:ss, or h:mm:ss from an hour on. */
export function clock(sec) {
  const s = Math.max(0, Math.floor(sec)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), p = n => String(n).padStart(2, '0');
  return h ? h + ':' + p(m) + ':' + p(s % 60) : m + ':' + p(s % 60);
}

/**
 * Where a callout goes: beside the object's sign at (x, y), on the side with more room, kept
 * inside a stage of W by H. Returns the box corner [lx, ty] and the leader line from the box
 * (sx, y0) through an elbow (ex, y0) to the sign.
 */
export function calloutBox(x, y, w, h, W, H) {
  const left = x < W / 2;
  const lx = Math.max(16, Math.min(W - 16 - w, left ? x - 64 - w : x + 64)), ty = Math.max(12, Math.min(H - h - 12, y - 60 - h / 2));
  const sx = left ? lx + w + 6 : lx - 6;
  return { left, lx, ty, sx, ex: left ? sx + 22 : sx - 22, y0: ty + 16 };
}
