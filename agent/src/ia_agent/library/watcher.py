import asyncio
from pathlib import Path

from watchfiles import awatch

from ia_agent.events.bus import EventBus
from ia_agent.library import folders
from ia_agent.library.counts import LibraryCounts
from ia_agent.logging import logger


_RESEED_INTERVAL_SECONDS = 300


async def watch_library(bus: EventBus, counts: LibraryCounts, reseed_interval: float = _RESEED_INTERVAL_SECONDS) -> None:
    """Recomputes and broadcasts exactly the `(folder, root)` pairs a batch of
    filesystem changes touched. Unlike `config/watcher.py`'s deliberately
    non-recursive watch of `IA_DIR`'s top level, this one watches the seven
    known stage directories recursively — that churn is exactly what the
    Library screen needs to reflect — but by passing those seven paths
    explicitly rather than `IA_DIR` itself, `.thumbs`/`.Trash-0`/`config.env`
    changes never wake it.

    Runs alongside `_periodic_reseed` — found necessary live, 2026-08-11:
    `entity_classify` moving a whole batch of files into `gender_valid`/
    `gender_invalid` at once overflowed Windows' change-notification buffer
    for those two directories specifically, and unlike a merely coalesced or
    dropped single event (which the next real touch of that same pair still
    fixes), the underlying watch stopped delivering *anything* for them ever
    again — `scanned`/`scraped` kept updating live the whole time. The
    periodic reseed is the safety net for that failure mode."""
    paths = []
    for folder in folders.FOLDERS.values():
        folder.path.mkdir(parents=True, exist_ok=True)
        paths.append(str(folder.path))

    await asyncio.gather(
        _watch_changes(bus, counts, paths),
        _periodic_reseed(bus, counts, reseed_interval),
    )


async def _watch_changes(bus: EventBus, counts: LibraryCounts, paths: list[str]) -> None:
    async for changes in awatch(*paths):
        touched: set[tuple[str, str | None]] = set()
        for _change, raw_path in changes:
            resolved = folders.resolve(Path(raw_path))
            if resolved is not None:
                touched.add(resolved)
        if not touched:
            continue
        results = await asyncio.gather(
            *(asyncio.to_thread(counts.touch, folder_name, root) for folder_name, root in touched)
        )
        logger.debug(f"library changed: {results}")
        await bus.publish("library.changes", {"changes": results})


async def _periodic_reseed(bus: EventBus, counts: LibraryCounts, interval: float) -> None:
    """A full `seed()` is cheap (~15ms measured over the real 7,655-file
    `IA_DIR`, CP 5.1) so a plain interval is simpler and more robust than
    trying to detect a dead watch directly — it bounds how long any folder's
    count can stay wrong regardless of what specifically broke."""
    while True:
        await asyncio.sleep(interval)
        before = counts.folders()
        await asyncio.to_thread(counts.seed)
        after = counts.folders()
        if before == after:
            continue
        logger.warning(f"library periodic reseed found drift: {before} -> {after}")
        changes = [{"folder": f["name"], "root": None, "count": f["total"]} for f in after]
        await bus.publish("library.changes", {"changes": changes})
