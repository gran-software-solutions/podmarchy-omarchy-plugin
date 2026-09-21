#!/usr/bin/env python3
"""Tiny Podcast Index mock for testing podmarchy-api without network calls."""
import http.server
import json
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9876

FEEDS = [
    {
        "id": 123,
        "title": "Test & Show",
        "author": "Author",
        "description": "<p>Hello world</p>",
        "url": "https://example.com/feed",
        "categories": {"1": "Tech"},
        "episodeCount": 5,
        "newestItemPublishTime": 1700000000,
    }
]

ITEMS = [
    {
        "id": 456,
        "feedId": 123,
        "title": "Episode one",
        "description": "<p>First episode</p>",
        "datePublished": 1700000000,
        "duration": 3600,
        "enclosureUrl": "https://example.com/ep1.mp3",
        "enclosureType": "audio/mpeg",
        "image": "https://example.com/cover.jpg",
    }
]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/search/byterm"):
            body = json.dumps({"feeds": FEEDS})
        elif self.path.startswith("/podcasts/trending"):
            body = json.dumps({"feeds": FEEDS})
        elif self.path.startswith("/episodes/byfeedid"):
            body = json.dumps({"items": ITEMS})
        else:
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, *args):
        pass

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"Mock Podcast Index on 127.0.0.1:{PORT}", file=sys.stderr)
        httpd.serve_forever()
