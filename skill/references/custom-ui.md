# Custom App UI Reference

An app can ship its own web pages ("custom UIs"): static bundles of HTML, JavaScript, CSS and assets. Timeplus stores them at install, serves them on the console's own origin, and lists them on the app's page in the console under **Custom UI**. A page runs its queries as the signed-in user, so it never asks for a URL, a username or a password.

Use one when a dashboard cannot show what the app needs: a 3D scene, a custom layout, an interaction the built-in panel types do not have.

Needs a Timeplus Enterprise release with custom app UI support. An older server ignores the `uis:` key: the app installs, just without its pages.

## Declaring a UI

```
my-app/
├── manifest.yaml
├── ddl/
├── dashboards/
├── web/
│   └── live/              # one bundle: everything under it is shipped and served
│       ├── index.html     # entry file
│       ├── src/app.js
│       └── vendor/…       # third-party code, copied in
└── tests/                 # tests, package.json, tooling: outside the bundle
```

```yaml
# manifest.yaml: top-level list, next to dashboards:
uis:
  - name: live               # required; ^[a-z][a-z0-9-]{0,31}$; unique in the app; part of the URL
    title: Live Readings     # optional; shown in the console; defaults to name
    dir: web/live            # required; directory inside the package
    entry: index.html        # optional; relative to dir; default index.html
    icon: "data:image/svg+xml;base64,..."   # optional; same rules as the app icon
```

`uis:` is not a `resources[].type`. `package_format_version` stays 1.

Rules checked at install (and by `scripts/check_tpapp.py` at build):

| Rule | Limit |
|---|---|
| UIs per app | 8 |
| One file | 8 MiB |
| One UI, all files | 32 MiB and 2,000 files |
| Whole package, uncompressed | 128 MiB |
| File paths inside `dir` | only `A-Z a-z 0-9 . _ - /`; no spaces, no non-ASCII |
| File kinds | regular files only; a symlink fails the install |
| `dir`, `entry` | relative, `/`-separated, no `..` |
| App `id` (when `uis:` is present) | `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`, because it becomes a URL segment |

**Everything under `dir` is shipped and served**, including a README, tests or a `.gitignore` left there. Keep those outside the bundle directory.

**Files are stored and served byte for byte.** No `{{ .DB }}` or `[[ .DB ]]` rendering happens in a bundle; the database name reaches the page through the URL (below).

## Packaging

The bundle directories must be in the zip. Take them from the manifest so the two cannot drift, then check the result:

```makefile
CHECK := python3 ../../scripts/check_tpapp.py

build:
	zip -r -X -FS $(OUT).tmp manifest.yaml ddl/ dashboards/ $$($(CHECK) --ui-dirs manifest.yaml) -x '*.DS_Store'
	$(CHECK) $(OUT).tmp
	mv $(OUT).tmp $(OUT)
```

- `check_tpapp.py --ui-dirs manifest.yaml` prints each `uis[].dir`.
- `check_tpapp.py app.tpapp` applies the table above to the built package and fails with the server's wording, for example `ui "live": entry file "index.html" not found in web/live`. It also warns about things the server accepts but the browser will block: an inline `<script>`, an inline `on…=` handler, a `src`/`href` pointing at another host.
- `-FS` makes zip drop entries whose files were deleted; plain `zip -r` onto an existing archive keeps them.
- `-x '*.DS_Store'` keeps macOS folder metadata out of the bundle (it would be stored and served like any other file).

The release workflow builds and checks every app the same way.

## What the page receives

The console opens the entry file in a frame and appends four query parameters:

```
/{workspace}/apps/{app_id}/ui/{name}/?workspace=default&app_id=io.example.my-app&db=my_app&theme=dark
```

| Parameter | Value |
|---|---|
| `workspace` | workspace id; first path segment of every API call |
| `app_id` | the installed app's id |
| `db` | the app's database (`db_name`, as installed) |
| `theme` | `light` or `dark`, the console's current theme |

```js
const p = new URLSearchParams(location.search);
const ctx = {
  workspace: p.get('workspace') || location.pathname.split('/')[1],
  db: p.get('db') || 'my_app',
  theme: p.get('theme') === 'light' ? 'light' : 'dark',
};
document.documentElement.dataset.theme = ctx.theme;
```

- Read them once at load. A theme switch reloads the console, and with it the frame.
- Fall back to sensible defaults: the URL can be opened directly in a tab, with no parameters.
- `db` ends up in SQL text. Accept it only if it matches `^[A-Za-z_][A-Za-z0-9_]*$`.
- Relative URLs (`src/app.js`, `assets/logo.svg`) resolve inside the bundle. There is no fallback to the entry file for unknown paths; use hash routes (`#/detail`) for client-side navigation.

## Running queries

The page is same-origin with the console, so `fetch` sends the session cookie by itself:

