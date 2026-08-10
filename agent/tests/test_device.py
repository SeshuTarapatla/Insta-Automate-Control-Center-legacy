"""Device control (CP 4.5) — GET /api/device and POST /api/device/scrcpy/
{start|stop}, all against a monkeypatched `ia_agent.integrations.wsl_bridge`
and `ia_agent.window` (never the real wsl-bridge or a real scrcpy window).
The retry-loop around the snap-after-start is the one piece of real logic
here worth testing directly; `window.py`'s ctypes calls themselves are
verified live instead, in `check_device.py`, since there is nothing to unit
test in a raw Win32 call beyond "does it find the real window" — this file's
"snap" fakes are pure return-value stubs.

PLAN V2.13.1 (device identity) adds: `GET /api/device/adb-devices` and
`PATCH /api/device/pinned-serial`, both against `device_api._device_model`/
`_list_adb_devices` monkeypatched the same way `wsl_bridge` is above — real
`adbutils` needs a real adb server this environment doesn't have. The actual
caching logic (`device_settings.resolve_model`) is real code, exercised
directly with a fake `live_lookup`, never monkeypatched away.
"""
import asyncio
import sys
import tempfile
import threading
from pathlib import Path

import httpx
import uvicorn

import ia_agent.device_settings as device_settings
import ia_agent.integrations.wsl_bridge as wsl_bridge
import ia_agent.window as window

# Never the real device.json — a serial pinned or cached by this run must not
# leak into the real agent's own settings file.
device_settings.DEVICE_SETTINGS_PATH = Path(tempfile.mkdtemp(prefix="ia-agent-test-device-")) / "device.json"

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


# ------------------------------------------------------------------- fixtures

BRIDGE_UP = True
MIRRORING = False
START_RESULT = {"status": "started", "pid": 4242}
SNAP_SUCCEEDS_AFTER = 0  # number of failed attempts before snap succeeds
_snap_calls = []


async def fake_bridge_healthy():
    if not BRIDGE_UP:
        raise httpx.ConnectError("refused")
    return True


async def fake_scrcpy_status():
    return MIRRORING


async def fake_scrcpy_start(serial):
    return dict(START_RESULT)


async def fake_scrcpy_stop():
    return None


def fake_snap(pid, x=1, y=45):
    _snap_calls.append(pid)
    return len(_snap_calls) > SNAP_SUCCEEDS_AFTER


ADB_DEVICES = [{"serial": "159555486700071", "state": "device"}]
LIVE_MODEL = "Pixel 7"


def fake_device_model(serial):
    return LIVE_MODEL if serial == "159555486700071" else None


def fake_list_adb_devices():
    return list(ADB_DEVICES)


wsl_bridge.bridge_healthy = fake_bridge_healthy
wsl_bridge.scrcpy_status = fake_scrcpy_status
wsl_bridge.scrcpy_start = fake_scrcpy_start
wsl_bridge.scrcpy_stop = fake_scrcpy_stop
window.snap_to_known_position = fake_snap

import ia_agent.api.device as device_api  # noqa: E402

device_api._SNAP_INTERVAL = 0.01  # keep the retry loop fast in tests
# Real adbutils talks to a real adb server this test environment doesn't
# have — the caching logic itself (`device_settings.resolve_model`) is
# exercised directly further down, against a fake `live_lookup`, never here.
device_api._device_model = fake_device_model
device_api._list_adb_devices = fake_list_adb_devices


# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
PORT = 8794
app = app_module.create_app()
from ia_agent.vars import TOKEN_PATH  # noqa: E402

