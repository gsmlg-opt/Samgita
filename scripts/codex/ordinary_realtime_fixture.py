#!/usr/bin/env python3
"""Finite loopback WebSocket peer for an ordinary native realtime start/stop.

Only functional paths, bounded fixture model bodies and WebSocket messages enter
the journal. This peer never implements app-server requests or journals headers.
Only instructions/delegation scenarios serve bounded inert model outputs.
"""
import argparse
import base64
from email.parser import BytesParser
from email.policy import default
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import socketserver
import struct
import sys
import threading
import time
import traceback


MODEL = "owned-v432-realtime-model"
PROMPT = "Owned local realtime start"
ACK = {"type": "session.updated", "session": {
    "id": "owned-v432-peer-session", "instructions": PROMPT}}
TRANSCRIPT = [
    {"type": "response.output_text.delta", "delta": "Owned realtime λ "},
    {"type": "response.output_text.delta", "delta": "draft."},
    {"type": "response.output_text.done", "text": "Owned realtime λ revised final."},
]
SERVICE_ERROR = {
    "type": "error",
    "error": {
        "type": "server_error", "code": "server_error",
        "message": "Owned local realtime service unavailable λ", "param": None,
    },
}
ITEM_AUDIO = [
    {"type": "conversation.item.added", "item": {
        "id": "owned-item-audio-backend-item", "type": "message", "role": "user",
        "content": [{"type": "input_text", "text": "Owned inert realtime item λ"}],
    }},
    {"type": "response.output_audio.delta", "delta": "AADoAxj8/38=",
     "sample_rate": 16000, "channels": 2, "samples_per_channel": 2,
     "item_id": "owned-item-audio-output-item"},
]
INGRESS = [
    {"type": "conversation.item.create", "item": {
        "type": "message", "role": "developer",
        "content": [{"type": "input_text", "text": "Owned developer input λ\nkeep whitespace "}],
    }},
    {"type": "conversation.item.create", "item": {
        "type": "message", "role": "user",
        "content": [{"type": "input_text", "text": "[USER] Owned user input 🙂\nsecond line"}],
    }},
    {"type": "conversation.item.create", "item": {
        "type": "message", "role": "assistant",
        "content": [{"type": "output_text", "text": "Owned assistant input α\r\nfinal "}],
    }},
    {"type": "input_audio_buffer.append", "audio": "AADoAxj8/38="},
]
SPEECH = [
    {"type": "conversation.item.create", "item": {
        "type": "message", "role": "user",
        "content": [{"type": "input_text",
                     "text": "[BACKEND] Owned ordinary speech λ🙂\nkeep trailing space "}],
    }},
    {"type": "response.create"},
]
INITIAL_ACK = {"type": "session.started", "session": {
    "id": "owned-initial-peer-session", "instructions": PROMPT}}
INITIAL_SESSION = {
    "instructions": PROMPT,
    "audio": {"output": {"voice": "cove"}},
    "delegation": {"type": "client", "ack_filler": False},
    "initial_items": [
        {"type": "message", "role": "developer",
         "content": [{"type": "input_text", "text": "Owned initial developer λ\nkeep trailing space "}]},
        {"type": "message", "role": "user",
         "content": [{"type": "input_text", "text": "Owned initial user 🙂\nsecond line"}]},
        {"type": "message", "role": "assistant",
         "content": [{"type": "output_text", "text": "Owned initial assistant α\r\nfinal "}]},
    ],
}
SDP_OFFER = "v=0\r\ns=Owned ordinary offer λ\r\na=inactive\r\n"
SDP_ANSWER = "v=0\r\ns=Owned ordinary answer 🙂\r\na=inactive\r\n"
SDP_CALL_ID = "rtc_owned_ordinary_sdp"
SDP_CALL_PATH = "/v1/realtime/calls?intent=quicksilver&architecture=avas"
SDP_SIDEBAND_PATH = f"/v1/realtime?intent=quicksilver&call_id={SDP_CALL_ID}"
MAX_FRAME = 65_536
MAX_FRAMES = 32
MAX_JOURNAL = 2_097_152
MAX_HEADERS = 8192
INSTRUCTIONS_START = "Owned active context λ\nkeep trailing space "
INSTRUCTIONS_END = "Owned stopped context 🙂\nkeep trailing space "
INSTRUCTIONS_USERS = ["Owned active backing turn.", "Owned stopped backing turn."]
INSTRUCTIONS_ANSWERS = ["Owned active assistant result.", "Owned stopped assistant result."]
INSTRUCTIONS_FRAGMENTS = [
    f"<realtime_conversation>\n{INSTRUCTIONS_START}\n</realtime_conversation>",
    f"<realtime_conversation>\n{INSTRUCTIONS_END}\n</realtime_conversation>",
]
DELEGATION_INPUT = "<realtime_delegation>\n  <input>Owned bounded request λ</input>\n  <transcript_delta>user: Owned bounded request λ</transcript_delta>\n</realtime_delegation>"
DELEGATION_ANSWER = "Owned bounded assistant result 🙂"
DELEGATION_FRAME = {"type": "delegation.created", "item": {
    "type": "delegation", "target": "client", "id": "owned-handoff-1",
    "content": [{"type": "input_text", "text": "Owned bounded request λ"}]}}