```js
const res = await fetch(`/${encodeURIComponent(ctx.workspace)}/api/v1beta2/queries`, {
  method: 'POST',
  redirect: 'manual',                       // see "session ended" below
  headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
  body: JSON.stringify({ sql: `SELECT ... FROM ${ctx.db}.events` }),
});
if (res.status === 401 || res.type === 'opaqueredirect') {
  // session ended: tell the user to sign in again in the console
}
```

- **Never build an `Authorization` header in the page**, and never ask for or store credentials.
- The query runs **as the viewer**: their permissions decide what it can read.
- **Session ended**: the query API answers 401, or (password login) a redirect to the logout page. With `redirect: 'manual'` the redirect shows up as `res.type === 'opaqueredirect'` instead of being followed. Show a "sign in again" message; do not retry in a loop.
- The response is Server-Sent Events: an `event: query` frame carrying `result.header` (column names and types), then unnamed `data:` frames, each a JSON array of rows (arrays in header order), plus `event: metrics` frames to ignore. A streaming query keeps the response open; cancel it with an `AbortController`. Leaving the page in the console removes the frame, which cancels its requests.
- Backfill batches of a streaming query are not globally ordered by time. Sort by your own timestamp column before applying them.

## What the browser allows

Every file is served with a fixed content security policy. Plan the bundle around it:

| Allowed | Blocked |
|---|---|
| Scripts loaded from files in the bundle (`<script src>`, ES modules, dynamic `import()`) | Inline `<script>` blocks, inline `onclick=`-style handlers, import maps, `eval`, `new Function` |
| WebAssembly | |
| Inline `<style>` and `style=` attributes | Stylesheets from another host (Google Fonts, CDNs) |
| Images and fonts from the bundle, `data:` and `blob:` URLs | Images, fonts, media from another host |
| `fetch` / `EventSource` / WebSocket to the same origin | Any network request to another host |
| Workers from the bundle or `blob:` | Pop-ups and top-level navigation (the console's frame sandbox) |

So **every dependency is vendored**: copy the library's built files into the bundle (`vendor/`), keep its license next to it, and import it by relative path. No CDN `<script>`, no CDN fallback, no web fonts from a font service (ship the font files or use a system font stack).

A build step (Vite, esbuild) is fine as long as its output directory is what `dir` points to and it emits no inline scripts.

Files are served with `Cache-Control: no-cache` and an `ETag`, so an upgrade shows on the next load without renaming files.

## Lifecycle and trust

- **Install** stores the bundles after the SQL resources and dashboards succeed. **Upgrade** replaces a bundle as a whole; a failed upgrade keeps the old one serving. **Uninstall** removes them, including with `preserve_data=true`.
- Installing an app is admin-only. Any signed-in user can open an installed page.
- A custom UI is **trusted code**, like the app's SQL: it can call any API the viewing user can. The policy above stops it from loading outside code or sending data elsewhere; it does not sandbox it from the console.

## Checking a UI

1. `make build` passes the package check with no warnings.
2. `make install`, then open the app in the console → **Custom UI** → the page. The console fetches the entry file before framing it, so a missing bundle shows an error, not a blank frame.
3. Open the browser's developer console: a policy violation is logged there and names the blocked resource.
4. `curl -i http://host:8000/{workspace}/apps/{app_id}/ui/{name}/` (add `-u user:password` when authentication is on) shows the entry file and its headers; `GET /{workspace}/api/v1beta2/apps/{app_id}` lists `uis` with `entry_url`, `file_count` and `size_bytes`.
5. Switch the console theme and check the page in both.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Install fails: `entry file "index.html" not found in web/live` | The bundle directory was not in the zip, or `entry` is wrong | Add `uis[].dir` to the zip command (use `--ui-dirs`); run the package check |
| Install fails: `file "…" has characters outside A-Z a-z 0-9 . _ - /` | A space or non-ASCII character in a file name | Rename the file |
| Blank page, console error `Refused to execute inline script` | Inline `<script>` or `onclick=` | Move the code to a `.js` file; attach handlers with `addEventListener` |
| Library missing, `Refused to load the script 'https://…'` | Loaded from a CDN | Vendor it into the bundle |
| Fonts fall back, `Refused to load the stylesheet` | Web font service | Ship the font files or use a system font stack |
| Query returns 401 with a correct password in the page | The page builds its own `Authorization` header or calls another host | Drop the header and the URL; call the same origin |
| Tests, README or `.DS_Store` reachable under the UI URL | They live inside `dir` | Move them out; exclude `.DS_Store` in the zip command |
| Old files still served after deleting them locally | `zip -r` updated an existing archive | Use `zip -FS`, or build to a fresh file |
| Page works when opened directly but queries the wrong database | Hard-coded database name | Read `db` from the URL |
