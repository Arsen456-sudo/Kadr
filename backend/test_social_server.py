"""Isolated HTTP integration checks; never use the app's database or accounts."""
import base64
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from social_server import Handler, SocialService, ThreadingHTTPServer


class SocialHTTPTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.service = SocialService(Path(self.directory.name) / "test.sqlite3", "test-only-secret-" * 4)
        self.users = [str(uuid.uuid4()) for _ in range(3)]
        with self.service.connect() as db:
            for user, handle in zip(self.users, ["alpha_one", "alphaXone", "gamma_user"]):
                db.execute("INSERT INTO profiles(id,handle,name) VALUES (?,?,?)", (user, handle, handle))
        self.tokens = [self.service.issue_session(user) for user in self.users]
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.social = self.service
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        self.directory.cleanup()

    def request(self, path, user=0, method="GET", body=None, raw=None, token=None):
        data = raw if raw is not None else json.dumps(body).encode() if body is not None else None
        headers = {"Authorization": "Bearer " + (token if token is not None else self.tokens[user])}
        if body is not None: headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = response.read()
                return response.status, json.loads(payload) if response.headers.get_content_type() == "application/json" and payload else payload
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def record(self, resource, key, value, user=0):
        return {"owner": self.users[user], "resource": resource, "entityID": key,
                "payload": base64.b64encode(json.dumps(value).encode()).decode()}

    def push(self, *records, user=0):
        return self.request("/sync", user=user, method="POST", body=list(records))

    def test_invalid_session_is_rejected(self):
        self.assertEqual(self.request("/users", token=self.tokens[0] + "corrupt")[0], 401)

    def test_username_underscore_is_literal(self):
        code, profiles = self.request("/users?handle=alpha_")
        self.assertEqual(code, 200)
        self.assertEqual([profile["handle"] for profile in profiles], ["alpha_one"])

    def test_chat_follow_gate_idempotency_and_participant_isolation(self):
        target = self.users[1]
        message = {"id": str(uuid.uuid4()), "text": "Private test"}
        path = "/conversations/" + target + "/messages"
        self.assertEqual(self.request(path, method="POST", body=message)[0], 403)
        self.assertEqual(self.request("/users/" + target + "/follow", method="PUT")[0], 200)
        self.assertEqual(self.request(path, method="POST", body=message)[0], 200)
        self.assertEqual(self.request(path, method="POST", body=message)[0], 200)
        self.assertEqual(len(self.request(path)[1]), 1)
        self.assertEqual(self.request("/conversations/" + self.users[0] + "/messages", user=2)[1], [])
        collision = {**message, "text": "A different payload"}
        self.assertEqual(self.request(path, method="POST", body=collision)[0], 409)

    def test_forged_sync_owner_is_rejected(self):
        record = self.record("preferences", self.users[1], {"preferences": {}}, user=1)
        self.assertEqual(self.push(record)[0], 403)

    def test_private_preferences_and_posts_do_not_leak(self):
        post_id = str(uuid.uuid4())
        post = {"id": post_id, "authorID": self.users[0], "caption": "Private", "options": {"onlyMe": True}}
        self.assertEqual(self.push(self.record("preferences", self.users[0], {"privateNote": "secret"}), self.record("post", post_id, post))[0], 200)
        code, page = self.request("/sync", user=1)
        self.assertEqual(code, 200)
        self.assertEqual(page["records"], [])
        self.assertGreater(page["cursor"], 0)

    def test_asset_bytes_and_visibility(self):
        name = str(uuid.uuid4()) + ".mp4"
        original = bytes(range(256)) * 20
        self.assertEqual(self.request("/assets/" + name, method="PUT", raw=original)[0], 200)
        self.assertEqual(self.request("/assets/" + name, user=1)[0], 403)
        post_id = str(uuid.uuid4())
        post = {"id": post_id, "authorID": self.users[0], "caption": "Public", "options": {"onlyMe": False}, "media": [{"file": name}]}
        self.assertEqual(self.push(self.record("post", post_id, post))[0], 200)
        self.assertEqual(self.request("/assets/" + name, user=1, method="HEAD")[0], 200)
        self.assertEqual(self.request("/assets/" + name, user=1)[1], original)

    def test_private_bookmarks_are_redacted(self):
        post_id = str(uuid.uuid4())
        post = {"id": post_id, "authorID": self.users[0], "options": {"onlyMe": False}}
        self.assertEqual(self.push(self.record("post", post_id, post), self.record("reaction", post_id, {"postID": post_id, "liked": True, "bookmarked": True}))[0], 200)
        records = self.request("/sync", user=1)[1]["records"]
        reactions = [record for record in records if record["resource"] == "reaction"]
        self.assertEqual(len(reactions), 1)
        self.assertFalse(json.loads(base64.b64decode(reactions[0]["payload"]))["bookmarked"])

    def test_another_author_cannot_pin_comments(self):
        post_id = str(uuid.uuid4())
        self.push(self.record("post", post_id, {"id": post_id, "authorID": self.users[0], "options": {"onlyMe": False}}))
        pin = self.record("commentPin", post_id, {"postID": post_id}, user=1)
        self.assertEqual(self.push(pin, user=1)[0], 403)

    def test_message_tombstone_reaches_only_participants(self):
        self.request("/users/" + self.users[1] + "/follow", method="PUT")
        message_id = str(uuid.uuid4())
        value = {"id": message_id, "senderID": self.users[0], "recipientID": self.users[1], "text": "Transient", "createdAt": 0}
        self.assertEqual(self.push(self.record("message", message_id, value))[0], 200)
        self.assertTrue(any(record["resource"] == "message" for record in self.request("/sync", user=1)[1]["records"]))
        self.assertEqual(self.push(self.record("message", message_id, {"deleted": True}))[0], 200)
        messages = [record for record in self.request("/sync", user=1)[1]["records"] if record["resource"] == "message"]
        self.assertEqual(len(messages), 1)
        self.assertTrue(json.loads(base64.b64decode(messages[0]["payload"]))["deleted"])
        self.assertFalse(any(record["resource"] == "message" for record in self.request("/sync", user=2)[1]["records"]))

    def test_blocked_recipient_cannot_receive_new_rest_messages(self):
        self.request("/users/" + self.users[1] + "/follow", method="PUT")
        preferences = {"preferences": {"blocked": [self.users[0]], "messagePermission": "everyone"}}
        self.assertEqual(self.push(self.record("preferences", self.users[1], preferences, user=1), user=1)[0], 200)
        self.assertEqual(self.request("/conversations/" + self.users[1] + "/messages", method="POST", body={"id": str(uuid.uuid4()), "text": "Blocked"})[0], 403)

    def test_another_author_cannot_replace_existing_post_id(self):
        post_id = str(uuid.uuid4())
        self.assertEqual(self.push(self.record("post", post_id, {"id": post_id, "authorID": self.users[0]}))[0], 200)
        self.assertEqual(self.push(self.record("post", post_id, {"id": post_id, "authorID": self.users[1]}, user=1), user=1)[0], 409)


if __name__ == "__main__":
    unittest.main()
