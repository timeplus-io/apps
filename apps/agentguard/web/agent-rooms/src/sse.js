// Incremental parser for the Timeplus REST API query stream (Server-Sent Events).
//
// The query endpoint emits:
//   event: query    data: {..., "result": {"header": [{name, type}, ...]}}   (start, and again on finish)
//   (no event name) data: [[v1, v2, ...], ...]                               (row batches)
//   event: metrics  data: {...}                                              (ignored)

export class SSEParser {
  constructor() { this.buf = ''; }
  /** Feed a text chunk; returns the complete events it closed: [{event, data}]. */
  feed(chunk) {
    this.buf += chunk.replace(/\r\n?/g, '\n');
    const out = [];
    let i;
    while ((i = this.buf.indexOf('\n\n')) >= 0) {
      const block = this.buf.slice(0, i); this.buf = this.buf.slice(i + 2);
      let event = 'message'; const data = [];
      for (const line of block.split('\n')) {
        if (!line || line[0] === ':') continue;
        const c = line.indexOf(':'), f = c < 0 ? line : line.slice(0, c);
        let v = c < 0 ? '' : line.slice(c + 1); if (v[0] === ' ') v = v.slice(1);
        if (f === 'event') event = v; else if (f === 'data') data.push(v);
      }
      if (data.length) out.push({ event, data: data.join('\n') });
    }
    return out;
  }
}

/**
 * Turns parsed SSE events into row objects keyed by column name.
 * Call push(event) for each event; it returns an array of rows (possibly empty).
 */
export class RowDecoder {
  constructor() { this.header = null; this.status = 'running'; this.message = ''; }
  push(ev) {
    let d; try { d = JSON.parse(ev.data); } catch { return []; }
    if (ev.event === 'query') {
      const h = d && d.result && d.result.header; if (h && !this.header) this.header = h.map(c => c.name);
      if (d && d.status) { this.status = d.status; this.message = d.message || ''; }
      return [];
    }
    if (ev.event !== 'message' || !Array.isArray(d) || !this.header) return [];
    const names = this.header;
    return d.map(r => { const o = {}; for (let i = 0; i < names.length; i++) o[names[i]] = r[i]; return o; });
  }
}
