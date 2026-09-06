#!/usr/bin/env python3
"""Minimal OpenAI-compatible server for developing HermesVoice without a backend.

Implements just enough of the API surface the app touches:

    GET  /health              -> {"status": "ok"}
    GET  /v1/models           -> one fake model
    POST /v1/chat/completions -> a canned reply, streamed as SSE

The reply is echoed back in whatever language the system prompt asks for, when
that language is one of the few canned below; otherwise it falls back to English.
That is enough to exercise the full voice loop, including a language switch.

Usage:
    python3 tools/mock-server.py [--port 8642] [--delay 0.04]

Then point HermesVoice at http://localhost:8642 with any non-empty API key.

Standard library only — no pip install required.
"""

from __future__ import annotations

import argparse
import json
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Canned replies keyed by the English language name the app injects into the
# system prompt ("Always reply in Spanish, ...").
REPLIES: dict[str, str] = {
    "English": (
        "I am a mock Hermes server running on your machine. "
        "Nothing here reaches the network. Ask me anything and I will keep "
        "answering with this same friendly placeholder."
    ),
    "Spanish": (
        "Soy un servidor Hermes simulado corriendo en tu maquina. "
        "Nada de esto sale a la red. Preguntame lo que quieras y te seguire "
        "respondiendo con este mismo texto de prueba."
    ),
    "French": (
        "Je suis un serveur Hermes simule qui tourne sur votre machine. "
        "Rien ne quitte le reseau local. Posez-moi une question et je "
        "continuerai a repondre avec ce meme texte."
    ),
    "German": (
        "Ich bin ein simulierter Hermes-Server auf deinem Rechner. "
        "Nichts davon verlaesst das Netzwerk. Frag mich etwas und ich "
        "antworte weiterhin mit diesem Platzhaltertext."
    ),
    "Portuguese": (
        "Sou um servidor Hermes simulado rodando na sua maquina. "
        "Nada disso vai para a rede. Pergunte o que quiser e eu vou "
        "continuar respondendo com este mesmo texto."
    ),
    "Japanese": (
        "これはあなたのマシンで動作しているモックのHermesサーバーです。"
        "通信は外部に出ません。何でも聞いてください。"
    ),
}

LANGUAGE_DIRECTIVE = re.compile(r"Always reply in ([A-Za-z ]+?),")


def pick_reply(messages: list[dict]) -> str:
    """Chooses a canned reply matching the language the system prompt requests."""
    for message in messages:
        if message.get("role") != "system":
            continue
        match = LANGUAGE_DIRECTIVE.search(message.get("content", ""))
        if match:
            return REPLIES.get(match.group(1).strip(), REPLIES["English"])
    return REPLIES["English"]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    token_delay = 0.04

    # Keep the console readable; the app is chatty.
    def log_message(self, fmt: str, *args) -> None:
        print(f"  {self.command} {self.path}")

    # MARK: helpers

    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_sse_chunk(self, data: dict) -> None:
        self.wfile.write(f"data: {json.dumps(data)}\n\n".encode())
        self.wfile.flush()

    # MARK: routes

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self.path == "/health":
            self._send_json({"status": "ok"})
        elif self.path == "/v1/models":
            self._send_json(
                {
                    "object": "list",
                    "data": [{"id": "hermes-agent", "object": "model", "owned_by": "mock"}],
                }
            )
        else:
            self._send_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self.path != "/v1/chat/completions":
            self._send_json({"error": "not found"}, status=404)
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send_json({"error": "invalid JSON"}, status=400)
            return

        messages = payload.get("messages", [])
        reply = pick_reply(messages)
        user_turn = next(
            (m.get("content", "") for m in reversed(messages) if m.get("role") == "user"),
            "",
        )
        if user_turn:
            print(f'  user: "{user_turn}"')

        if not payload.get("stream"):
            self._send_json(
                {
                    "id": "chatcmpl-mock",
                    "object": "chat.completion",
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": reply},
                            "finish_reason": "stop",
                        }
                    ],
                }
            )
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        # The role-only opening chunk real servers send first.
        self._send_sse_chunk(
            {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
            }
        )

        try:
            for index, word in enumerate(reply.split(" ")):
                token = word if index == 0 else " " + word
                self._send_sse_chunk(
                    {
                        "id": "chatcmpl-mock",
                        "object": "chat.completion.chunk",
                        "choices": [
                            {"index": 0, "delta": {"content": token}, "finish_reason": None}
                        ],
                    }
                )
                time.sleep(self.token_delay)

            self._send_sse_chunk(
                {
                    "id": "chatcmpl-mock",
                    "object": "chat.completion.chunk",
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                }
            )
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            # The app cancelled mid-stream — an interruption. Expected.
            print("  (client disconnected)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8642)
    parser.add_argument(
        "--delay",
        type=float,
        default=0.04,
        help="seconds between streamed tokens (0 for instant)",
    )
    args = parser.parse_args()

    Handler.token_delay = args.delay
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Mock Hermes server on http://localhost:{args.port}")
    print("Point HermesVoice at that URL with any non-empty API key. Ctrl-C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()


if __name__ == "__main__":
    main()