DELEGATION_SESSION = {"instructions": PROMPT,
    "audio": {"output": {"voice": "cove"}}, "delegation": {"type": "client"}}
DELEGATION_ACK = {"type": "session.started", "session": {
    "id": "owned-v485-peer-session", "instructions": PROMPT}}
DELEGATION_OUTPUT = {"type": "session.context.append", "channel": "commentary",
    "content": [{"type": "input_text", "text": "Owned delegate result λ\n\nOwned bounded assistant result 🙂"}]}
DELEGATION_SCENARIOS = ("delegation", "delegation-status")
QUIET_REASONING = {"type": "reasoning", "id": "owned-v486-public-summary",
    "summary": [{"type": "summary_text", "text": "  Owned quiet progress λ  "}], "content": []}
QUIET_STATUS = {"type": "delegation.context.append", "delegation_item_id": "owned-handoff-1",
    "channel": "commentary", "content": [{"type": "input_text", "text": "[STATUS] Owned quiet progress λ"}]}


def delegation_outputs(scenario):
    return ([QUIET_STATUS, DELEGATION_OUTPUT] if scenario == "delegation-status"
            else [DELEGATION_OUTPUT])


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    assert len(encoded) <= MAX_JOURNAL, "Owned realtime journal overflow"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def sdp_session(with_model=False):
    session = {"type": "quicksilver", "instructions": PROMPT,
               "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000}},
                         "output": {"voice": "cove"}}}
    if with_model:
        session["model"] = MODEL
    return session