token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def main() -> int:
    global BRIDGE_UP, MIRRORING, SNAP_SUCCEEDS_AFTER
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
        for _ in range(50):
            try:
                await client.get("/api/health")
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        print("\n1. GET /api/device with ANDROID_SERIAL set, bridge up, not mirroring")
        device_api.ANDROID_SERIAL = "159555486700071"
        status = (await client.get("/api/device")).json()
        check("serial reported", status["serial"] == "159555486700071", str(status))
        check("bridge reachable", status["bridge_reachable"] is True, str(status))
        check("not mirroring", status["mirroring"] is False, str(status))

        print("\n2. GET /api/device when mirroring")
        MIRRORING = True
        status = (await client.get("/api/device")).json()
        check("mirroring true", status["mirroring"] is True, str(status))
        MIRRORING = False

        print("\n3. GET /api/device when the bridge is unreachable")
        BRIDGE_UP = False
        status = (await client.get("/api/device")).json()
        check("bridge_reachable false", status["bridge_reachable"] is False)
        check("mirroring false (never asked, bridge is down)", status["mirroring"] is False)
        BRIDGE_UP = True

        print("\n4. POST /scrcpy/start with no ANDROID_SERIAL is a 409")
        device_api.ANDROID_SERIAL = ""
        rejected = await client.post("/api/device/scrcpy/start")
        check("409 without a serial", rejected.status_code == 409, str(rejected.status_code))
        device_api.ANDROID_SERIAL = "159555486700071"

        print("\n5. POST /scrcpy/start when already mirroring doesn't cycle it")
        MIRRORING = True
        already = (await client.post("/api/device/scrcpy/start")).json()
        check("reports already mirroring, no new pid", already["status"] == "already mirroring" and already["pid"] is None, str(already))
        MIRRORING = False

        print("\n6. POST /scrcpy/start snaps the window once it appears (retried)")
        _snap_calls.clear()
        SNAP_SUCCEEDS_AFTER = 3
        started = (await client.post("/api/device/scrcpy/start")).json()
        check("start succeeded with the real pid", started["pid"] == 4242, str(started))
        check("snapped eventually true", started["snapped"] is True, str(started))
        check("snap was retried against the same pid until it succeeded", _snap_calls == [4242] * 4, str(_snap_calls))

        print("\n7. POST /scrcpy/start still reports success even if the window is never found")
        _snap_calls.clear()
        SNAP_SUCCEEDS_AFTER = 10_000  # never succeeds within the retry budget
        started = (await client.post("/api/device/scrcpy/start")).json()
        check("start is still a success", started["status"] == "started", str(started))
        check("snapped is false, not an error", started["snapped"] is False, str(started))

        print("\n8. POST /scrcpy/start surfaces a wsl-bridge failure as a 502")

        async def failing_start(serial):
            raise httpx.ConnectError("refused")

        wsl_bridge.scrcpy_start = failing_start
        failed = await client.post("/api/device/scrcpy/start")
        check("502 on a bridge failure", failed.status_code == 502, str(failed.status_code))
        wsl_bridge.scrcpy_start = fake_scrcpy_start

        print("\n9. POST /scrcpy/stop")
        stopped = (await client.post("/api/device/scrcpy/stop")).json()
        check("reports stopped", stopped == {"status": "stopped"}, str(stopped))

        print("\n10. POST /scrcpy/stop surfaces a wsl-bridge failure as a 502")

        async def failing_stop():
            raise httpx.ConnectError("refused")

        wsl_bridge.scrcpy_stop = failing_stop
        failed_stop = await client.post("/api/device/scrcpy/stop")
        check("502 on a bridge failure", failed_stop.status_code == 502, str(failed_stop.status_code))
        wsl_bridge.scrcpy_stop = fake_scrcpy_stop

        print("\n11. GET /api/device/adb-devices lists every known serial")
        listed = (await client.get("/api/device/adb-devices")).json()
        check("returns the fixture list", listed == {"devices": ADB_DEVICES}, str(listed))

        print("\n12. GET /api/device/adb-devices returns an empty list, not a 500, when adb itself fails")
        device_api._list_adb_devices = lambda: (_ for _ in ()).throw(RuntimeError("adb server not running"))
        listed_failed = await client.get("/api/device/adb-devices")
        check("still 200", listed_failed.status_code == 200, str(listed_failed.status_code))
        check("empty list on failure", listed_failed.json() == {"devices": []}, str(listed_failed.json()))
        device_api._list_adb_devices = fake_list_adb_devices

        print("\n13. GET /api/device with no pin reports the default (pipeline) serial")
        device_api.ANDROID_SERIAL = "159555486700071"
        unpinned = (await client.get("/api/device")).json()
        check(
            "serial/default_serial agree, no pin",
            unpinned["serial"] == "159555486700071" and unpinned["default_serial"] == "159555486700071" and unpinned["pinned_serial"] is None,
            str(unpinned),
        )

        print("\n14. PATCH /api/device/pinned-serial retargets GET /api/device without touching ANDROID_SERIAL")
        pinned = (await client.patch("/api/device/pinned-serial", json={"serial": "999999999999999"})).json()
        check("pin echoed back", pinned == {"pinned_serial": "999999999999999"}, str(pinned))
        after_pin = (await client.get("/api/device")).json()
        check(
            "effective serial follows the pin, default_serial unchanged",
            after_pin["serial"] == "999999999999999"
            and after_pin["pinned_serial"] == "999999999999999"
            and after_pin["default_serial"] == "159555486700071",
            str(after_pin),
        )
        check("model is None for a pinned serial the fixture has no model for", after_pin["model"] is None, str(after_pin))

        print("\n15. PATCH /api/device/pinned-serial with null clears the pin")
        cleared = (await client.patch("/api/device/pinned-serial", json={"serial": None})).json()
        check("pin cleared", cleared == {"pinned_serial": None}, str(cleared))
        after_clear = (await client.get("/api/device")).json()
        check("effective serial reverts to ANDROID_SERIAL", after_clear["serial"] == "159555486700071", str(after_clear))

    print("\n16. device_settings.resolve_model caches on a real success and survives a later failure")
    device_settings.set_pinned_serial(None)
    calls = {"n": 0}

    def flaky_live():
        calls["n"] += 1
        if calls["n"] == 1:
            return "Pixel 7"
        raise RuntimeError("device offline")

    first = device_settings.resolve_model("resolve-test-serial", flaky_live)
    check("first (successful) call returns the live model", first == "Pixel 7", str(first))
    second = device_settings.resolve_model("resolve-test-serial", flaky_live)
    check("second (failing) call still returns the cached model, not None", second == "Pixel 7", str(second))
    check("live_lookup was actually called both times", calls["n"] == 2, str(calls))
    never_seen = device_settings.resolve_model("a-serial-never-seen", lambda: None)
    check("a serial with no cache and no live model resolves to None", never_seen is None, str(never_seen))

    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
