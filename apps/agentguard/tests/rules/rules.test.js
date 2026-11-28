// Static checks of the detection rule views (timeplus-io/apps#86). No server needed: `make test`.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const DDL = new URL('../../ddl/', import.meta.url);
const files = readdirSync(DDL).filter(f => /^\d+_mv_rule_/.test(f));
const manifest = readFileSync(new URL('../../manifest.yaml', import.meta.url), 'utf8');
const { cases } = JSON.parse(readFileSync(new URL('./cases.json', import.meta.url), 'utf8'));

test('a regex escape in a rule is written with two backslashes', () => {
  // In a SQL string '\b' is a backspace character, so a pattern written with one backslash never
  // matches and the rule is silently dead. Every backslash in a rule file must come in a pair.
  for (const f of files) {
    const sql = readFileSync(new URL(f, DDL), 'utf8').split('\n').filter(l => !l.startsWith('--')).join('\n');
    const single = sql.replaceAll('\\\\', '').replaceAll("\\'", '').match(/\\./g);
    assert.equal(single, null, `${f}: single backslash before ${single}`);
  }
});

test('every rule view is in the manifest, and every rule has a case that expects it', () => {
  const ids = new Set();
  for (const f of files) {
    assert.ok(manifest.includes(`file: ddl/${f}\n`), `${f} is not listed in manifest.yaml`);
    const sql = readFileSync(new URL(f, DDL), 'utf8');
    const list = n => [...sql.match(new RegExp(`\\[([^\\]]*)\\] AS ${n}`))[1].matchAll(/'([^']*)'/g)].map(m => m[1]);
    const [rule, name, severity] = ['rule_id', 'rule_name', 'severity'].map(list);
    assert.ok(rule.length > 0 && rule.length === name.length && rule.length === severity.length, `${f}: rule_id, rule_name and severity lists differ in length`);
    assert.equal((sql.match(/^    -- [a-z]+\.[a-z-]+$/gm) || []).length, rule.length * 2, `${f}: one condition and one evidence expression per rule`);
    for (const s of severity) assert.ok(['info', 'low', 'medium', 'high', 'critical'].includes(s), `${f}: severity ${s}`);
    rule.forEach(r => ids.add(r));
  }
  const expected = new Set(cases.flatMap(c => c.expect));
  assert.deepEqual([...ids].filter(r => !expected.has(r)), [], 'rules without a case');
  assert.deepEqual([...expected].filter(r => !ids.has(r)), [], 'cases that expect a rule that does not exist');
  assert.ok(cases.filter(c => c.expect.length === 0).length >= 15, 'benign cases');
});

test('no token-shaped string is stored in the cases file', () => {
  const text = readFileSync(new URL('./cases.json', import.meta.url), 'utf8');
  assert.equal(/ghp_[A-Za-z0-9]{36}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}\b/.test(text), false);
});