class PeerHandler(socketserver.BaseRequestHandler):
    def handle(self):
        fixture = self.server.fixture
        self.websocket = False
        self.request.settimeout(0.2)
        with fixture.lock:
            fixture.sockets.add(self.request)
        try:
            self.handle_request(fixture)
        except Exception as failure:
            if not fixture.stopping.is_set():
                # Fixed exception class and source line, never payload/headers.
                line = traceback.extract_tb(failure.__traceback__)[-1].lineno
                fixture.fail(f"{type(failure).__name__}:line{line}")
        finally:
            try:
                self.request.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.request.close()
            with fixture.lock:
                fixture.sockets.discard(self.request)
                if self.websocket:
                    fixture.state["activeConnections"] = 0
                fixture.save_locked()

    def read_exact(self, count, fixture, deadline):
        assert 0 <= count <= MAX_FRAME
        result = bytearray()
        while len(result) < count:
            if fixture.stopping.is_set():
                raise EOFError("Owned peer stopping")
            assert time.monotonic() < deadline, "Owned realtime socket deadline"
            try:
                chunk = self.request.recv(count - len(result))
            except socket.timeout:
                continue
            if not chunk:
                if not result:
                    return None
                raise EOFError("Owned incomplete frame")
            result.extend(chunk)
        return bytes(result)

    def handle_request(self, fixture):
        # Parse a bounded HTTP upgrade in memory; retain only method/path.
        header = bytearray()
        deadline = time.monotonic() + 5
        while not header.endswith(b"\r\n\r\n"):
            assert len(header) < MAX_HEADERS, "Owned HTTP header limit"
            byte = self.read_exact(1, fixture, deadline)
            if byte is None:
                raise EOFError("Owned incomplete HTTP request")
            header.extend(byte)
        lines = bytes(header).decode("iso-8859-1").split("\r\n")
        method, path, version = lines[0].split(" ")
        assert version == "HTTP/1.1"
        fields = {}
        for line in lines[1:]:
            if line:
                name, value = line.split(":", 1)
                fields[name.lower()] = value.strip()

        if (fixture.scenario == "instructions" and method == "POST"
                and path == "/v1/responses"):
            self.instructions_response(fixture, fields, deadline)
            return
        if (fixture.scenario in DELEGATION_SCENARIOS and method == "POST"
                and path == "/v1/responses"):
            self.delegation_response(fixture, fields, deadline)
            return

        if fixture.scenario == "sdp" and method == "POST" and path == SDP_CALL_PATH:
            self.create_sdp_call(fixture, fields, deadline)
            return

        if (fixture.scenario == "transcript" and method == "POST"
                and path == "/fixture/transcript"):
            assert fields.get("content-length") == "0"
            with fixture.lock:
                assert fixture.state["paths"] == [f"/v1/realtime?model={MODEL}"]
                assert len(fixture.state["messages"]) == 1
                assert fixture.state["sent"] == [ACK]
                assert fixture.state["activeConnections"] == 1
                assert fixture.state["controls"] == []
                fixture.state["controls"].append({
                    "method": "POST", "path": "/fixture/transcript", "bodyBytes": 0})
                fixture.save_locked()
            body = b'{"released":true}'
            self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                + f"Content-Length: {len(body)}\r\n".encode()
                + b"Connection: close\r\n\r\n" + body)
            fixture.release.set()
            return

        if (fixture.scenario == "service-error" and method == "POST"
                and path == "/fixture/service-error"):
            assert fields.get("content-length") == "0"
            with fixture.lock:
                assert fixture.state["paths"] == [f"/v1/realtime?model={MODEL}"]
                assert len(fixture.state["messages"]) == 1
                assert fixture.state["sent"] == [ACK]
                assert fixture.state["activeConnections"] == 1
                assert fixture.state["controls"] == []
                fixture.state["controls"].append({
                    "method": "POST", "path": "/fixture/service-error", "bodyBytes": 0})
                fixture.save_locked()
            body = b'{"released":true}'
            self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                + f"Content-Length: {len(body)}\r\n".encode()
                + b"Connection: close\r\n\r\n" + body)
            fixture.release.set()
            return

        if (fixture.scenario == "item-audio" and method == "POST"
                and path == "/fixture/item-audio"):
            assert fields.get("content-length") == "0"
            with fixture.lock:
                assert fixture.state["paths"] == [f"/v1/realtime?model={MODEL}"]
                assert len(fixture.state["messages"]) == 1
                assert fixture.state["sent"] == [ACK]
                assert fixture.state["activeConnections"] == 1
                assert fixture.state["controls"] == []
                fixture.state["controls"].append({
                    "method": "POST", "path": "/fixture/item-audio", "bodyBytes": 0})
                fixture.save_locked()
            body = b'{"released":true}'
            self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                + f"Content-Length: {len(body)}\r\n".encode()
                + b"Connection: close\r\n\r\n" + body)
            fixture.release.set()
            return

        expected_path = (SDP_SIDEBAND_PATH if fixture.scenario == "sdp"
                         else f"/v1/live?model={MODEL}" if fixture.scenario in ("initial-items", *DELEGATION_SCENARIOS)
                         else f"/v1/realtime?model={MODEL}")
        if method != "GET" or path != expected_path:
            with fixture.lock:
                if method == "POST" and path == "/v1/responses":
                    fixture.state["responsesRequests"] += 1
                fixture.state["otherHttp"].append({"method": method, "path": path})
                fixture.save_locked()
            self.request.sendall(b"HTTP/1.1 500 Unexpected fixture request\r\n"
                                 b"Content-Length: 0\r\nConnection: close\r\n\r\n")
            raise ValueError("Unexpected ordinary peer path")

        if fixture.scenario == "sdp":
            with fixture.lock:
                assert len(fixture.state["calls"]) == 1

        assert fields.get("upgrade", "").lower() == "websocket"
        assert "upgrade" in fields.get("connection", "").lower()
        key = fields["sec-websocket-key"]
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        self.request.sendall(b"HTTP/1.1 101 Switching Protocols\r\n"
                             b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                             b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        # No header value is retained by the fixture state or error reporting.
        del fields, header, lines, key, accept
        with fixture.lock:
            fixture.state["paths"].append(path)
            assert len(fixture.state["paths"]) == 1, "Extra owned realtime connection"
            fixture.state["activeConnections"] = 1
            self.websocket = True
            fixture.save_locked()

        deadline = time.monotonic() + 25
        while not fixture.stopping.is_set():
            first = self.read_exact(2, fixture, deadline)
            if first is None:
                if fixture.scenario in DELEGATION_SCENARIOS:
                    assert not fixture.stopping.is_set()
                    with fixture.lock:
                        assert fixture.state["responsesRequests"] == 1
                        assert fixture.state["delegationOutput"] == delegation_outputs(fixture.scenario)
                        assert fixture.state["transportEofCount"] == 0
                        fixture.state["transportEofCount"] = 1
                        fixture.save_locked()
                if fixture.scenario == "instructions":
                    # Observe native requested-stop EOF before fixture teardown.
                    assert not fixture.stopping.is_set()
                    with fixture.lock:
                        assert fixture.state["responsesRequests"] == 1
                        assert fixture.state["transportEofCount"] == 0
                        fixture.state["transportEofCount"] = 1
                        fixture.save_locked()
                if fixture.scenario == "initial-items":
                    # Stock app-server requested stop drops the native writer;
                    # it does not invoke RealtimeWebsocketWriter.close. Observe
                    # EOF here, before fixture teardown can close any socket.
                    assert not fixture.stopping.is_set()
                    with fixture.lock:
                        assert fixture.state["messages"] == [{"type": "session.update", "session": INITIAL_SESSION}]
                        assert fixture.state["sent"] == [INITIAL_ACK]
                        assert fixture.state["sessionClose"] == []
                        assert fixture.state["websocketCloseCount"] == 0
                        assert fixture.state["transportEofCount"] == 0
                        fixture.state["transportEofCount"] = 1
                        fixture.save_locked()
                return
            assert first[0] & 0x80 and not first[0] & 0x70, "Owned unfragmented frame required"
            opcode = first[0] & 0x0F
            assert first[1] & 0x80, "Owned client frame must be masked"
            size = first[1] & 0x7F
            if size == 126:
                size = struct.unpack("!H", self.read_exact(2, fixture, deadline))[0]
            elif size == 127:
                size = struct.unpack("!Q", self.read_exact(8, fixture, deadline))[0]
            assert size <= MAX_FRAME, "Owned WebSocket frame overflow"
            if opcode >= 8:
                assert size <= 125
            mask = self.read_exact(4, fixture, deadline)
            payload = self.read_exact(size, fixture, deadline)
            assert payload is not None
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            fixture.record_frame()
            if opcode == 8:
                if fixture.scenario == "initial-items":
                    with fixture.lock:
                        assert fixture.state["sessionClose"] == [{"type": "session.close"}]
                        assert fixture.state["websocketCloseCount"] == 0
                        fixture.state["websocketCloseCount"] = 1
                        fixture.save_locked()
                self.send_frame(fixture, 8, payload)
                return
            if opcode == 9:
                self.send_frame(fixture, 10, payload)
                continue
            if opcode == 10:
                continue
            assert opcode == 1, "Unexpected owned realtime frame opcode"
            message = json.loads(payload.decode("utf-8"))
            if fixture.scenario in DELEGATION_SCENARIOS and message.get("type") != "session.update":
                with fixture.lock:
                    expected = delegation_outputs(fixture.scenario)
                    index = len(fixture.state["delegationOutput"])
                    assert index < len(expected) and message == expected[index]
                    fixture.state["delegationOutput"].append(message)
                    fixture.save_locked()
                if fixture.scenario == "delegation-status" and message == QUIET_STATUS:
                    fixture.release.set()
                continue
            if fixture.scenario == "ingress" and message.get("type") != "session.update":
                with fixture.lock:
                    assert len(fixture.state["messages"]) == 1
                    assert fixture.state["sent"] == [ACK]
                    index = len(fixture.state["ingress"])
                    assert index < len(INGRESS), "Extra owned realtime ingress message"
                    assert message == INGRESS[index], "Unexpected owned realtime ingress message"
                    fixture.state["ingress"].append(message)
                    fixture.save_locked()
                continue
            if fixture.scenario == "speech" and message.get("type") != "session.update":
                with fixture.lock:
                    assert len(fixture.state["messages"]) == 1
                    assert fixture.state["sent"] == [ACK]
                    index = len(fixture.state["speech"])
                    assert index < len(SPEECH), "Extra owned realtime speech message"
                    assert message == SPEECH[index], "Unexpected owned realtime speech message"
                    fixture.state["speech"].append(message)
                    fixture.save_locked()
                continue
            if fixture.scenario == "initial-items" and message.get("type") != "session.update":
                with fixture.lock:
                    assert message == {"type": "session.close"}
                    assert fixture.state["messages"] == [{"type": "session.update", "session": INITIAL_SESSION}]
                    assert fixture.state["sent"] == [INITIAL_ACK]
                    assert fixture.state["sessionClose"] == []
                    assert fixture.state["websocketCloseCount"] == 0
                    fixture.state["sessionClose"].append(message)
                    fixture.save_locked()
                continue
            assert isinstance(message, dict) and message.get("type") == "session.update"
            if fixture.scenario == "sdp":
                assert message == {"type": "session.update", "session": sdp_session()}
            elif fixture.scenario == "initial-items":
                assert message == {"type": "session.update", "session": INITIAL_SESSION}
            elif fixture.scenario in DELEGATION_SCENARIOS:
                assert message == {"type": "session.update", "session": DELEGATION_SESSION}
            else:
                assert message["session"]["type"] == "realtime"
                assert message["session"]["instructions"] == PROMPT
                expected_modality = "audio" if fixture.scenario in ("item-audio", "speech") else "text"
                assert message["session"]["output_modalities"] == [expected_modality]
                if fixture.scenario == "speech":
                    assert message["session"]["audio"]["output"]["voice"] == "marin"
            with fixture.lock:
                fixture.state["messages"].append(message)
                assert len(fixture.state["messages"]) == 1, "Extra owned session.update"
                fixture.save_locked()
            ack = (INITIAL_ACK if fixture.scenario == "initial-items" else
                   DELEGATION_ACK if fixture.scenario in DELEGATION_SCENARIOS else ACK)
            self.send_frame(fixture, 1, json.dumps(ack, separators=(",", ":")).encode())
            with fixture.lock:
                fixture.state["sent"].append(ack)
                fixture.save_locked()
            if fixture.scenario in DELEGATION_SCENARIOS:
                self.send_frame(fixture, 1,
                    json.dumps(DELEGATION_FRAME, ensure_ascii=False, separators=(",", ":")).encode())
                with fixture.lock:
                    fixture.state["sent"].append(DELEGATION_FRAME)
                    fixture.save_locked()
            if fixture.scenario == "transcript":
                while not fixture.release.is_set():
                    if fixture.stopping.is_set():
                        return
                    remaining = deadline - time.monotonic()
                    assert remaining > 0, "Owned transcript release deadline"
                    fixture.release.wait(min(0.2, remaining))
                if fixture.stopping.is_set():
                    return
                for entry in TRANSCRIPT:
                    self.send_frame(fixture, 1,
                        json.dumps(entry, ensure_ascii=False, separators=(",", ":")).encode())
                    with fixture.lock:
                        fixture.state["sent"].append(entry)
                        fixture.save_locked()

            if fixture.scenario == "service-error":
                while not fixture.release.is_set():
                    if fixture.stopping.is_set():
                        return
                    remaining = deadline - time.monotonic()
                    assert remaining > 0, "Owned service-error release deadline"
                    fixture.release.wait(min(0.2, remaining))
                if fixture.stopping.is_set():
                    return
                self.send_frame(fixture, 1,
                    json.dumps(SERVICE_ERROR, ensure_ascii=False,
                               separators=(",", ":")).encode())
                with fixture.lock:
                    fixture.state["sent"].append(SERVICE_ERROR)
                    fixture.save_locked()

            if fixture.scenario == "item-audio":
                while not fixture.release.is_set():
                    if fixture.stopping.is_set():
                        return
                    remaining = deadline - time.monotonic()
                    assert remaining > 0, "Owned item-audio release deadline"
                    fixture.release.wait(min(0.2, remaining))
                if fixture.stopping.is_set():
                    return
                for entry in ITEM_AUDIO:
                    self.send_frame(fixture, 1,
                        json.dumps(entry, ensure_ascii=False, separators=(",", ":")).encode())
                    with fixture.lock:
                        fixture.state["sent"].append(entry)
                        fixture.save_locked()

    def delegation_response(self, fixture, fields, deadline):
        status = fixture.scenario == "delegation-status"
        size = int(fields.get("content-length", "0"))
        assert 0 < size <= MAX_FRAME, "Owned delegation request body bound"
        raw = self.read_exact(size, fixture, deadline)
        assert raw is not None and len(raw) == size
        request = json.loads(raw)
        assert request["model"] == "mock-model"
        assert isinstance(request["input"], list) and len(request["input"]) <= 64
        user_texts = [part.get("text") for item in request["input"]
                      if item.get("role") == "user" for part in item.get("content", [])
                      if part.get("type") == "input_text"]
        assert user_texts.count(DELEGATION_INPUT) == 1
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert isinstance(metadata["thread_id"], str) and metadata["thread_id"]
        assert isinstance(metadata["turn_id"], str) and metadata["turn_id"]
        item = {"type": "message", "role": "assistant", "id": "owned-v485-message",
                "content": [{"type": "output_text", "text": DELEGATION_ANSWER}]}
        events = [
            {"type": "response.created", "response": {"id": "owned-v485-response"}},
            {"type": "response.output_item.done", "item": item},
            {"type": "response.completed", "response": {"id": "owned-v485-response", "usage": {
                "input_tokens": 0, "input_tokens_details": None,
                "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0}}},
        ]
        if status:
            events.insert(1, {"type": "response.output_item.done", "item": QUIET_REASONING})
        with fixture.lock:
            assert fixture.state["responsesRequests"] == 0
            assert fixture.state["activeConnections"] == 1
            assert fixture.state["paths"] == [f"/v1/live?model={MODEL}"]
            assert fixture.state["messages"] == [{"type": "session.update", "session": DELEGATION_SESSION}]
            # The provider can race the WebSocket sender's post-send journal.
            # Its original wrapped input independently proves delegation receipt.
            assert fixture.state["sent"][:1] == [DELEGATION_ACK]
            fixture.state["responsesRequests"] = 1
            fixture.state["delegationResponses"].append({"bodyBytes": size,
                "bodyBase64": base64.b64encode(raw).decode(),
                "bodySha256": hashlib.sha256(raw).hexdigest(),
                "input": request["input"], "turnMetadata": metadata, "events": events})
            fixture.save_locked()
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        assert len(body) <= MAX_FRAME
        header = (b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
            + f"Content-Length: {len(body)}\r\n".encode() + b"Connection: close\r\n\r\n")
        if not status:
            self.request.sendall(header + body)
            return
        prefix = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                         for event in events[:2]).encode()
        suffix = body[len(prefix):]
        assert prefix + suffix == body and suffix
        with fixture.lock:
            entry = fixture.state["delegationResponses"][0]
            entry["sseSegmentsBase64"] = [base64.b64encode(segment).decode()
                                           for segment in (prefix, suffix)]
            entry["quietStatusBarrier"] = False
            fixture.save_locked()
        self.request.sendall(header + prefix)
        # Keep the handoff active until its actual quiet status traverses WS.
        # Existing close() sets stopping/release, so failed tests cannot strand
        # this provider handler while the existing cleanup joins it.
        remaining = deadline - time.monotonic()
        assert remaining > 0 and fixture.release.wait(remaining), "Owned quiet status deadline"
        assert not fixture.stopping.is_set(), "Owned quiet status peer stopping"
        with fixture.lock:
            assert fixture.state["delegationOutput"] == [QUIET_STATUS]
            entry["quietStatusBarrier"] = True
            fixture.save_locked()
        self.request.sendall(suffix)

    def instructions_response(self, fixture, fields, deadline):
        size = int(fields.get("content-length", "0"))
        assert 0 < size <= MAX_FRAME, "Owned instruction request body bound"
        raw = self.read_exact(size, fixture, deadline)
        assert raw is not None and len(raw) == size
        request = json.loads(raw)
        assert request["model"] == "mock-model"
        assert isinstance(request["input"], list) and len(request["input"]) <= 64
        # Test only the realtime fragments and inert fixture conversation, not
        # unrelated native developer context carried in the same model input.
        texts = [(item.get("role"), content.get("type"), content.get("text"))
                 for item in request["input"]
                 for content in item.get("content", [])]
        developer = [text for role, kind, text in texts
                     if role == "developer" and kind == "input_text"]
        users = [text for role, kind, text in texts
                 if role == "user" and kind == "input_text"]
        assistants = [text for role, kind, text in texts
                      if role == "assistant" and kind == "output_text"]
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert isinstance(metadata["thread_id"], str) and metadata["thread_id"]
        assert isinstance(metadata["turn_id"], str) and metadata["turn_id"]
        with fixture.lock:
            index = fixture.state["responsesRequests"]
            assert index < 2, "Extra owned instruction Responses request"
            assert fixture.state["paths"] == [f"/v1/realtime?model={MODEL}"]
            assert len(fixture.state["messages"]) == 1
            assert fixture.state["sent"] == [ACK]
            assert fixture.state["activeConnections"] == (1 if index == 0 else 0)
            assert fixture.state["transportEofCount"] == index
            assert developer.count(INSTRUCTIONS_FRAGMENTS[0]) == 1
            assert developer.count(INSTRUCTIONS_FRAGMENTS[1]) == index
            assert users.count(INSTRUCTIONS_USERS[0]) == 1
            assert users.count(INSTRUCTIONS_USERS[1]) == index
            assert assistants.count(INSTRUCTIONS_ANSWERS[0]) == index
            assert assistants.count(INSTRUCTIONS_ANSWERS[1]) == 0
            fixture.state["responsesRequests"] += 1
            identity = f"owned-instructions-response-{index + 1}"
            item = {"type": "message", "role": "assistant",
                    "id": f"owned-instructions-message-{index + 1}",
                    "content": [{"type": "output_text", "text": INSTRUCTIONS_ANSWERS[index]}]}
            events = [
                {"type": "response.created", "response": {"id": identity}},
                {"type": "response.output_item.done", "item": item},
                {"type": "response.completed", "response": {"id": identity, "usage": {
                    "input_tokens": 0, "input_tokens_details": None,
                    "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0,
                }}},
            ]
            fixture.state["instructionResponses"].append({
                "index": index + 1, "bodyBytes": size,
                "bodyBase64": base64.b64encode(raw).decode(),
                "bodySha256": hashlib.sha256(raw).hexdigest(),
                "input": request["input"], "turnMetadata": metadata,
                "activeConnections": fixture.state["activeConnections"],
                "events": events})
            fixture.save_locked()
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        assert len(body) <= MAX_FRAME
        self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
            + f"Content-Length: {len(body)}\r\n".encode()
            + b"Connection: close\r\n\r\n" + body)

    def create_sdp_call(self, fixture, fields, deadline):
        size = int(fields.get("content-length", "0"))
        assert 0 < size <= 16384, "Owned call body bound"
        kind = fields.get("content-type")
        assert kind == "multipart/form-data; boundary=codex-realtime-call-boundary"
        body = self.read_exact(size, fixture, deadline)
        assert body is not None
        mime = BytesParser(policy=default).parsebytes(
            f"Content-Type: {kind}\r\nMIME-Version: 1.0\r\n\r\n".encode() + body)
        assert mime.is_multipart() and not mime.defects
        parts = list(mime.iter_parts())
        assert len(parts) == 2
        assert [part.get_param("name", header="content-disposition") for part in parts] == ["sdp", "session"]
        assert [part.get_content_type() for part in parts] == ["application/sdp", "application/json"]
        assert parts[0].get_payload(decode=True) == SDP_OFFER.encode()
        session = json.loads(parts[1].get_payload(decode=True))
        assert session == sdp_session(with_model=True)
        with fixture.lock:
            assert fixture.state["calls"] == [] and fixture.state["paths"] == []
            fixture.state["calls"].append({
                "method": "POST", "path": SDP_CALL_PATH,
                "bodyBytes": len(body), "bodyBase64": base64.b64encode(body).decode(),
                "offer": SDP_OFFER, "session": session,
                "answer": SDP_ANSWER, "location": f"/v1/realtime/calls/{SDP_CALL_ID}"})
            fixture.save_locked()
        answer = SDP_ANSWER.encode()
        self.request.sendall(b"HTTP/1.1 201 Created\r\nContent-Type: application/sdp\r\n"
            + f"Location: /v1/realtime/calls/{SDP_CALL_ID}\r\n".encode()
            + f"Content-Length: {len(answer)}\r\n".encode()
            + b"Connection: close\r\n\r\n" + answer)

    def send_frame(self, fixture, opcode, payload):
        assert len(payload) <= MAX_FRAME
        fixture.record_frame()
        if len(payload) < 126:
            header = bytes([0x80 | opcode, len(payload)])
        elif len(payload) <= 65_535:
            header = bytes([0x80 | opcode, 126]) + struct.pack("!H", len(payload))
        else:
            header = bytes([0x80 | opcode, 127]) + struct.pack("!Q", len(payload))
        self.request.sendall(header + payload)


class PeerServer(socketserver.TCPServer):
    allow_reuse_address = False

    def process_request(self, request, address):
        fixture = self.fixture
        with fixture.lock:
            full = len(fixture.handlers) >= 2
            fixture.state["requestCount"] += 1
            full = full or fixture.state["requestCount"] > 4
            fixture.save_locked()
            if not full and not fixture.stopping.is_set():
                worker = threading.Thread(target=self.run_request,
                    args=(request, address), name="owned-realtime-handler", daemon=False)
                fixture.handlers.add(worker)
            else:
                worker = None
        if worker is None:
            self.shutdown_request(request)
            if not fixture.stopping.is_set():
                fixture.fail("OwnedHandlerLimit")
        else:
            worker.start()

    def run_request(self, request, address):
        try:
            self.finish_request(request, address)
        except Exception as failure:
            if not self.fixture.stopping.is_set():
                self.fixture.fail(type(failure).__name__)
        finally:
            self.shutdown_request(request)
            with self.fixture.lock:
                self.fixture.handlers.discard(threading.current_thread())


class OrdinaryRealtimePeer:
    def __init__(self, root, scenario="start-stop"):
        self.root = root
        self.scenario = scenario
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        self.release = threading.Event()
        self.sockets = set()
        self.handlers = set()
        self.state = {"paths": [], "messages": [], "sent": [], "frameCount": 0,
                      "responsesRequests": 0, "otherHttp": [],
                      "activeConnections": 0, "requestCount": 0, "controls": [], "errors": []}
        if scenario == "sdp":
            self.state["calls"] = []
        if scenario == "ingress":
            self.state["ingress"] = []
        if scenario == "speech":
            self.state["speech"] = []
        if scenario == "instructions":
            self.state["instructionResponses"] = []
            self.state["transportEofCount"] = 0
        if scenario in DELEGATION_SCENARIOS:
            self.state["delegationResponses"] = []
            self.state["delegationOutput"] = []
            self.state["transportEofCount"] = 0
        if scenario == "initial-items":
            self.state["sessionClose"] = []
            self.state["websocketCloseCount"] = 0
            self.state["transportEofCount"] = 0
        self.server = PeerServer(("127.0.0.1", 0), PeerHandler)
        self.server.fixture = self
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.05),
            name="owned-ordinary-realtime", daemon=False)
        with self.lock:
            self.save_locked()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def save_locked(self):
        write_json(self.root / "peer.json", self.state)

    def record_frame(self):
        with self.lock:
            self.state["frameCount"] += 1
            assert self.state["frameCount"] <= MAX_FRAMES, "Owned WebSocket frame count overflow"
            self.save_locked()

    def fail(self, kind):
        with self.lock:
            assert len(self.state["errors"]) < 8
            self.state["errors"].append(kind)
            self.save_locked()

    def config(self):
        sdp_config = (f'experimental_realtime_webrtc_call_base_url = "{self.url}/v1"\n'
                      '[realtime]\ntype = "conversational"\n' if self.scenario == "sdp" else "")
        initial_config = ('[realtime]\nversion = "v3"\ntype = "conversational"\n'
                          if self.scenario in ("initial-items", *DELEGATION_SCENARIOS) else "")
        catalog = self.root / "codex/models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned ordinary realtime fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned ordinary realtime instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        (self.root / "codex/config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
