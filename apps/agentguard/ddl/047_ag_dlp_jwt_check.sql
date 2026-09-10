CREATE OR REPLACE FUNCTION ag_dlp_jwt_check(v string)
RETURNS bool
LANGUAGE JAVASCRIPT AS $$
function ag_dlp_jwt_check(values) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function b64decode(s) {
    s = s.replace(/-/g,'+').replace(/_/g,'/');
    while (s.length % 4) s += '=';
    var out = '', buf = 0, acc = 0;
    for (var i = 0; i < s.length; i++) {
      var n = chars.index_of(s[i]);
      if (n < 0) { if (s[i]==='=') break; return null; }
      buf = (buf << 6) | n; acc += 6;
      if (acc >= 8) { acc -= 8; out += String.fromCharCode((buf >> acc) & 0xff); }
    }
    return out;
  }
  return values.map(function(v) {
    if (typeof v !== 'string') return false;
    // Find JWT pattern anywhere in the string
    var m = v.match(/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}/);
    if (!m) return false;
    var parts = m[0].split('.');
    if (parts.length !== 3) return false;
    // Validate by decoding header — must contain 'alg' field
    try {
      var header = b64decode(parts[0]);
      if (header && header.index_of('alg') >= 0) return true;
    } catch(e) {}
    // Fallback: validate payload is parseable JSON
    try {
      var payload = b64decode(parts[1]);
      if (payload) { JSON.parse(payload); return true; }
    } catch(e) {}
    return false;
  });
}
$$
