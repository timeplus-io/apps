// Lucide icon paths (ISC license) drawn to canvas, plus the label and meaning of every room object.

export const META = {
  bench: ['Context', 'The context window. Every card is something the agent knows in this session. Thicker cards cost more tokens; the bar on the back edge is how full the window is.'],
  skill: ['Skill', 'Skills. A book is opened when a skill is loaded.'],
  memory: ['Memory', 'Long-term memory. Reads, searches and saves.'],
  files: ['Local file', 'Local files. Reads, searches and edits.'],
  shell: ['Terminal', 'The terminal. Shell commands and their results.'],
  web: ['Search', 'Web searches and page fetches.'],
  mcp: ['MCP', 'MCP servers and external tools.'],
  other: ['Other tools', 'Any other tool call.'],
  phone: ['User instruction', 'Incoming user messages.'],
  board: ['System instruction', 'System prompt and the task in progress.'],
  subbench: ['Sub-agent context', 'Sub-agents work here with their own context. Only results cross to the main workbench.'],
  agent: ['Agent', '']
};
export const LEGEND = ['bench', 'phone', 'board', 'skill', 'memory', 'files', 'shell', 'web', 'mcp', 'other', 'subbench'];

const ICONS = {
  bench: ['M12 2 2 7l10 5 10-5-10-5Z', 'm2 17 10 5 10-5', 'm2 12 10 5 10-5'],
  skill: ['M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z', 'M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z'],
  memory: [['e', 12, 5, 9, 3], 'M3 5v14a9 3 0 0 0 18 0V5', 'M3 12a9 3 0 0 0 18 0'],
  files: ['M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z'],
  board: [['r', 8, 2, 8, 4, 1], 'M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2', 'M12 11h4', 'M12 16h4', 'M8 11h.01', 'M8 16h.01'],
  shell: ['M4 17l6-6-6-6', 'M12 19h8'],
  mcp: ['M12 22v-5', 'M9 8V2', 'M15 8V2', 'M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z'],
  web: [['e', 11, 11, 8, 8], 'M21 21l-4.35-4.35'],
  phone: ['M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'],
  other: ['M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z'],
  subbench: ['M12 8V4H8', ['r', 4, 8, 16, 12, 2], 'M2 14h2', 'M20 14h2', 'M15 13v2', 'M9 13v2'],
  agent: ['M12 8V4H8', ['r', 4, 8, 16, 12, 2], 'M2 14h2', 'M20 14h2', 'M15 13v2', 'M9 13v2']
};

export function iconCanvas(kind, bg, fg) {
  const c = document.createElement('canvas'); c.width = c.height = 192; const x = c.getContext('2d');
  if (bg) { x.fillStyle = bg; x.fillRect(0, 0, 192, 192); }
  x.translate(30, 30); x.scale(5.5, 5.5); x.strokeStyle = fg; x.lineWidth = 2; x.lineCap = 'round'; x.lineJoin = 'round';
  (ICONS[kind] || ICONS.other).forEach(d => {
    if (typeof d === 'string') x.stroke(new Path2D(d));
    else { x.beginPath(); if (d[0] === 'r') x.roundRect(d[1], d[2], d[3], d[4], d[5]); else x.ellipse(d[1], d[2], d[3], d[4], 0, 0, Math.PI * 2); x.stroke(); }
  });
  return c;
}

let urls = {}, ink = '#F7F6F6';
/** Line colour of the side-panel icons; follows the page theme. */
export const setIconInk = c => { ink = c; urls = {}; };
/** Data URL of an icon in line art, for the side panel. */
export const iconURL = kind => urls[kind] || (urls[kind] = iconCanvas(kind, null, ink).toDataURL());
