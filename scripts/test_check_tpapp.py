#!/usr/bin/env python3
"""Tests for check_tpapp.py. Run: python3 -m unittest discover -s scripts -p 'test_*.py'"""

import os
import tempfile
import unittest
import zipfile

import check_tpapp as c

MANIFEST = """\
package_format_version: 1
id: io.example.demo
db_name: demo
uis:
  - name: live
    title: Live
    dir: web/live
"""


class CheckTpapp(unittest.TestCase):
    def pkg(self, files, manifest=MANIFEST, symlink=None):
        fd, path = tempfile.mkstemp(suffix=".tpapp")
        os.close(fd)
        self.addCleanup(os.remove, path)
        with zipfile.ZipFile(path, "w") as z:
            z.writestr("manifest.yaml", manifest)
            for name, body in files.items():
                z.writestr(name, body)
            if symlink:
                info = zipfile.ZipInfo(symlink)
                info.external_attr = 0o120777 << 16
                z.writestr(info, "target")
        return path

    def bad(self, text, *args, **kw):
        with self.assertRaises(c.Invalid) as cm:
            c.check_package(self.pkg(*args, **kw))
        self.assertIn(text, str(cm.exception))

    def test_ok(self):
        uis, warnings = c.check_package(self.pkg({"web/live/index.html": "<script type=module src=a.js></script>", "web/live/a.js": "1"}))
        self.assertEqual(warnings, [])
        self.assertEqual((uis[0]["file_count"], uis[0]["size_bytes"], uis[0]["entry"]), (2, 39, "index.html"))

    def test_no_uis_passes(self):
        self.assertEqual(c.check_package(self.pkg({}, manifest="package_format_version: 1\nid: x\ndb_name: x\n")), ([], []))

    def test_missing_entry(self):
        self.bad('entry file "index.html" not found in web/live', {"web/live/main.html": "x"})

    def test_dir_not_packaged(self):
        self.bad('directory "web/live" not found', {"web/other/index.html": "x"})

    def test_file_too_large(self):
        self.bad("limit is 8.0 MiB", {"web/live/index.html": "x", "web/live/big.bin": b"\0" * (c.MAX_FILE_BYTES + 1)})

    def test_bundle_too_large(self):
        files = {"web/live/index.html": "x"}
        files.update({f"web/live/{n}.bin": b"\0" * c.MAX_FILE_BYTES for n in range(5)})
        self.bad("limit is 32.0 MiB", files)

    def test_bad_file_name(self):
        self.bad("characters outside", {"web/live/index.html": "x", "web/live/my file.js": "x"})

    def test_symlink(self):
        self.bad("is a symlink", {"web/live/index.html": "x"}, symlink="web/live/link.js")

    def test_manifest_rules(self):
        for bad, text in [
            (MANIFEST.replace("name: live", "name: Live"), "ui name"),
            (MANIFEST.replace("dir: web/live", "dir: ../live"), "must be a relative path"),
            (MANIFEST.replace("id: io.example.demo", "id: io.example/demo"), "cannot be used in a URL"),
            (MANIFEST + "    icon: nope\n", "invalid icon"),
            (MANIFEST + "  - name: live\n    dir: web/live\n", "duplicate ui name"),
        ]:
            self.bad(text, {"web/live/index.html": "x"}, manifest=bad)

    def test_policy_warnings(self):
        html = '<link href="https://fonts.example.com/a.css" rel=stylesheet><script>go()</script><button onclick="go()">x</button>'
        _, warnings = c.check_package(self.pkg({"web/live/index.html": html}))
        self.assertEqual(len(warnings), 3)

    def test_ui_dirs(self):
        self.assertEqual([u["dir"] for u in c.parse_uis(c.load_manifest(MANIFEST))], ["web/live"])


if __name__ == "__main__":
    unittest.main()