check_for_update_on_startup = false
allow_login_shell = false
web_search = "disabled"
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
experimental_realtime_ws_base_url = "{self.url}/v1"
experimental_realtime_ws_model = "{MODEL}"
experimental_realtime_ws_backend_prompt = ""
experimental_realtime_ws_startup_context = ""
{sdp_config}{initial_config}[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[memories]
generate_memories = false
use_memories = false
[features]
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
shell_snapshot = false
memories = false
hooks = false
realtime_conversation = true
[model_providers.fixture]
name = "Owned ordinary realtime provider"
base_url = "{self.url}/v1"
wire_api = "responses"
env_key = "SAMGITA_ORDINARY_REALTIME_FIXTURE_KEY"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')

    def close(self):
        self.stopping.set()
        self.release.set()
        # Close sockets before joining bounded handlers. The second slot lets an
        # unintended Responses request be observed while the WS is still open.
        with self.lock:
            sockets = list(self.sockets)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        if self.thread.ident is not None:
            self.server.shutdown()
        with self.lock:
            sockets = list(self.sockets)
            handlers = list(self.handlers)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        for handler in handlers:
            handler.join(timeout=2)
            assert not handler.is_alive(), "Owned realtime handler did not stop"
        self.server.server_close()
        assert self.server.socket.fileno() == -1, "Owned realtime listener did not close"
        if self.thread.ident is not None:
            self.thread.join(timeout=2)
        assert not self.thread.is_alive(), "Owned realtime server thread did not stop"
        with self.lock:
            assert not self.sockets, "Owned realtime handler socket did not close"
            assert not self.handlers, "Owned realtime handler thread did not stop"
            self.save_locked()
        write_json(self.root / "peer-closed.json", {
            "activeSockets": len(self.sockets), "handlerThreads": len(self.handlers),
            "threadAlive": self.thread.is_alive(),
            "serverClosed": self.server.socket.fileno() == -1})


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--scenario", choices=["start-stop", "transcript", "service-error", "item-audio", "sdp", "ingress", "speech", "initial-items", "instructions", *DELEGATION_SCENARIOS],
                        default="start-stop")
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    peer = OrdinaryRealtimePeer(root, args.scenario)
    signal.signal(signal.SIGTERM, terminate)
    try:
        peer.config()
        peer.thread.start()
        print(json.dumps({"url": peer.url, "pid": os.getpid()}), flush=True)
        sys.stdin.buffer.read(1)
    finally:
        peer.close()


if __name__ == "__main__":
    main()
