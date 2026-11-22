"""SuperShot's optional review-link service. Run behind an HTTPS reverse proxy."""

import argparse
import base64
import binascii
import contextlib
import hashlib
import hmac
import html
import http.cookies
import ipaddress
import json
import math
import os
import re
import secrets
import sqlite3
import threading
import time
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


HERE = Path(__file__).resolve().parent
MEDIA_LIMIT = 64 * 1024 * 1024
STORE_LIMIT = 1024 * 1024 * 1024
FORM_LIMIT = 8192
REACTIONS = {"like": "Helpful", "love": "Love it", "eyes": "Looking", "check": "Done"}
ASSETS = {"/review.css": ("review.css", "text/css"), "/review.js": ("review.js", "text/javascript")}
SHARE_ROUTE = re.compile(r"/s/([a-f0-9]{32})(?:/(media|comments|reactions))?")
API_ROUTE = re.compile(r"/api/shares/([a-f0-9]{32})")
TOKEN = re.compile(r"[a-f0-9]{64}")

SCHEMA = """
CREATE TABLE IF NOT EXISTS shares (
    id TEXT PRIMARY KEY, token TEXT NOT NULL, title TEXT NOT NULL,
    mime TEXT NOT NULL, media BLOB NOT NULL, digest TEXT NOT NULL,
    byte_count INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS revoked (id TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS comments (
    id TEXT PRIMARY KEY, share_id TEXT NOT NULL REFERENCES shares(id) ON DELETE CASCADE,
    reply_to TEXT, name TEXT NOT NULL, body TEXT NOT NULL, x REAL, y REAL, seconds REAL,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE INDEX IF NOT EXISTS comments_by_share ON comments (share_id, created_at);
CREATE TABLE IF NOT EXISTS reactions (
    share_id TEXT NOT NULL REFERENCES shares(id) ON DELETE CASCADE,
    guest TEXT NOT NULL, reaction TEXT NOT NULL, PRIMARY KEY (share_id, guest)
);
"""


class HTTPProblem(Exception):
    def __init__(self, status, message, headers=None):
        self.status = status
        self.message = message
        self.headers = headers


class ReviewServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, data_directory, upload_key, public_url=None,
                 max_media_bytes=MEDIA_LIMIT, store_bytes=STORE_LIMIT):
        if not ipaddress.ip_address(address[0]).is_loopback:
            raise ValueError("Bind the service to a loopback address behind HTTPS.")
        if len(upload_key) < 32:
            raise ValueError("The upload key must be at least 32 characters.")
        if public_url:
            parts = urlsplit(public_url)
            if (parts.scheme != "https" or not parts.hostname or parts.path not in ("", "/")
                    or parts.query or parts.fragment or parts.username or parts.password):
                raise ValueError("Use the bare HTTPS origin as the public URL.")
        self.data_directory = data_directory
        data_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        data_directory.chmod(0o700)
        self.database = data_directory / "reviews.sqlite3"
        self.upload_key = upload_key.encode()
        self.guest_key = hmac.digest(self.upload_key, b"SuperShot guest forms", "sha256")
        self.max_media_bytes = max_media_bytes
        self.store_bytes = store_bytes
        self.slots = threading.BoundedSemaphore(8)
        self.feedback_lock = threading.Lock()
        self.feedback_windows = OrderedDict()
        with contextlib.closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript(SCHEMA)
        self.database.chmod(0o600)
        super().__init__(address, ReviewHandler)
        self.origin = public_url.rstrip("/") if public_url else f"http://127.0.0.1:{self.server_port}"
        self.secure = self.origin.startswith("https://")

    def connect(self):
        db = sqlite3.connect(self.database, timeout=5)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA secure_delete=ON")
        return db

    def admit_feedback(self, share_id, guest):
        now = time.monotonic()
        with self.feedback_lock:
            limits = [(share_id, 36), ((share_id, guest), 12)]
            accepted = []
            for key, limit in limits:
                started, count = self.feedback_windows.get(key, (now, 0))
                if now - started >= 60:
                    started, count = now, 0
                if count >= limit:
                    raise HTTPProblem(429, "Too many recent posts. Try again in a minute.")
                accepted.append((key, (started, count + 1)))
            for key, window in accepted:
                self.feedback_windows[key] = window
                self.feedback_windows.move_to_end(key)
            while len(self.feedback_windows) > 4096:
                self.feedback_windows.popitem(last=False)

    def get_request(self):
        request, address = super().get_request()
        request.settimeout(15)
        return request, address

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


