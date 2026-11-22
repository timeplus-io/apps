#!/usr/bin/env python3
"""
Check the custom UIs of a Timeplus app package before it is installed.

  check_tpapp.py <app>.tpapp           validate a built package
  check_tpapp.py --ui-dirs <manifest>  print the `dir` of every UI in a manifest,
                                       one per line (what the build must zip)

The rules are the ones the API server applies at install (neutron,
internal/app/installer/manifest.go and internal/app/uibundle/bundle.go), so a
package that passes here is not refused there for its `uis:` section. A
package without `uis:` only gets the package-wide checks.

Exit status: 0 ok, 1 the package is invalid, 2 usage or I/O error.
"""

import re
import stat
import sys
import zipfile

import yaml

MIB = 1 << 20
MAX_FILE_BYTES = 8 * MIB        # one file of a UI
MAX_BUNDLE_BYTES = 32 * MIB     # all files of one UI
MAX_FILES = 2000                # files in one UI
MAX_UIS = 8                     # UIs in one app
MAX_PACKAGE_BYTES = 128 * MIB   # whole package, uncompressed

UI_NAME = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
APP_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
BUNDLE_PATH = re.compile(r"^[A-Za-z0-9._/-]+$")

INLINE_SCRIPT = re.compile(rb"<script\b(?![^>]*\bsrc\s*=)[^>]*>\s*[^\s<]", re.I)
INLINE_HANDLER = re.compile(rb"<[a-z][^>]*\son[a-z]+\s*=", re.I)
# The console's own storage keys. A page is same-origin and can read them, but they are not
# part of the page contract: theme and language come from the URL and the context message.
CONSOLE_STORAGE = re.compile(rb"""localStorage\s*(?:\.\s*(?:theme|i18nextLng)\b|\[\s*["'`](?:theme|i18nextLng)["'`]\s*\]|\.\s*getItem\(\s*["'`](?:theme|i18nextLng)["'`])""")
EXTERNAL_REF = re.compile(rb"<(?:script|link|img|iframe|source)\b[^>]*\b(?:src|href)\s*=\s*[\"']?(?:https?:)?//", re.I)


class Invalid(Exception):
    pass


def fmt_bytes(n):
    if n >= MIB:
        return f"{n / MIB:.1f} MiB"
    if n >= 1 << 10:
        return f"{n / (1 << 10):.1f} KiB"
    return f"{n} B"


def valid_rel_path(p):
    if not isinstance(p, str) or not p or p.startswith("/") or "\\" in p:
        return False
    return all(seg not in ("", ".", "..") for seg in p.split("/"))


def valid_icon(icon):
    if not icon:
        return True
    return isinstance(icon, str) and icon.startswith("data:image/") and ";base64," in icon and bool(icon.split(";base64,", 1)[1])


def parse_uis(manifest):
    """Validate the `uis:` section. Returns [{name, title, dir, entry}] with defaults applied."""
    uis = manifest.get("uis") or []
    if not uis:
        return []
    if not isinstance(uis, list) or not all(isinstance(u, dict) for u in uis):
        raise Invalid("uis must be a list of mappings")
    app_id = str(manifest.get("id") or "")
    if not APP_ID.match(app_id):
        raise Invalid(f'app id "{app_id}" cannot be used in a URL; a package with uis needs an id of letters, digits, \'.\', \'_\' and \'-\'')
    if len(uis) > MAX_UIS:
        raise Invalid(f"{len(uis)} uis declared, at most {MAX_UIS} are allowed")
    out, seen = [], set()
    for u in uis:
        name = u.get("name")
        if not isinstance(name, str) or not UI_NAME.match(name):
            raise Invalid(f'ui name "{name}" must be lower-case letters, digits and \'-\', starting with a letter, at most 32 characters')
        if name in seen:
            raise Invalid(f'duplicate ui name "{name}"')
        seen.add(name)
        d, entry = u.get("dir"), u.get("entry") or "index.html"
        if not valid_rel_path(d):
            raise Invalid(f'ui "{name}": dir "{d}" must be a relative path inside the package')
        if not valid_rel_path(entry):
            raise Invalid(f'ui "{name}": entry "{entry}" must be a relative path inside dir')
        if not valid_icon(u.get("icon")):
            raise Invalid(f'ui "{name}": invalid icon: must be a data:image/...;base64,... URI')
        out.append({"name": name, "title": u.get("title") or name, "dir": d, "entry": entry})
    return out


