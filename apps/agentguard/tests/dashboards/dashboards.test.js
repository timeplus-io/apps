// Static checks on the dashboards the manifest lists (timeplus-io/apps#74). No Timeplus needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const manifest = readFileSync(new URL('manifest.yaml', root), 'utf8');
const files = [...manifest.matchAll(/^\s+- file: (dashboards\/\S+\.json)$/gm)].map(m => m[1]);
// `[[ .DB ]]` is the only install-time template in these files; it sits inside JSON strings.
const load = file => JSON.parse(readFileSync(new URL(file, root), 'utf8'));

test('the manifest lists six dashboards', () => {
  assert.equal(files.length, 6);
});

for (const file of files) {
  const panels = load(file);
  const charts = panels.filter(p => p.viz_type === 'chart');
  const controls = panels.filter(p => p.viz_type === 'control');

  test(`${file}: at most six charts, unique ids`, () => {
    assert.ok(charts.length >= 1 && charts.length <= 6, `${charts.length} charts`);
    assert.equal(new Set(panels.map(p => p.id)).size, panels.length);
  });

  test(`${file}: the controls fill the first row`, () => {
    // A panel placed beside a narrower control row is lifted into it by the grid.
    assert.equal(controls.reduce((w, c) => w + c.position.w, 0), 12);
    assert.ok(controls.every(c => c.position.y === 0 && c.viz_config.defaultValue !== ''), 'every control has a default value');
    assert.ok(charts.every(p => p.position.y >= 1));
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
      if (chartType !== 'table') continue;
      // A table shows the last `rowCount` rows of the result, so the query must not return more.
      const limit = Math.max(...[...p.viz_content.matchAll(/LIMIT (\d+)/g)].map(m => Number(m[1])), 0);
      assert.ok(limit <= config.rowCount, `${p.id}: LIMIT ${limit} over rowCount ${config.rowCount}`);
    }
  });
}
