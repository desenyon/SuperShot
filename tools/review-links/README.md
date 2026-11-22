# SuperShot Review Links

Review Links lets you upload a flattened screenshot or an exported video to a server you operate. Anyone with the link can view the capture and leave guest comments, replies, and reactions. Guests can attach a point to a screenshot or a timestamp to a video comment.

## Run a server

Use Python 3.9 or later. Python 3.11 or later streams media directly from SQLite. Put the service on an HTTPS origin dedicated to reviews. The Python process binds to loopback. Terminate TLS at your reverse proxy on the same host.

1. Generate an upload key with `openssl rand -hex 32`. Keep the key in a password manager or your service manager’s secret store.
2. Supply the key to the process as `SUPERSHOT_REVIEW_UPLOAD_KEY`.
3. Start the process using a dedicated data directory writable by the service account.

```zsh
python3 tools/review-links/server.py \
  --data /var/lib/supershot-reviews \
  --port 8730 \
  --public-url https://reviews.example.com
```

Forward the whole origin to `http://127.0.0.1:8730` with your proxy. Accept request bodies up to 64 MiB and preserve the `Origin`, `Authorization`, `X-Share-Title-B64`, and `X-Revocation-Token` request headers. Disable or redact access logs for review paths since their IDs grant access. The service limits the number of simultaneous requests, the size and total storage of uploads, and the rate and volume of guest feedback.

For local testing, omit `--public-url` and use `http://127.0.0.1:8730` in SuperShot. Others need a reachable HTTPS origin to open links you create.

## Use Review Links

1. Choose **Create Review Link** in SuperShot and check the screenshot or recording shown.
2. Enter the server’s HTTPS origin and the upload key on your first upload.
3. Choose **Upload and Create Link**, then **Copy Link** or **Open in Browser**. The app sends the rendered media and the title you entered. Screenshot project layers, recognized text, and Ask conversations stay on your Mac.
4. Open **Manage Review Links** to revoke a link. Revoking removes the hosted media and feedback and prevents a retry from recreating the same link. Recipients may still have downloaded copies.

SuperShot keeps the server address, upload key, and revocation receipts in its private Application Support directory. Back up that directory if you need to retain revocation access from this Mac. The server stores a hash of each revocation token. Its SQLite database contains media and feedback, so protect the data directory and its backups.

## Test locally

```zsh
python3 -B tools/review-links/test_server.py -v
```

The tests use a temporary database and a local port. They exercise uploads, retries, revocation, format and size limits, guest forms and rate limits, escaped text, image points, timestamp feedback, and media byte ranges. On a Mac with Swift installed, they also compile the app’s review client and exercise create, retry, download, and revoke against the running fixture server.