def load_manifest(text):
    m = yaml.safe_load(text)
    if not isinstance(m, dict):
        raise Invalid("manifest.yaml is not a mapping")
    return m


def check_package(path):
    """Validate a .tpapp. Returns (uis with file_count/size_bytes, warnings)."""
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        total = 0
        for i in infos:
            if "\\" in i.filename:
                raise Invalid(f'zip entry "{i.filename}" has a backslash in its name')
            if stat.S_ISLNK(i.external_attr >> 16):
                raise Invalid(f'zip entry "{i.filename}" is a symlink; zip the files it points to instead')
            total += i.file_size
        if total > MAX_PACKAGE_BYTES:
            raise Invalid(f"package is {fmt_bytes(total)} uncompressed, limit is {fmt_bytes(MAX_PACKAGE_BYTES)}")
        try:
            manifest = load_manifest(z.read("manifest.yaml"))
        except KeyError:
            raise Invalid("manifest.yaml not found at the root of the package") from None

        files = [i for i in infos if not i.is_dir()]
        uis, warnings = parse_uis(manifest), []
        for ui in uis:
            name, prefix = ui["name"], ui["dir"] + "/"
            members = [i for i in files if i.filename.startswith(prefix)]
            if not members:
                raise Invalid(f'ui "{name}": directory "{ui["dir"]}" not found in the package (is it in the zip command?)')
            size = 0
            for i in members:
                rel = i.filename[len(prefix):]
                if not BUNDLE_PATH.match(rel) or not valid_rel_path(rel):
                    raise Invalid(f'ui "{name}": file "{rel}" has characters outside A-Z a-z 0-9 . _ - /')
                if i.file_size > MAX_FILE_BYTES:
                    raise Invalid(f'ui "{name}": file "{rel}" is {fmt_bytes(i.file_size)}, limit is {fmt_bytes(MAX_FILE_BYTES)}')
                size += i.file_size
            if len(members) > MAX_FILES:
                raise Invalid(f'ui "{name}": bundle has {len(members)} files, limit is {MAX_FILES}')
            if size > MAX_BUNDLE_BYTES:
                raise Invalid(f'ui "{name}": bundle is {fmt_bytes(size)}, limit is {fmt_bytes(MAX_BUNDLE_BYTES)}')
            if prefix + ui["entry"] not in {i.filename for i in members}:
                raise Invalid(f'ui "{name}": entry file "{ui["entry"]}" not found in {ui["dir"]}')
            ui["file_count"], ui["size_bytes"] = len(members), size

            # Things the server accepts but its content security policy stops in the browser.
            for i in members:
                lower = i.filename.lower()
                if not lower.endswith((".html", ".htm", ".js", ".mjs")):
                    continue
                rel, body = i.filename[len(prefix):], z.read(i)
                if CONSOLE_STORAGE.search(body):
                    warnings.append(f'ui "{name}": {rel} reads the console\'s localStorage (theme or i18nextLng); those keys are internal, take theme and locale from the entry URL and the timeplus:context message')
                if not lower.endswith((".html", ".htm")):
                    continue
                if INLINE_SCRIPT.search(body):
                    warnings.append(f'ui "{name}": {rel} has an inline <script>; the page policy only runs scripts loaded from files')
                if INLINE_HANDLER.search(body):
                    warnings.append(f'ui "{name}": {rel} has an inline event handler (on...=); the page policy blocks it')
                if EXTERNAL_REF.search(body):
                    warnings.append(f'ui "{name}": {rel} loads a resource from another host; the page policy blocks it, vendor the file into the bundle')
    return uis, warnings


def main(argv):
    if len(argv) == 3 and argv[1] == "--ui-dirs":
        with open(argv[2]) as f:
            for ui in parse_uis(load_manifest(f.read())):
                print(ui["dir"])
        return 0
    if len(argv) != 2 or argv[1].startswith("-"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    uis, warnings = check_package(argv[1])
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    for ui in uis:
        print(f'  ui "{ui["name"]}": {ui["file_count"]} files, {fmt_bytes(ui["size_bytes"])}, entry {ui["entry"]}')
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Invalid as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    except (OSError, zipfile.BadZipFile, yaml.YAMLError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
