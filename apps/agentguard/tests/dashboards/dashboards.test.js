// Static checks on the dashboards the manifest lists (timeplus-io/apps#74). No Timeplus needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const manifest = readFileSync(new URL('manifest.yaml', root), 'utf8');
const files = [...manifest.matchAll(/^\s+- file: (dashboards\/\S+\.json)$/gm)].map(m => m[1]);
// `[[ .DB ]]` is the only install-time template in these files; it sits inside JSON strings.
const load = file => JSON.parse(readFileSync(new URL(file, root), 'utf8'));

test('the manifest lists eight dashboards', () => {
  assert.equal(files.length, 8);
});

for (const file of files) {
  const panels = load(file);
  const charts = panels.filter(p => p.viz_type === 'chart');
  const controls = panels.filter(p => p.viz_type === 'control');

  test(`${file}: at most six charts, unique ids`, () => {
    assert.ok(charts.length >= 1 && charts.length <= 6, `${charts.length} charts`);
    assert.equal(new Set(panels.map(p => p.id)).size, panels.length);
  });

  test(`${file}: the controls fill their row`, () => {
    // A panel placed beside a narrower control row is lifted into it by the grid. A control may sit
    // lower than the first row (right above the panel it drives), but its row still holds controls only.
    const rows = new Map();
    for (const c of controls) rows.set(c.position.y, (rows.get(c.position.y) ?? 0) + c.position.w);
    assert.ok(rows.has(0), 'the first row is a control row');
    for (const [y, width] of rows) assert.equal(width, 12, `controls of row ${y} fill it`);
    assert.ok(controls.every(c => c.position.h === 1 && c.viz_config.defaultValue !== ''), 'every control has a default value');
    assert.ok(charts.every(p => !rows.has(p.position.y)), 'no chart starts in a control row');
    for (const c of controls.filter(c => c.viz_content)) {
      // a selector that takes its options from a query: the chosen text goes into the panel queries between quotes
      assert.equal(c.viz_config.chartType, 'selector');
      assert.ok(c.viz_content.includes('[[ .DB ]].'), `${c.id} reads [[ .DB ]]`);
      assert.match(c.viz_content, /replace_all\(.*char\(39\), ''\)/, `${c.id}: options hold no quote character`);
    }
  });

  test(`${file}: every query filter has a control, and queries name the database by template`, () => {
    const targets = new Set(controls.map(c => c.viz_config.target));
    for (const p of charts) {
      for (const [, name] of p.viz_content.matchAll(/\{\{(filter_\w+)\}\}/g)) assert.ok(targets.has(name), `${p.id} uses ${name}`);
      assert.ok(p.viz_content.includes('[[ .DB ]].'), `${p.id} reads [[ .DB ]]`);
      assert.ok(!/\bag\./.test(p.viz_content), `${p.id} has a hard-coded database`);
    }
  });

  test(`${file}: chart columns exist in the query, tables show every row`, () => {
    for (const p of charts) {
      const { chartType, config = {} } = p.viz_config;
      const names = chartType === 'singleValue' ? [config.value] : [config.xAxis, config.yAxis, config.color].filter(Boolean);
      for (const n of names) assert.match(p.viz_content, new RegExp(`\\b${n}\\b`), `${p.id}: column ${n}`);
      if ((chartType === 'column' || chartType === 'bar') && config.color) {
        // A column or bar chart keeps one row per x value unless it updates by a key that is unique per
        // row. Without that key only one series of each bar is drawn, and the chart looks unstacked.
        assert.equal(config.updateMode, 'key', `${p.id}: a chart with series updates by key`);
        assert.match(p.viz_content, new RegExp(`concat\\(to_string\\(${config.xAxis}\\), ' ', to_string\\(${config.color}\\)\\) AS ${config.updateKey}\\b`), `${p.id}: the key is x and series together`);
      }
      if (chartType === 'grammar') {
        // a waterfall: every field the spec encodes or shows in the tooltip is a column of the query
        const mark = JSON.parse(config.advancedSpec).marks[0];
        const fields = [...Object.values(mark.encode), ...(mark.tooltip?.items ?? []).map(i => i.field)];
        for (const f of fields) assert.match(p.viz_content, new RegExp(`\\b${f}\\b`), `${p.id}: column ${f}`);
        assert.ok(mark.encode.y && mark.encode.y1, `${p.id}: a bar has a start and an end`);
      }
      if (chartType !== 'table') continue;
      // A table shows the last `rowCount` rows of the result, so the query must not return more.
      const limit = Math.max(...[...p.viz_content.matchAll(/LIMIT (\d+)/g)].map(m => Number(m[1])), 0);
      assert.ok(limit <= config.rowCount, `${p.id}: LIMIT ${limit} over rowCount ${config.rowCount}`);
    }
  });
}