class ReviewHandler(BaseHTTPRequestHandler):
    server_version = "SuperShotReview"
    sys_version = ""

    def do_GET(self):
        self.run("GET")

    def do_HEAD(self):
        self.run("HEAD")

    def do_PUT(self):
        self.run("PUT")

    def do_DELETE(self):
        self.run("DELETE")

    def do_POST(self):
        self.run("POST")

    def log_message(self, *_args):
        # Share IDs grant access. Keep them and the revocation tokens out of application logs.
        pass

    def run(self, method):
        try:
            path = urlsplit(self.path).path
            api = API_ROUTE.fullmatch(path)
            share = SHARE_ROUTE.fullmatch(path)
            if path in ASSETS and method in ("GET", "HEAD"):
                name, mime = ASSETS[path]
                self.respond(200, (HERE / name).read_bytes(), mime + "; charset=utf-8")
            elif api and method == "PUT":
                self.upload(api[1])
            elif api and method == "DELETE":
                self.revoke(api[1])
            elif share and share[2] == "media" and method in ("GET", "HEAD"):
                self.media(share[1])
            elif share and share[2] is None and method in ("GET", "HEAD"):
                self.page(share[1])
            elif share and share[2] in ("comments", "reactions") and method == "POST":
                self.feedback(share[1], share[2])
            else:
                raise HTTPProblem(404, "This review link is unavailable.")
        except HTTPProblem as error:
            if self.path.startswith("/s/") and "text/html" in self.headers.get("Accept", ""):
                self.html_error(error)
            else:
                self.json(error.status, {"error": error.message}, error.headers)
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        except ValueError:
            self.json(400, {"error": "The request URL is invalid."})
        except sqlite3.Error:
            self.json(503, {"error": "The review server could not access its storage."})

    def header_block(self, status, length, mime, headers=None):
        self.send_response(status)
        self.send_header("Content-Length", str(length))
        self.send_header("Content-Type", mime)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; img-src 'self'; media-src 'self'; "
            "style-src 'self'; script-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
        )
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()

    def respond(self, status, body=b"", mime="text/plain; charset=utf-8", headers=None):
        self.header_block(status, len(body), mime, headers)
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, status, value, headers=None):
        self.respond(status, json.dumps(value).encode(), "application/json", headers)

    def html_error(self, error):
        title = "Review link unavailable" if error.status == 404 else "Feedback could not be saved"
        path = SHARE_ROUTE.fullmatch(urlsplit(self.path).path)
        back = f'<p><a href="/s/{path[1]}">Back to review</a></p>' if path and error.status != 404 else ""
        markup = (
            '<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f'<title>{title} · SuperShot</title><link rel="stylesheet" href="/review.css"></head>'
            f'<body><header><span>SuperShot</span><h1>{title}</h1>'
            f'<p>{html.escape(error.message)}</p>{back}</header></body></html>'
        )
        self.respond(error.status, markup.encode(), "text/html; charset=utf-8", error.headers)

    def read_body(self, maximum):
        lengths = self.headers.get_all("Content-Length") or []
        if self.headers.get("Transfer-Encoding") or len(lengths) != 1:
            raise HTTPProblem(411, "A content length is required.")
        if not re.fullmatch(r"[0-9]{1,12}", lengths[0]):
            raise HTTPProblem(400, "The content length is invalid.")
        length = int(lengths[0])
        if length > maximum:
            raise HTTPProblem(413, "This file exceeds the review server’s size limit.")
        body = self.rfile.read(length)
        if len(body) != length:
            raise HTTPProblem(400, "The upload ended early.")
        return body

    def revocation_token(self):
        token = self.headers.get("X-Revocation-Token", "")
        if not TOKEN.fullmatch(token):
            raise HTTPProblem(403, "The revocation token is invalid.")
        return token_digest(token)

    def upload(self, share_id):
        expected = b"Bearer " + self.server.upload_key
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), expected):
            raise HTTPProblem(401, "The upload key was rejected.")
        token = self.revocation_token()
        mime = self.headers.get_content_type()
        if mime not in ("image/png", "video/mp4", "video/quicktime"):
            raise HTTPProblem(415, "Upload a PNG image or an MP4 or MOV video.")
        try:
            title = base64.b64decode(self.headers.get("X-Share-Title-B64", ""), validate=True).decode()
        except (binascii.Error, UnicodeDecodeError):
            raise HTTPProblem(400, "The capture title is invalid.")
        title = clean_text(title) or "Capture"
        if len(title) > 160:
            raise HTTPProblem(422, "Capture titles are limited to 160 characters.")
        media = self.read_body(self.server.max_media_bytes)
        is_png = media.startswith(b"\x89PNG\r\n\x1a\n") and media[12:16] == b"IHDR"
        is_video = len(media) >= 12 and media[4:8] == b"ftyp"
        if not (is_png if mime == "image/png" else is_video):
            raise HTTPProblem(415, "The file does not match its media type.")
        digest = hashlib.sha256(media).hexdigest()
        with contextlib.closing(self.server.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM revoked WHERE id = ?", (share_id,)).fetchone():
                raise HTTPProblem(410, "This review link was revoked.")
            old = db.execute("SELECT token, digest, title, mime FROM shares WHERE id = ?", (share_id,)).fetchone()
            if old:
                matches = hmac.compare_digest(old["token"], token) and (
                    old["digest"], old["title"], old["mime"]
                ) == (digest, title, mime)
                if not matches:
                    raise HTTPProblem(409, "That review link already exists with different content.")
            else:
                used = db.execute("SELECT coalesce(sum(byte_count), 0) FROM shares").fetchone()[0]
                if used + len(media) > self.server.store_bytes:
                    raise HTTPProblem(507, "The review server is out of storage.")
                db.execute(
                    "INSERT INTO shares VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (share_id, token, title, mime, media, digest, len(media)),
                )
        self.json(200 if old else 201, {"path": f"/s/{share_id}"})

    def revoke(self, share_id):
        token = self.revocation_token()
        with contextlib.closing(self.server.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT token FROM shares WHERE id = ?", (share_id,)).fetchone()
            if row:
                if not hmac.compare_digest(row["token"], token):
                    raise HTTPProblem(403, "The revocation token was rejected.")
                db.execute("DELETE FROM shares WHERE id = ?", (share_id,))
                db.execute("INSERT INTO revoked VALUES (?)", (share_id,))
        self.respond(204)

    def media(self, share_id):
        with contextlib.closing(self.server.connect()) as db, db:
            # A read transaction keeps the response consistent with a concurrent revoke.
            db.execute("BEGIN")
            share = db.execute("SELECT mime, byte_count FROM shares WHERE id = ?", (share_id,)).fetchone()
            if not share:
                raise HTTPProblem(404, "This review link is unavailable.")
            total = share["byte_count"]
            start, end = byte_range(self.headers.get("Range"), total)
            headers = {"Accept-Ranges": "bytes", "Content-Disposition": "inline"}
            if self.headers.get("Range"):
                headers["Content-Range"] = f"bytes {start}-{end}/{total}"
            status = 206 if "Content-Range" in headers else 200
            self.header_block(status, end - start + 1, share["mime"], headers)
            if self.command == "HEAD":
                return
            if hasattr(db, "blobopen"):
                row_id = db.execute("SELECT rowid FROM shares WHERE id = ?", (share_id,)).fetchone()[0]
                with db.blobopen("shares", "media", row_id, readonly=True) as data:
                    data.seek(start)
                    remaining = end - start + 1
                    while remaining:
                        chunk = data.read(min(remaining, 256 * 1024))
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
            else:
                data = db.execute("SELECT substr(media, ?, ?) FROM shares WHERE id = ?",
                                  (start + 1, end - start + 1, share_id)).fetchone()[0]
                self.wfile.write(data)

    def guest(self):
        try:
            cookie = http.cookies.SimpleCookie(self.headers.get("Cookie", ""))
        except http.cookies.CookieError:
            return ""
        item = cookie.get("supershot_guest")
        return item.value if item and TOKEN.fullmatch(item.value) else ""

    def nonce(self, share_id, guest):
        return hmac.digest(self.server.guest_key, f"{share_id}:{guest}".encode(), "sha256").hex()

    def page(self, share_id):
        with contextlib.closing(self.server.connect()) as db:
            share = db.execute("SELECT title, mime FROM shares WHERE id = ?", (share_id,)).fetchone()
            if not share:
                raise HTTPProblem(404, "This review link is unavailable.")
            comments = list(db.execute("SELECT * FROM comments WHERE share_id = ? ORDER BY created_at, rowid", (share_id,)))
            counts = dict(db.execute(
                "SELECT reaction, count(*) FROM reactions WHERE share_id = ? GROUP BY reaction", (share_id,),
            ))
        guest = self.guest() or secrets.token_hex(32)
        cookie = f"supershot_guest={guest}; Path=/; Max-Age=2592000; HttpOnly; SameSite=Strict"
        if self.server.secure:
            cookie += "; Secure"
        markup = review_page(share_id, share, comments, counts, self.nonce(share_id, guest))
        self.respond(200, markup.encode(), "text/html; charset=utf-8", {"Set-Cookie": cookie})

    def feedback(self, share_id, kind):
        origin = self.headers.get("Origin")
        if origin and origin != self.server.origin:
            raise HTTPProblem(403, "Open the review link directly to leave feedback.")
        if self.headers.get_content_type() != "application/x-www-form-urlencoded":
            raise HTTPProblem(415, "Use the feedback form on the review page.")
        try:
            pairs = parse_qs(self.read_body(FORM_LIMIT).decode(), max_num_fields=10, errors="strict")
        except (UnicodeError, ValueError):
            raise HTTPProblem(400, "The feedback form is invalid.")
        fields = {key: values[0] for key, values in pairs.items()}
        guest = self.guest()
        submitted = fields.get("nonce", "").encode()
        if not guest or not hmac.compare_digest(submitted, self.nonce(share_id, guest).encode()):
            raise HTTPProblem(403, "Reload the review page and try again.")
        with contextlib.closing(self.server.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            share = db.execute("SELECT mime FROM shares WHERE id = ?", (share_id,)).fetchone()
            if not share:
                raise HTTPProblem(404, "This review link is unavailable.")
            self.server.admit_feedback(share_id, guest)
            if kind == "comments":
                self.comment(db, share_id, share["mime"], fields)
            else:
                self.reaction(db, share_id, guest, fields)
        self.respond(303, headers={"Location": f"/s/{share_id}#feedback"})

    @staticmethod
    def comment(db, share_id, mime, fields):
        body = clean_text(fields.get("body", ""))
        name = clean_text(fields.get("name", "")) or "Guest"
        if not body or len(body) > 2000 or len(name) > 60:
            raise HTTPProblem(422, "Enter a comment up to 2,000 characters and a name up to 60 characters.")
        reply = fields.get("reply")
        if reply and not db.execute("SELECT 1 FROM comments WHERE id = ? AND share_id = ?", (reply, share_id)).fetchone():
            raise HTTPProblem(422, "The comment you are replying to is unavailable.")
        x = optional_number(fields.get("x"), maximum=1)
        y = optional_number(fields.get("y"), maximum=1)
        seconds = optional_number(fields.get("seconds"), maximum=24 * 3600)
        if (x is None) != (y is None) or (x is not None and mime != "image/png"):
            raise HTTPProblem(422, "This annotation position is invalid.")
        if seconds is not None and mime == "image/png":
            raise HTTPProblem(422, "Only videos support timestamps.")
        count = db.execute("SELECT count(*) FROM comments WHERE share_id = ?", (share_id,)).fetchone()[0]
        if count >= 500:
            raise HTTPProblem(429, "This review link has reached its comment limit.")
        db.execute("""
            INSERT INTO comments (id, share_id, reply_to, name, body, x, y, seconds)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (secrets.token_hex(12), share_id, reply, name, body, x, y, seconds))

    @staticmethod
    def reaction(db, share_id, guest, fields):
        reaction = fields.get("reaction")
        if reaction not in REACTIONS:
            raise HTTPProblem(422, "Choose a supported reaction.")
        old = db.execute("SELECT reaction FROM reactions WHERE share_id = ? AND guest = ?", (share_id, guest)).fetchone()
        if old and old["reaction"] == reaction:
            db.execute("DELETE FROM reactions WHERE share_id = ? AND guest = ?", (share_id, guest))
            return
        count = db.execute("SELECT count(*) FROM reactions WHERE share_id = ?", (share_id,)).fetchone()[0]
        if not old and count >= 1000:
            raise HTTPProblem(429, "This review link has reached its reaction limit.")
        db.execute("INSERT OR REPLACE INTO reactions VALUES (?, ?, ?)", (share_id, guest, reaction))


def optional_number(value, maximum):
    if not value:
        return None
    try:
        number = float(value)
    except ValueError:
        number = -1
    if not math.isfinite(number) or not 0 <= number <= maximum:
        raise HTTPProblem(422, "The annotation position or timestamp is invalid.")
    return round(number, 4)


def clean_text(value):
    return "".join(c for c in value.strip() if c in ("\n", "\t") or 32 <= ord(c) < 127 or ord(c) >= 160)


def token_digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def byte_range(value, total):
    if not value:
        return 0, total - 1
    match = re.fullmatch(r"bytes=([0-9]{0,12})-([0-9]{0,12})", value)
    if match:
        first, last = match.groups()
        if first:
            start = int(first)
            end = min(int(last), total - 1) if last else total - 1
            if start <= end:
                return start, end
        elif last and int(last) > 0:
            return max(0, total - int(last)), total - 1
    raise HTTPProblem(416, "This byte range is unavailable.", {"Content-Range": f"bytes */{total}"})


def review_page(share_id, share, comments, counts, nonce):
    escape = html.escape
    title = escape(share["title"])
    path = f"/s/{share_id}"
    nonce_input = f'<input type="hidden" name="nonce" value="{nonce}">'
    is_image = share["mime"] == "image/png"
    media = (f'<img id="capture" src="{path}/media" alt="Shared capture">'
             if is_image else f'<video id="capture" src="{path}/media" controls preload="metadata"></video>')
    markers = []
    cards = []
    for number, item in enumerate(comments, 1):
        comment_id = item["id"]
        context = ""
        if item["reply_to"]:
            context += f'<a href="#comment-{item["reply_to"]}">In reply</a> '
        if item["x"] is not None:
            markers.append(
                f'<a class="marker" data-x="{item["x"]}" data-y="{item["y"]}" '
                f'href="#comment-{comment_id}" aria-label="Comment {number}">{number}</a>'
            )
            context += f'<span>Image point {number}</span> '
        if item["seconds"] is not None:
            context += f'<button type="button" data-seconds="{item["seconds"]}">{item["seconds"]:g}s</button> '
        cards.append(
            f'<article id="comment-{comment_id}"><div class="comment-head">'
            f'<strong>{escape(item["name"])}</strong><span>{context}</span></div>'
            f'<p>{escape(item["body"])}</p>'
            f'<button type="button" data-reply="{comment_id}" data-name="{escape(item["name"])}">Reply</button></article>'
        )
    reactions = "".join(
        f'<button name="reaction" value="{key}" type="submit">{label} ({counts.get(key, 0)})</button>'
        for key, label in REACTIONS.items()
    )
    annotation = (
        '<button id="mark-capture" type="button">Mark a point</button>'
        '<input type="hidden" name="x"><input type="hidden" name="y">'
        if is_image else
        '<label>Video time in seconds <input name="seconds" type="number" min="0" max="86400" step="0.01"></label>'
        '<button id="set-time" type="button">Use current time</button>'
    )
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · SuperShot</title><link rel="stylesheet" href="/review.css"><script src="/review.js" defer></script></head>
<body><header><span>SuperShot</span><h1>{title}</h1></header><main>
<section aria-label="Shared capture"><div class="capture">{media}{"".join(markers)}<span id="draft-mark" hidden>+</span></div>
<form class="reactions" action="{path}/reactions" method="post" aria-label="Reactions">{nonce_input}{reactions}</form>
<p><a href="{path}/media" download>Download capture</a></p></section>
<section id="feedback" aria-labelledby="feedback-title"><h2 id="feedback-title">Feedback</h2>{"".join(cards)}
<form class="feedback" action="{path}/comments" method="post">{nonce_input}<input type="hidden" name="reply">
<div id="context" hidden><span id="context-label" role="status"></span><button id="clear-context" type="button">Clear</button></div>
<label>Your name <input name="name" maxlength="60" placeholder="Guest"></label>
<label>Comment <textarea name="body" maxlength="2000" rows="4" required></textarea></label>
<div class="actions">{annotation}<button class="primary" type="submit">Post comment</button></div>
</form></section></main></body></html>'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8730)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--public-url", help="HTTPS origin used by the reverse proxy")
    args = parser.parse_args()
    try:
        with ReviewServer(
            ("127.0.0.1", args.port), args.data, os.environ.get("SUPERSHOT_REVIEW_UPLOAD_KEY", ""), args.public_url,
        ) as server:
            print("Review server listening on 127.0.0.1:" + str(server.server_port), flush=True)
            server.serve_forever()
    except ValueError as error:
        parser.error(str(error))
    except KeyboardInterrupt:
        pass
