import base64
import http.cookiejar
import json
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from server import ReviewServer


PIXEL = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
)
UPLOAD_KEY = "u" * 40
SHARE_ID = "a" * 32
TOKEN = "b" * 64
SHARE_PATH = "/s/" + SHARE_ID
API_PATH = "/api/shares/" + SHARE_ID


class ReviewLinksTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.server = ReviewServer(
            ("127.0.0.1", 0), Path(self.directory.name), UPLOAD_KEY, max_media_bytes=1024,
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.origin = "http://127.0.0.1:" + str(self.server.server_port)
        cookie_jar = http.cookiejar.CookieJar()
        self.browser = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, method, path, body=None, headers=None, browser=False):
        request = urllib.request.Request(
            self.origin + path, data=body, method=method, headers=headers or {},
        )
        opener = self.browser.open if browser else urllib.request.urlopen
        try:
            result = opener(request, timeout=3)
        except urllib.error.HTTPError as error:
            result = error
        with result:
            return result.code, result.headers, result.read()

    def upload(self, body=PIXEL, upload_key=UPLOAD_KEY, token=TOKEN, mime="image/png"):
        return self.request("PUT", API_PATH, body, {
            "Authorization": "Bearer " + upload_key,
            "Content-Type": mime,
            "X-Share-Title-B64": base64.b64encode("Review <draft> 🐈".encode()).decode(),
            "X-Revocation-Token": token,
        })

    def form(self, path, fields):
        return self.request("POST", path, urllib.parse.urlencode(fields).encode(), {
            "Content-Type": "application/x-www-form-urlencoded",
            "Origin": self.origin,
        }, browser=True)

    def guest_nonce(self):
        status, _, body = self.request("GET", SHARE_PATH, browser=True)
        self.assertEqual(status, 200)
        return re.search(rb'name="nonce" value="([a-z0-9]+)"', body).group(1).decode()

    def test_upload_link_escaping_media_and_revoke(self):
        status, _, body = self.upload()
        self.assertEqual(status, 201)
        self.assertEqual(json.loads(body)["path"], SHARE_PATH)
        status, headers, page = self.request("GET", SHARE_PATH)
        self.assertEqual(status, 200)
        self.assertIn(b"Review &lt;draft&gt;", page)
        self.assertNotIn(TOKEN.encode(), page)
        self.assertIn("noindex", headers["X-Robots-Tag"])
        status, headers, media = self.request("GET", SHARE_PATH + "/media")
        self.assertEqual((status, headers["Content-Type"], media), (200, "image/png", PIXEL))
        self.assertEqual(self.request("DELETE", API_PATH, headers={"X-Revocation-Token": "c" * 64})[0], 403)
        self.assertEqual(self.request("DELETE", API_PATH, headers={"X-Revocation-Token": TOKEN})[0], 204)
        self.assertEqual(self.request("GET", SHARE_PATH)[0], 404)
        self.assertEqual(self.request("GET", SHARE_PATH + "/media")[0], 404)
        self.assertEqual(self.request("DELETE", API_PATH, headers={"X-Revocation-Token": TOKEN})[0], 204)
        self.assertEqual(self.upload()[0], 410)

    def test_upload_retries_and_input_limits(self):
        self.assertEqual(self.upload(upload_key="invalid")[0], 401)
        self.assertEqual(self.upload(body=b"<html>bad</html>")[0], 415)
        self.assertEqual(self.upload(body=PIXEL * 64)[0], 413)
        self.assertEqual(self.upload()[0], 201)
        self.assertEqual(self.upload()[0], 200)
        self.assertEqual(self.upload(token="c" * 64)[0], 409)
        self.assertEqual(self.request("GET", SHARE_PATH + "/../server.py")[0], 404)

    def test_guest_comments_reply_marks_reactions_and_csrf(self):
        self.assertEqual(self.upload()[0], 201)
        nonce = self.guest_nonce()
        fields = {"nonce": nonce, "name": "Guest", "body": "<script> unsafe </script>", "x": "0.25", "y": "0.80"}
        self.assertEqual(self.form(SHARE_PATH + "/comments", fields)[0], 200)
        status, _, page = self.request("GET", SHARE_PATH, browser=True)
        self.assertEqual(status, 200)
        self.assertIn(b"&lt;script&gt; unsafe &lt;/script&gt;", page)
        self.assertNotIn(b"<script> unsafe", page)
        self.assertIn(b'data-x="0.25"', page)
        parent = re.search(rb'id="comment-([a-z0-9]+)"', page).group(1).decode()
        fields = {"nonce": nonce, "body": "Reply text", "reply": parent}
        self.assertEqual(self.form(SHARE_PATH + "/comments", fields)[0], 200)
        self.assertIn(b"Reply text", self.request("GET", SHARE_PATH, browser=True)[2])
        self.assertEqual(self.form(SHARE_PATH + "/reactions", {"nonce": nonce, "reaction": "like"})[0], 200)
        self.assertIn(b"Helpful (1)", self.request("GET", SHARE_PATH, browser=True)[2])
        self.assertEqual(self.form(SHARE_PATH + "/reactions", {"nonce": nonce, "reaction": "love"})[0], 200)
        page = self.request("GET", SHARE_PATH, browser=True)[2]
        self.assertIn(b"Helpful (0)", page)
        self.assertIn(b"Love it (1)", page)
        self.assertEqual(self.form(SHARE_PATH + "/comments", {"nonce": "fake", "body": "forged"})[0], 403)
        self.assertEqual(self.form(SHARE_PATH + "/comments", {"nonce": nonce, "body": "bad", "x": "nan", "y": "2"})[0], 422)

    def test_video_range_and_timestamp(self):
        mp4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 12
        self.assertEqual(self.upload(body=mp4, mime="video/mp4")[0], 201)
        status, headers, media = self.request("GET", SHARE_PATH + "/media", headers={"Range": "bytes=4-7"})
        self.assertEqual((status, headers["Content-Range"], media), (206, "bytes 4-7/24", b"ftyp"))
        nonce = self.guest_nonce()
        self.assertEqual(self.form(SHARE_PATH + "/comments", {"nonce": nonce, "body": "At the intro", "seconds": "1.5"})[0], 200)
        self.assertIn(b'data-seconds="1.5"', self.request("GET", SHARE_PATH)[2])
        status, headers, body = self.request("GET", SHARE_PATH + "/media", headers={"Range": "bytes=99-"})
        self.assertEqual((status, headers["Content-Range"]), (416, "bytes */24"))
        self.assertNotEqual(body, mp4)
        status, headers, body = self.request("HEAD", SHARE_PATH + "/media")
        self.assertEqual((status, headers["Content-Length"], body), (200, "24", b""))

    def test_guest_rate_limit(self):
        self.assertEqual(self.upload()[0], 201)
        nonce = self.guest_nonce()
        for index in range(12):
            self.assertEqual(self.form(SHARE_PATH + "/comments", {"nonce": nonce, "body": "Comment " + str(index)})[0], 200)
        self.assertEqual(self.form(SHARE_PATH + "/comments", {"nonce": nonce, "body": "Rate limited"})[0], 429)

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "Requires the macOS Swift toolchain")
    def test_native_transport_against_service(self):
        tools = Path(__file__).resolve().parent
        root = tools.parent.parent
        with tempfile.TemporaryDirectory() as temporary:
            binary = str(Path(temporary) / "review-links-native-test")
            subprocess.run([
                "swiftc", "-swift-version", "6",
                str(root / "Sources/SuperShotApp/ReviewLinksClient.swift"),
                str(tools / "test_client.swift"), "-o", binary,
            ], check=True, timeout=60)
            subprocess.run([binary, self.origin], check=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
