#!/usr/bin/env python3
"""A small WebDAV server with Basic auth, for Himeko Files' network tests only (ops.sh selftest, headless checks).
   testdav.py DIR PORT USER PASS   (listens on 127.0.0.1)"""
import base64
import email.utils
import os
import shutil
import sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import quote, unquote, urlparse

ROOT, PORT, USER, PASS = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
AUTH = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def local(self, href):
        rel = unquote(urlparse(href).path).lstrip("/")
        p = os.path.realpath(os.path.join(ROOT, rel))
        return p if p == os.path.realpath(ROOT) or p.startswith(os.path.realpath(ROOT) + "/") else None

    def reply(self, code, body=b"", headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authed(self):
        if self.headers.get("Authorization") == AUTH:
            return True
        self.body()
        self.reply(401, headers=[("WWW-Authenticate", 'Basic realm="himeko"')])
        return False

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def entry(self, href, p):
        st = os.stat(p)
        is_dir = os.path.isdir(p)
        kind = "<D:resourcetype><D:collection/></D:resourcetype>" if is_dir else "<D:resourcetype/>"
        return (f"<D:response><D:href>{quote(href)}</D:href><D:propstat><D:prop>{kind}"
                f"<D:getcontentlength>{0 if is_dir else st.st_size}</D:getcontentlength>"
                f"<D:getlastmodified>{email.utils.formatdate(st.st_mtime, usegmt=True)}</D:getlastmodified>"
                "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>")

    def do_OPTIONS(self):
        if self.authed():
            self.reply(200, headers=[("DAV", "1"), ("Allow", "OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, PROPFIND")])

    def do_PROPFIND(self):
        if not self.authed():
            return
        self.body()
        href = unquote(urlparse(self.path).path)
        p = self.local(self.path)   # the raw path: decoding twice would cut a name at "#"
        if not p or not os.path.exists(p):
            return self.reply(404)
        out = [self.entry(href, p)]
        if os.path.isdir(p) and self.headers.get("Depth", "1") != "0":
            for name in sorted(os.listdir(p)):
                c = os.path.join(p, name)
                out.append(self.entry(href.rstrip("/") + "/" + name + ("/" if os.path.isdir(c) else ""), c))
        xml = '<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">' + "".join(out) + "</D:multistatus>"
        self.reply(207, xml.encode(), [("Content-Type", 'application/xml; charset="utf-8"')])

    def do_GET(self, head=False):
        if not self.authed():
            return
        p = self.local(self.path)
        if not p or not os.path.isfile(p):
            return self.reply(404)
        data = open(p, "rb").read()
        self.reply(200, b"" if head else data, [("Content-Type", "application/octet-stream")])

    def do_HEAD(self):
        self.do_GET(head=True)

    def do_PUT(self):
        if not self.authed():
            return
        data = self.body()
        p = self.local(self.path)
        if not p:
            return self.reply(403)
        with open(p, "wb") as f:
            f.write(data)
        self.reply(201)

    def do_MKCOL(self):
        if not self.authed():
            return
        self.body()
        p = self.local(self.path)
        if not p or os.path.exists(p):
            return self.reply(405)
        os.mkdir(p)
        self.reply(201)

    def do_DELETE(self):
        if not self.authed():
            return
        p = self.local(self.path)
        if not p or not os.path.exists(p):
            return self.reply(404)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
        self.reply(204)

    def do_MOVE(self):
        if not self.authed():
            return
        self.body()
        src, dst = self.local(self.path), self.local(self.headers.get("Destination", ""))
        if not src or not dst or not os.path.exists(src):
            return self.reply(404)
        if os.path.exists(dst) and self.headers.get("Overwrite", "T") == "F":
            return self.reply(412)
        os.replace(src, dst)
        self.reply(201)

    def do_PROPPATCH(self):
        if self.authed():
            self.body()
            self.reply(207, b'<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"/>', [("Content-Type", "application/xml")])

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()   # gvfs keeps two connections open
