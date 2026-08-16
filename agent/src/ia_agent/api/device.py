import asyncio

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ia_agent import device_settings, window
from ia_agent.integrations import wsl_bridge
from ia_agent.vars import ANDROID_SERIAL

# The window doesn't exist the instant the process does - give it a moment
# to actually appear before giving up on the snap. Best-effort: a start that
# succeeds but never gets snapped is still a successful start.
_SNAP_ATTEMPTS = 20
_SNAP_INTERVAL = 0.25


class PinnedSerialBody(BaseModel):
    serial: str | None = None


def create_device_router() -> APIRouter:
    router = APIRouter(prefix="/api/device")

    @router.get("")
    async def get_device() -> dict:
        serial = _effective_serial()
        try:
            bridge_reachable = await wsl_bridge.bridge_healthy()
        except Exception:
            bridge_reachable = False
        mirroring = False
        if bridge_reachable:
            try:
                mirroring = await wsl_bridge.scrcpy_status()
            except Exception:
                mirroring = False
        model = await asyncio.to_thread(_device_model, serial) if serial else None
        return {
            "serial": serial or None,
            "model": model,
            "pinned_serial": device_settings.pinned_serial(),
            "default_serial": ANDROID_SERIAL or None,
            "bridge_reachable": bridge_reachable,
            "mirroring": mirroring,
        }

    @router.get("/adb-devices")
    async def get_adb_devices() -> dict:
        try:
            devices = await asyncio.to_thread(_list_adb_devices)
        except Exception:
            devices = []
        return {"devices": devices}

    @router.patch("/pinned-serial")
    async def patch_pinned_serial(body: PinnedSerialBody) -> dict:
        return {"pinned_serial": device_settings.set_pinned_serial(body.serial)}

    @router.post("/scrcpy/start")
    async def start_scrcpy() -> dict:
        serial = _effective_serial()
        if not serial:
            raise HTTPException(status_code=409, detail="ANDROID_SERIAL is not set")
        try:
            if await wsl_bridge.scrcpy_status():
                # start() calls stop() on the way in - cycling an existing
                # mirror would throw a new window on screen for no reason.
                return {"status": "already mirroring", "pid": None, "snapped": False}
            result = await wsl_bridge.scrcpy_start(serial)
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"wsl-bridge call failed: {error}")

        pid = result.get("pid")
        snapped = False
        if pid:
            for _ in range(_SNAP_ATTEMPTS):
                await asyncio.sleep(_SNAP_INTERVAL)
                snapped = await asyncio.to_thread(window.snap_to_known_position, pid)
                if snapped:
                    break
        return {**result, "snapped": snapped}

    @router.post("/scrcpy/stop")
    async def stop_scrcpy() -> dict:
        try:
            await wsl_bridge.scrcpy_stop()
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"wsl-bridge call failed: {error}")
        return {"status": "stopped"}

    return router


def _effective_serial() -> str:
    """A pinned serial (Settings → Devices) always wins over the pipeline's
    own `ANDROID_SERIAL` — the pin exists specifically for the case that
    default is wrong (more than one device ever attached)."""
    return device_settings.pinned_serial() or ANDROID_SERIAL


def _device_model(serial: str) -> str | None:
    """Best-effort live read, same reasoning as `services/selftest.py`'s own
    `device.prop.model` read for the adb functional test — a compact model
    name (e.g. "Pixel 7") reads far better in the header's device bar than
    the serial's 15 raw digits. Falls through `device_settings.resolve_model`
    so a transient disconnect still serves the cached model instead of
    reverting to the bare serial (PLAN V2.13.1)."""

    def live() -> str | None:
        import adbutils

        client = adbutils.AdbClient(host="127.0.0.1", port=5037)
        return client.device(serial=serial).prop.model or None

    return device_settings.resolve_model(serial, live)


def _list_adb_devices() -> list[dict]:
    """Every serial `adb` currently knows about, online or not — the
    Settings dropdown (PLAN V2.13.1) needs to show a disconnected device the
    user still wants to pin, not just the ones actually reachable right
    now."""
    import adbutils

    client = adbutils.AdbClient(host="127.0.0.1", port=5037)
    return [{"serial": info.serial, "state": info.state} for info in client.list()]
