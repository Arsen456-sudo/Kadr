"""Kadr development social API, Python 3.11+, SQLite, no third party dependencies.

Set KADR_AUTH_SECRET to a random secret of at least 32 characters, then run:
  python social_server.py --create-user nickname 'Display name'
  python social_server.py --port 8080
Provisioning prints a short-lived bearer session for that user. This is an admin
development command, not a public authentication endpoint. Production must issue
sessions only after verifying Apple/Google credentials and terminate HTTPS at the
reverse proxy. RemoteSocialRepository accepts that HTTPS URL and a token provider.
The iOS app continues to use LocalSocialRepository until account sync is enabled.
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def canonical_id(value):
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        raise APIError(400, "Некоректний ідентифікатор.")


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


class SocialService:
    def __init__(self, database, secret):
        self.database, self.secret = str(database), secret.encode()
        with self.connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS profiles (
                    id TEXT PRIMARY KEY, handle TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    name TEXT NOT NULL, bio TEXT NOT NULL DEFAULT ''
                );
                CREATE TABLE IF NOT EXISTS follows (
                    follower TEXT NOT NULL REFERENCES profiles(id),
                    followed TEXT NOT NULL REFERENCES profiles(id),
                    PRIMARY KEY(follower, followed), CHECK(follower != followed)
                );
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    sender TEXT NOT NULL REFERENCES profiles(id),
                    recipient TEXT NOT NULL REFERENCES profiles(id),
                    text TEXT NOT NULL CHECK(length(text) BETWEEN 1 AND 4000),
                    created TEXT NOT NULL, CHECK(sender != recipient)
                );
                CREATE INDEX IF NOT EXISTS messages_pair ON messages(sender, recipient, created);
                CREATE INDEX IF NOT EXISTS messages_recipient ON messages(recipient, created);
            """)

    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def issue_session(self, user):
        body = b64(json.dumps({"sub": user, "exp": int(time.time()) + 86400}, separators=(",", ":")).encode())
        return (body + b"." + b64(hmac.digest(self.secret, body, "sha256"))).decode()

    def authenticate(self, header):
        try:
            scheme, token = header.split(" ", 1)
            if scheme.lower() != "bearer" or len(token) > 2048:
                raise ValueError()
            body, signature = token.encode().split(b".", 1)
            if not hmac.compare_digest(signature, b64(hmac.digest(self.secret, body, "sha256"))):
                raise ValueError()
            claims = json.loads(base64.urlsafe_b64decode(body + b"=" * (-len(body) % 4)))
            if not isinstance(claims["exp"], (int, float)) or claims["exp"] <= time.time():
                raise ValueError()
            user = canonical_id(claims["sub"])
            with self.connect() as db:
                if db.execute("SELECT id FROM profiles WHERE id=?", (user,)).fetchone() is None:
                    raise ValueError()
            return user
        except (ValueError, KeyError, TypeError, APIError):
            raise APIError(401, "Увійди знову. Сесія недійсна або завершилася.")

    @staticmethod
    def message(row):
        return {"id": row["id"], "senderID": row["sender"], "recipientID": row["recipient"],
                "text": row["text"], "createdAt": row["created"]}

    def route(self, user, method, path, query, body):
        parts = path.strip("/").split("/")
        with self.connect() as db:
            if parts == ["users"] and method == "GET":
                term = query.get("handle", [""])[0].strip().lower().lstrip("@")
                if len(term) > 24:
                    raise APIError(400, "Нікнейм надто довгий.")
                # Prefix search treats underscores literally, not as LIKE wildcards.
                escaped = term.replace("\\", "\\\\").replace("_", "\\_").replace("%", "\\%")
                return [dict(row) for row in db.execute(
                    "SELECT id, handle, name, bio FROM profiles WHERE handle LIKE ? ESCAPE '\\' ORDER BY handle LIMIT 100",
                    (escaped + "%",))]
            if len(parts) == 3 and parts[0] == "users" and parts[2] == "follow" and method in ("PUT", "DELETE"):
                peer = canonical_id(parts[1])
                if peer == user:
                    raise APIError(400, "Не можна підписатися на себе.")
                if db.execute("SELECT id FROM profiles WHERE id=?", (peer,)).fetchone() is None:
                    raise APIError(404, "Профіль не знайдено.")
                if method == "PUT":
                    db.execute("INSERT OR IGNORE INTO follows VALUES (?,?)", (user, peer))
                else:
                    db.execute("DELETE FROM follows WHERE follower=? AND followed=?", (user, peer))
                return {"following": method == "PUT"}
            if parts == ["conversations"] and method == "GET":
                rows = db.execute("""
                    SELECT * FROM (
                        SELECT messages.*, ROW_NUMBER() OVER (
                            PARTITION BY CASE WHEN sender=? THEN recipient ELSE sender END
                            ORDER BY created DESC, id DESC) AS rank
                        FROM messages WHERE sender=? OR recipient=?
                    ) WHERE rank=1 ORDER BY created DESC LIMIT 100
                """, (user, user, user)).fetchall()
                result = []
                for row in rows:
                    peer = row["recipient"] if row["sender"] == user else row["sender"]
                    profile = db.execute("SELECT id, handle, name, bio FROM profiles WHERE id=?", (peer,)).fetchone()
                    result.append({"profile": dict(profile), "lastMessage": self.message(row)})
                return result
            if len(parts) == 3 and parts[0] == "conversations" and parts[2] == "messages":
                peer = canonical_id(parts[1])
                if peer == user or db.execute("SELECT id FROM profiles WHERE id=?", (peer,)).fetchone() is None:
                    raise APIError(404, "Профіль не знайдено.")
                pair = (user, peer, peer, user)
                condition = "((sender=? AND recipient=?) OR (sender=? AND recipient=?))"
                if method == "GET":
                    rows = db.execute(f"SELECT * FROM messages WHERE {condition} ORDER BY created DESC, id DESC LIMIT 500", pair).fetchall()
                    return [self.message(row) for row in reversed(rows)]
                if method == "POST":
                    message_id = canonical_id(body.get("id"))
                    text = body.get("text")
                    if not isinstance(text, str) or not 1 <= len(text.strip()) <= 4000:
                        raise APIError(400, "Повідомлення має містити від 1 до 4000 символів.")
                    text = text.strip()
                    # Serialize permission checks and insertion, including simultaneous retries.
                    db.execute("BEGIN IMMEDIATE")
                    existing = db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
                    if existing:
                        if existing["sender"] != user or existing["recipient"] != peer or existing["text"] != text:
                            raise APIError(409, "Ідентифікатор повідомлення вже використано.")
                        return self.message(existing)
                    followed = db.execute("SELECT 1 FROM follows WHERE follower=? AND followed=?", (user, peer)).fetchone()
                    conversation = db.execute(f"SELECT 1 FROM messages WHERE {condition} LIMIT 1", pair).fetchone()
                    if not followed and not conversation:
                        raise APIError(403, "Підпишись на користувача, щоб почати чат.")
                    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    db.execute("INSERT INTO messages VALUES (?,?,?,?,?)", (message_id, user, peer, text, created))
                    return {"id": message_id, "senderID": user, "recipientID": peer, "text": text, "createdAt": created}
            raise APIError(404, "Шлях не знайдено.")


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, data):
        payload = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self.handle_api()

    do_POST = do_PUT = do_DELETE = do_GET

    def handle_api(self):
        try:
            user = self.server.social.authenticate(self.headers.get("Authorization", ""))
            url = urlparse(self.path)
            if len(self.path) > 2048:
                raise APIError(400, "Запит надто довгий.")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 <= length <= 32768:
                raise APIError(413, "Запит надто великий.")
            body = json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(body, dict):
                raise APIError(400, "Очікується JSON-об’єкт.")
            self.respond(200, self.server.social.route(user, self.command, url.path, parse_qs(url.query), body))
        except APIError as error:
            self.respond(error.status, {"error": error.message})
        except (ValueError, UnicodeDecodeError):
            self.respond(400, {"error": "Некоректний запит."})
        except sqlite3.Error:
            self.respond(503, {"error": "Сховище тимчасово недоступне."})

    def log_message(self, *_):
        pass  # Do not log private handles, tokens, or message text.


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--database", default=str(Path(__file__).with_name("social.sqlite3")))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--create-user", nargs=2, metavar=("HANDLE", "NAME"))
    args = parser.parse_args()
    secret = os.environ.get("KADR_AUTH_SECRET", "")
    if len(secret) < 32:
        parser.error("Set KADR_AUTH_SECRET to a random secret of at least 32 characters.")
    service = SocialService(args.database, secret)
    if args.create_user:
        handle, name = args.create_user
        handle = handle.lower().lstrip("@")
        if not re.fullmatch(r"[a-z0-9_]{3,24}", handle) or not name.strip():
            parser.error("Use a valid handle (3–24 a-z, 0-9, _) and a nonempty name.")
        user = str(uuid.uuid4())
        with service.connect() as db:
            db.execute("INSERT INTO profiles(id,handle,name) VALUES (?,?,?)", (user, handle, name.strip()))
        print(json.dumps({"id": user, "handle": handle, "token": service.issue_session(user)}))
        return
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.social = service
    server.serve_forever()


if __name__ == "__main__":
    main()
