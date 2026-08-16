"""Agent-owned ADB device identity (PLAN V2.13.1): a cached serial->model map
(adb is not always reachable, but a phone's model never changes once seen)
plus an optional pinned serial for the rare case of more than one device
being attached at once. Persisted the same way `library/settings.py`
persists move targets — machine-local JSON, atomic write, D12's reasoning
applies again: this is a desktop-app concern, not something the pipeline
reads.
"""
import json
import threading
from typing import Callable

from ia_agent.logging import logger
from ia_agent.vars import DEVICE_SETTINGS_PATH

_lock = threading.Lock()

_DEFAULTS = {"pinned_serial": None, "model_cache": {}}


def _load() -> dict:
    if not DEVICE_SETTINGS_PATH.exists():
        return {**_DEFAULTS, "model_cache": {}}
    try:
        data = json.loads(DEVICE_SETTINGS_PATH.read_text())
    except (json.JSONDecodeError, OSError) as error:
        logger.warning(f"unreadable device settings, falling back to defaults — {error}")
        return {**_DEFAULTS, "model_cache": {}}
    return {
        "pinned_serial": data.get("pinned_serial") or None,
        "model_cache": data.get("model_cache") or {},
    }


def _save(data: dict) -> None:
    DEVICE_SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    temp = DEVICE_SETTINGS_PATH.with_suffix(".tmp")
    temp.write_text(json.dumps(data, indent=2))
    temp.replace(DEVICE_SETTINGS_PATH)


def pinned_serial() -> str | None:
    return _load()["pinned_serial"]


def set_pinned_serial(serial: str | None) -> str | None:
    serial = serial.strip() if serial else None
    with _lock:
        data = _load()
        data["pinned_serial"] = serial or None
        _save(data)
        return data["pinned_serial"]


def cached_model(serial: str) -> str | None:
    return _load()["model_cache"].get(serial)


def cache_model(serial: str, model: str) -> None:
    with _lock:
        data = _load()
        data["model_cache"][serial] = model
        _save(data)


def resolve_model(serial: str, live_lookup: Callable[[], str | None]) -> str | None:
    """`live_lookup` is the real, best-effort adbutils call. Any failure —
    adb server down, device disconnected, property unreadable — means "can't
    ask right now," not "no model," so it must never evict what's already
    cached; only a real, successful read ever updates the cache."""
    try:
        model = live_lookup()
    except Exception:
        model = None
    if model:
        cache_model(serial, model)
        return model
    return cached_model(serial)
