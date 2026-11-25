#!/usr/bin/env python3
"""Unit tests for the Spotify Soloist MPRIS2 D-Bus bridge helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

SCRIPT_PATH = Path(__file__).resolve().parent.parent / "scripts" / "soloist-mpris-bridge.py"
SPEC = importlib.util.spec_from_file_location("soloist_mpris_bridge", SCRIPT_PATH)
assert SPEC and SPEC.loader
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class SoloistMprisBridgeTests(unittest.TestCase):
    def test_parse_trace_line_strips_timestamp_prefix(self) -> None:
        self.assertIsNone(bridge.parse_trace_line("connected to ws://127.0.0.1:33183"))
        parsed = bridge.parse_trace_line(
            '1795635468271 {"type":"auth_state","logged_in":true,"is_active":true}'
        )
        self.assertEqual(parsed, {"type": "auth_state", "logged_in": True, "is_active": True})

    def test_extract_playback_snapshot_maps_metadata_and_position(self) -> None:
        msg = {
            "type": "playback_state",
            "status": "playing",
            "is_active": True,
            "volume": 75,
            "options": {"shuffle": True, "repeat": "context"},
            "position": {"position_ms": 10000, "timestamp_ms": 1000000, "speed": 1},
            "item": {
                "uri": "spotify:track:27824hvVGxllQecjb1dqDg",
                "entity_type": "track",
                "decorations": {
                    "identity": {"name": "Just A Western"},
                    "visual_identity": {
                        "cover": [
                            {"url": "https://img/small", "size": "small"},
                            {"url": "https://img/large", "size": "large"},
                        ]
                    },
                    "parent": {
                        "entity": {
                            "uri": "spotify:album:77DNkESTu7pZbZjWq3RD9e",
                            "decorations": {"identity": {"name": "Remix EP"}},
                        }
                    },
                    "creators": [
                        {"entity": {"decorations": {"identity": {"name": "Nilüfer Yanya"}}}},
                        {"entity": {"decorations": {"identity": {"name": "Boy Harsher"}}}},
                    ],
                    "playback": {"duration_ms": 241379},
                },
            },
        }
        snap = bridge.extract_playback_snapshot(msg, now_ms=1002000)
        self.assertIsNotNone(snap)
        assert snap is not None
        self.assertEqual(snap["playback_status"], "Playing")
        self.assertEqual(snap["track_id"], "/org/quickspotify/track/27824hvVGxllQecjb1dqDg")
        self.assertEqual(snap["title"], "Just A Western")
        self.assertEqual(snap["album"], "Remix EP")
        self.assertEqual(snap["artists"], ["Nilüfer Yanya", "Boy Harsher"])
        self.assertEqual(snap["art_url"], "https://img/large")
        self.assertAlmostEqual(snap["volume"], 0.75)
        self.assertTrue(snap["shuffle"])
        self.assertEqual(snap["loop_status"], "Playlist")
        self.assertEqual(bridge.compute_position_us(snap, now_ms=1002500), 12_500_000)

    def test_inactive_snapshot_reports_stopped(self) -> None:
        msg = {
            "type": "playback_state",
            "status": "paused",
            "is_active": False,
            "item": {"uri": "spotify:track:abc123"},
        }
        snap = bridge.extract_playback_snapshot(msg, now_ms=1000)
        assert snap is not None
        self.assertEqual(snap["playback_status"], "Stopped")


if __name__ == "__main__":
    unittest.main()
