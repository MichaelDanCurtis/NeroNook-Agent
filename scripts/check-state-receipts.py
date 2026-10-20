#!/usr/bin/env python3
"""Accountless source-process check for permitted state receipt identity/expiry."""
import json
import os
import selectors
import subprocess
import sys
import time
import uuid

binary = sys.argv[1]
session = str(uuid.uuid4())
address = {"plugin": "example.provider", "name": "desk_status"}
entry = {"address": address, "channel": {"id": "desk_status",
    "title": "Desk status", "kind": "state",
    "schema": {"fields": [{"name": "volume", "kind": "number", "required": True,
                           "minimum": 0, "maximum": 1}]}}}
process = subprocess.Popen([binary, "--neronook-plugin", "--protocol-test"],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
buffer = b""
messages = []


def send(kind, **fields):
    message = {"type": kind, "apiVersion": 1,
               "pluginID": "cafe.nero.plugin.agent", "session": session,
               "sequence": 0, **fields}
    process.stdin.write((json.dumps(message) + "\n").encode())
    process.stdin.flush()


def pump(predicate, timeout=8):
    global buffer
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError("Agent process exited")
        for key, _ in selector.select(0.1):
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                raise AssertionError("Agent process closed output")
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                item = json.loads(line)
                assert item["session"].lower() == session
                messages.append(item)
        if predicate():
            return
    raise AssertionError("Timed out waiting for Agent state")


def context():
    snapshots = [item["snapshot"] for item in messages if item["type"] == "snapshot"]
    if not snapshots:
        return ""
    panels = snapshots[-1]["panels"]
    section = next((panel for panel in panels if panel["id"] == "context"), None)
    return "" if section is None else json.dumps(section.get("sections", []))


def catalog(entries):
    send("bus", bus={"operation": "catalog", "requestID": str(uuid.uuid4()),
                     "catalog": entries, "complete": True})


def event(event_id, volume, lifetime):
    send("bus", bus={"operation": "event", "requestID": event_id,
                     "address": address, "values": {"volume": volume},
                     "lifetime": lifetime})


try:
    send("hello", features=["panels-v1", "actions-v1", "forms-v1"])
    pump(lambda: any(item["type"] == "snapshot" for item in messages))
    catalog([entry])
    pump(lambda: any(item.get("bus", {}).get("operation") == "subscribe"
                     and item["bus"].get("address") == address for item in messages))
    first_id = str(uuid.uuid4())
    event(first_id, 0.4, 1)
    pump(lambda: "volume: 0.4" in context())
    event(first_id, 0.4, 30)  # host replay cannot renew the first observation
    pump(lambda: "No module context" in context(), timeout=5)
    second_id = str(uuid.uuid4())
    event(second_id, 0.8, 30)
    pump(lambda: "volume: 0.8" in context())
    prior_subscribes = sum(item.get("bus", {}).get("operation") == "subscribe"
                           for item in messages)
    catalog([entry])  # identical entry can follow a provider reconnect
    pump(lambda: "No module context" in context() and
         sum(item.get("bus", {}).get("operation") == "subscribe"
             for item in messages) > prior_subscribes)
    event(second_id, 0.8, 20)  # retained state in the new local catalog epoch
    pump(lambda: "volume: 0.8" in context())
    catalog([])
    pump(lambda: "No module context" in context())
    process.stdin.close()
    process.stdin = None
    process.communicate(timeout=3)  # Drain final bounded shutdown snapshots.
    assert process.returncode == 0
    print("PASS: subscribe, typed update, replay expiry, identical-catalog reset, revocation, clean EOF; synthetic accountless process only")
finally:
    selector.close()
    if process.poll() is None:
        process.kill()
        process.wait()
