#!/usr/bin/env python3
"""Lightweight MPRIS2 D-Bus bridge for Spotify Soloist (`soloist ctl trace`).

Publishes `org.mpris.MediaPlayer2.quick_spotify` on the user session bus so
Wayland shells (Noctalia, Waybar, GNOME, KDE), lock screens, and hardware
XF86Audio* media keys see live metadata, album art, progress, and transport
controls whenever Spotify Soloist is active.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from typing import Any

BUS_NAME = "org.mpris.MediaPlayer2.quick_spotify"
OBJECT_PATH = "/org/mpris/MediaPlayer2"
NO_TRACK_PATH = "/org/mpris/MediaPlayer2/TrackList/NoTrack"

MPRIS_INTROSPECTION_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek">
      <arg direction="in" name="Offset" type="x"/>
    </method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri">
      <arg direction="in" name="Uri" type="s"/>
    </method>
    <signal name="Seeked">
      <arg name="Position" type="x"/>
    </signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


def parse_trace_line(line: str) -> dict[str, Any] | None:
    """Parse one `soloist ctl trace` line (`<ts_ms> {json}` or raw `{json}`)."""
    text = (line or "").strip()
    if not text:
        return None
    brace = text.find("{")
    if brace < 0:
        return None
    try:
        parsed = json.loads(text[brace:])
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def sanitize_track_object_path(uri: str) -> str:
    """Convert a Spotify URI into a valid MPRIS2 D-Bus object path."""
    raw = str(uri or "").strip()
    if not raw:
        return NO_TRACK_PATH
    match = re.match(r"^spotify:([a-z_]+):([A-Za-z0-9]+)$", raw)
    if match:
        kind, item_id = match.group(1), match.group(2)
        return f"/org/quickspotify/{kind}/{item_id}"
    cleaned = re.sub(r"[^A-Za-z0-9_]", "_", raw).strip("_")
    return f"/org/quickspotify/item/{cleaned}" if cleaned else NO_TRACK_PATH


def pick_cover_url(covers: Any) -> str:
    """Pick the best artwork URL from Soloist's `visual_identity.cover` list."""
    if not isinstance(covers, list):
        return ""
    preferred = ("large", "default", "xlarge", "small")
    by_size: dict[str, str] = {}
    fallback = ""
    for entry in covers:
        if not isinstance(entry, dict):
            continue
        url = str(entry.get("url") or "").strip()
        if not url:
            continue
        if not fallback:
            fallback = url
        size = str(entry.get("size") or "").strip().lower()
        if size and size not in by_size:
            by_size[size] = url
    for size in preferred:
        if size in by_size:
            return by_size[size]
    return fallback


def repeat_to_mpris_loop(repeat: str) -> str:
    value = str(repeat or "off").strip().lower()
    if value == "track":
        return "Track"
    if value == "context":
        return "Playlist"
    return "None"


def mpris_loop_to_repeat(loop_status: str) -> str:
    value = str(loop_status or "None").strip().lower()
    if value == "track":
        return "track"
    if value == "playlist":
        return "context"
    return "off"


def extract_playback_snapshot(
    msg: dict[str, Any], now_ms: float | None = None
) -> dict[str, Any] | None:
    """Normalize a Soloist `playback_state` message into plain MPRIS fields."""
    if not isinstance(msg, dict) or msg.get("type") != "playback_state":
        return None
    is_active = bool(msg.get("is_active"))
    raw_status = str(msg.get("status") or "").strip().lower()
    raw_item = msg.get("item") if isinstance(msg.get("item"), dict) else None
    uri = str(raw_item.get("uri") or "").strip() if raw_item else ""

    if not is_active or not uri:
        playback_status = "Stopped"
    elif raw_status == "playing":
        playback_status = "Playing"
    else:
        playback_status = "Paused"

    title = ""
    album = ""
    artists: list[str] = []
    art_url = ""
    duration_ms = 0
    external_url = ""

    if raw_item and uri:
        dec = raw_item.get("decorations")
        if not isinstance(dec, dict):
            dec = {}
        identity = dec.get("identity") if isinstance(dec.get("identity"), dict) else {}
        title = str(identity.get("name") or "").strip()
        vis = dec.get("visual_identity")
        if isinstance(vis, dict):
            art_url = pick_cover_url(vis.get("cover"))
        parent = dec.get("parent")
        if isinstance(parent, dict):
            p_entity = parent.get("entity")
            if isinstance(p_entity, dict):
                p_dec = p_entity.get("decorations")
                if isinstance(p_dec, dict):
                    p_id = p_dec.get("identity")
                    if isinstance(p_id, dict):
                        album = str(p_id.get("name") or "").strip()
        creators = dec.get("creators")
        if isinstance(creators, list):
            for creator in creators:
                if not isinstance(creator, dict):
                    continue
                c_entity = creator.get("entity")
                if not isinstance(c_entity, dict):
                    continue
                c_dec = c_entity.get("decorations")
                if not isinstance(c_dec, dict):
                    continue
                c_id = c_dec.get("identity")
                if isinstance(c_id, dict):
                    c_name = str(c_id.get("name") or "").strip()
                    if c_name:
                        artists.append(c_name)
        playback = dec.get("playback")
        if isinstance(playback, dict):
            try:
                duration_ms = max(0, int(playback.get("duration_ms") or 0))
            except (TypeError, ValueError):
                duration_ms = 0
        match = re.match(r"^spotify:([a-z_]+):([A-Za-z0-9]+)$", uri)
        if match:
            external_url = f"https://open.spotify.com/{match.group(1)}/{match.group(2)}"

    pos = msg.get("position") if isinstance(msg.get("position"), dict) else {}
    try:
        position_ms = max(0, int(pos.get("position_ms") or 0))
    except (TypeError, ValueError):
        position_ms = 0
    try:
        timestamp_ms = float(pos.get("timestamp_ms") or 0)
    except (TypeError, ValueError):
        timestamp_ms = 0.0
    try:
        speed = float(pos.get("speed") if pos.get("speed") is not None else 1.0)
    except (TypeError, ValueError):
        speed = 1.0
    if speed <= 0:
        speed = 1.0

    current_ms = time.time() * 1000.0 if now_ms is None else float(now_ms)
    if timestamp_ms <= 0 or abs(current_ms - timestamp_ms) > 60000.0:
        timestamp_ms = current_ms

    try:
        vol_raw = float(msg.get("volume"))
        volume = max(0.0, min(1.0, vol_raw / 100.0))
    except (TypeError, ValueError):
        volume = 1.0

    opts = msg.get("options") if isinstance(msg.get("options"), dict) else {}
    shuffle = bool(opts.get("shuffle"))
    loop_status = repeat_to_mpris_loop(str(opts.get("repeat") or "off"))

    return {
        "is_active": is_active,
        "playback_status": playback_status,
        "track_id": sanitize_track_object_path(uri) if uri else NO_TRACK_PATH,
        "uri": uri,
        "title": title,
        "album": album,
        "artists": artists,
        "art_url": art_url,
        "duration_ms": duration_ms,
        "position_ms": position_ms,
        "timestamp_ms": timestamp_ms,
        "speed": speed,
        "volume": volume,
        "shuffle": shuffle,
        "loop_status": loop_status,
        "external_url": external_url,
    }


def compute_position_us(
    snapshot: dict[str, Any], now_ms: float | None = None
) -> int:
    """Compute live playback position in microseconds."""
    base_ms = max(0.0, float(snapshot.get("position_ms") or 0.0))
    duration_ms = max(0.0, float(snapshot.get("duration_ms") or 0.0))
    if snapshot.get("playback_status") == "Playing":
        ts = float(snapshot.get("timestamp_ms") or 0.0)
        speed = max(0.1, float(snapshot.get("speed") or 1.0))
        current_ms = time.time() * 1000.0 if now_ms is None else float(now_ms)
        if ts > 0 and current_ms > ts:
            base_ms += (current_ms - ts) * speed
    if duration_ms > 0:
        base_ms = min(base_ms, duration_ms)
    return int(round(max(0.0, base_ms) * 1000.0))


def run_bridge(soloist_bin: str, data_dir: str, identity: str) -> int:
    from gi.repository import Gio, GLib

    node_info = Gio.DBusNodeInfo.new_for_xml(MPRIS_INTROSPECTION_XML)
    root_iface = node_info.lookup_interface("org.mpris.MediaPlayer2")
    player_iface = node_info.lookup_interface("org.mpris.MediaPlayer2.Player")

    loop = GLib.MainLoop()
    stop_event = threading.Event()
    trace_proc_lock = threading.Lock()
    trace_proc: list[subprocess.Popen[str] | None] = [None]

    state: dict[str, Any] = {
        "logged_in": False,
        "is_active": False,
        "playback_status": "Stopped",
        "track_id": NO_TRACK_PATH,
        "uri": "",
        "title": "",
        "album": "",
        "artists": [],
        "art_url": "",
        "duration_ms": 0,
        "position_ms": 0,
        "timestamp_ms": 0.0,
        "speed": 1.0,
        "volume": 1.0,
        "shuffle": False,
        "loop_status": "None",
        "external_url": "",
    }
    dbus_conn: list[Any] = [None]

    def run_ctl(args: list[str]) -> None:
        try:
            subprocess.Popen(
                [soloist_bin, "ctl", "-D", data_dir, *args],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass

    def build_metadata_variant() -> Any:
        if not state["uri"] or not state["is_active"]:
            return GLib.Variant("a{sv}", {})
        meta: dict[str, Any] = {
            "mpris:trackid": GLib.Variant("o", state["track_id"]),
            "mpris:length": GLib.Variant("x", int(state["duration_ms"]) * 1000),
            "xesam:title": GLib.Variant("s", state["title"] or "Unknown"),
        }
        if state["artists"]:
            meta["xesam:artist"] = GLib.Variant("as", list(state["artists"]))
        if state["album"]:
            meta["xesam:album"] = GLib.Variant("s", state["album"])
        if state["art_url"]:
            meta["mpris:artUrl"] = GLib.Variant("s", state["art_url"])
        if state["external_url"]:
            meta["xesam:url"] = GLib.Variant("s", state["external_url"])
        return GLib.Variant("a{sv}", meta)

    def has_active_item() -> bool:
        return bool(state["is_active"] and state["uri"])

    def get_root_property(prop: str) -> Any:
        if prop == "CanQuit":
            return GLib.Variant("b", False)
        if prop == "CanRaise":
            return GLib.Variant("b", True)
        if prop == "HasTrackList":
            return GLib.Variant("b", False)
        if prop == "Identity":
            return GLib.Variant("s", identity)
        if prop == "DesktopEntry":
            return GLib.Variant("s", "quick-spotify")
        if prop == "SupportedUriSchemes":
            return GLib.Variant("as", ["spotify"])
        if prop == "SupportedMimeTypes":
            return GLib.Variant("as", [])
        return None

    def get_player_property(prop: str) -> Any:
        if prop == "PlaybackStatus":
            return GLib.Variant("s", state["playback_status"])
        if prop == "LoopStatus":
            return GLib.Variant("s", state["loop_status"])
        if prop == "Rate":
            return GLib.Variant("d", 1.0)
        if prop == "Shuffle":
            return GLib.Variant("b", bool(state["shuffle"]))
        if prop == "Metadata":
            return build_metadata_variant()
        if prop == "Volume":
            return GLib.Variant("d", float(state["volume"]))
        if prop == "Position":
            return GLib.Variant("x", compute_position_us(state))
        if prop == "MinimumRate":
            return GLib.Variant("d", 1.0)
        if prop == "MaximumRate":
            return GLib.Variant("d", 1.0)
        if prop == "CanGoNext":
            return GLib.Variant("b", has_active_item())
        if prop == "CanGoPrevious":
            return GLib.Variant("b", has_active_item())
        if prop == "CanPlay":
            return GLib.Variant("b", bool(state["logged_in"] or has_active_item()))
        if prop == "CanPause":
            return GLib.Variant("b", has_active_item())
        if prop == "CanSeek":
            return GLib.Variant("b", has_active_item() and state["duration_ms"] > 0)
        if prop == "CanControl":
            return GLib.Variant("b", True)
        return None

    def emit_properties_changed(changed: dict[str, Any]) -> None:
        conn = dbus_conn[0]
        if conn is None or not changed:
            return
        try:
            conn.emit_signal(
                None,
                OBJECT_PATH,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                GLib.Variant(
                    "(sa{sv}as)",
                    ("org.mpris.MediaPlayer2.Player", changed, []),
                ),
            )
        except Exception:
            pass

    def emit_seeked(pos_us: int) -> None:
        conn = dbus_conn[0]
        if conn is None:
            return
        try:
            conn.emit_signal(
                None,
                OBJECT_PATH,
                "org.mpris.MediaPlayer2.Player",
                "Seeked",
                GLib.Variant("(x)", (int(pos_us),)),
            )
        except Exception:
            pass

    def on_method_call(
        connection: Any,
        sender: str,
        object_path: str,
        interface_name: str,
        method_name: str,
        parameters: Any,
        invocation: Any,
    ) -> None:
        try:
            if interface_name == "org.mpris.MediaPlayer2":
                if method_name == "Raise":
                    cli = shutil.which("quick-spotify")
                    if cli:
                        subprocess.Popen(
                            [cli, "open"],
                            stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                invocation.return_value(None)
                return

            if interface_name == "org.mpris.MediaPlayer2.Player":
                if method_name == "Play":
                    if not state["is_active"] and state["logged_in"]:
                        run_ctl(["activate"])
                    run_ctl(["play"])
                elif method_name == "Pause" or method_name == "Stop":
                    run_ctl(["pause"])
                elif method_name == "PlayPause":
                    if state["playback_status"] == "Playing":
                        run_ctl(["pause"])
                    else:
                        if not state["is_active"] and state["logged_in"]:
                            run_ctl(["activate"])
                        run_ctl(["play"])
                elif method_name == "Next":
                    run_ctl(["next"])
                elif method_name == "Previous":
                    run_ctl(["prev"])
                elif method_name == "Seek":
                    offset_us = int(parameters.unpack()[0])
                    cur_ms = compute_position_us(state) // 1000
                    target_ms = cur_ms + (offset_us // 1000)
                    duration_ms = int(state["duration_ms"])
                    if duration_ms > 0:
                        target_ms = max(0, min(duration_ms, target_ms))
                    else:
                        target_ms = max(0, target_ms)
                    run_ctl(["seek", str(target_ms)])
                elif method_name == "SetPosition":
                    track_id, pos_us = parameters.unpack()
                    if str(track_id) == state["track_id"]:
                        target_ms = max(0, int(pos_us) // 1000)
                        duration_ms = int(state["duration_ms"])
                        if duration_ms > 0:
                            target_ms = min(duration_ms, target_ms)
                        run_ctl(["seek", str(target_ms)])
                elif method_name == "OpenUri":
                    uri = str(parameters.unpack()[0] or "").strip()
                    if uri.startswith("spotify:"):
                        run_ctl(["play", uri])
                invocation.return_value(None)
                return
        except Exception as err:
            invocation.return_dbus_error(
                "org.freedesktop.DBus.Error.Failed", str(err)
            )
            return
        invocation.return_value(None)

    def on_get_property(
        connection: Any,
        sender: str,
        object_path: str,
        interface_name: str,
        property_name: str,
    ) -> Any:
        if interface_name == "org.mpris.MediaPlayer2":
            return get_root_property(property_name)
        if interface_name == "org.mpris.MediaPlayer2.Player":
            return get_player_property(property_name)
        return None

    def on_set_property(
        connection: Any,
        sender: str,
        object_path: str,
        interface_name: str,
        property_name: str,
        value: Any,
    ) -> bool:
        if interface_name != "org.mpris.MediaPlayer2.Player":
            return False
        unpacked = value.unpack()
        if property_name == "Volume":
            pct = max(0, min(100, int(round(float(unpacked) * 100.0))))
            run_ctl(["volume", str(pct)])
            return True
        if property_name == "Shuffle":
            run_ctl(["shuffle", "on" if bool(unpacked) else "off"])
            return True
        if property_name == "LoopStatus":
            run_ctl(["repeat", mpris_loop_to_repeat(str(unpacked))])
            return True
        return False

    def apply_trace_message(msg: dict[str, Any]) -> bool:
        msg_type = msg.get("type")
        if msg_type == "auth_state":
            was_logged_in = state["logged_in"]
            was_active = state["is_active"]
            state["logged_in"] = bool(msg.get("logged_in"))
            state["is_active"] = bool(msg.get("is_active"))
            changed: dict[str, Any] = {}
            if was_logged_in != state["logged_in"]:
                changed["CanPlay"] = get_player_property("CanPlay")
            if was_active and not state["is_active"]:
                state["playback_status"] = "Stopped"
                changed["PlaybackStatus"] = get_player_property("PlaybackStatus")
                changed["Metadata"] = get_player_property("Metadata")
                changed["CanPause"] = get_player_property("CanPause")
                changed["CanGoNext"] = get_player_property("CanGoNext")
                changed["CanGoPrevious"] = get_player_property("CanGoPrevious")
                changed["CanSeek"] = get_player_property("CanSeek")
            emit_properties_changed(changed)
            return False

        snap = extract_playback_snapshot(msg)
        if snap is None:
            return False

        prev_pos_us = compute_position_us(state)
        prev_uri = state["uri"]
        prev_status = state["playback_status"]
        prev_active = state["is_active"]
        prev_vol = state["volume"]
        prev_shuffle = state["shuffle"]
        prev_loop = state["loop_status"]
        prev_meta_key = (
            state["uri"],
            state["title"],
            state["album"],
            tuple(state["artists"]),
            state["art_url"],
            state["duration_ms"],
            state["is_active"],
        )

        state.update(snap)
        new_meta_key = (
            state["uri"],
            state["title"],
            state["album"],
            tuple(state["artists"]),
            state["art_url"],
            state["duration_ms"],
            state["is_active"],
        )

        changed = {}
        if prev_status != state["playback_status"]:
            changed["PlaybackStatus"] = get_player_property("PlaybackStatus")
        if prev_meta_key != new_meta_key:
            changed["Metadata"] = get_player_property("Metadata")
        if abs(prev_vol - state["volume"]) > 0.0001:
            changed["Volume"] = get_player_property("Volume")
        if prev_shuffle != state["shuffle"]:
            changed["Shuffle"] = get_player_property("Shuffle")
        if prev_loop != state["loop_status"]:
            changed["LoopStatus"] = get_player_property("LoopStatus")
        if prev_active != state["is_active"] or prev_uri != state["uri"]:
            changed["CanPlay"] = get_player_property("CanPlay")
            changed["CanPause"] = get_player_property("CanPause")
            changed["CanGoNext"] = get_player_property("CanGoNext")
            changed["CanGoPrevious"] = get_player_property("CanGoPrevious")
            changed["CanSeek"] = get_player_property("CanSeek")

        emit_properties_changed(changed)

        new_pos_us = compute_position_us(state)
        if state["is_active"] and prev_uri == state["uri"] and abs(new_pos_us - prev_pos_us) > 1_500_000:
            emit_seeked(new_pos_us)
        return False

    def reset_disconnected() -> bool:
        if state["playback_status"] != "Stopped" or state["is_active"]:
            state["is_active"] = False
            state["playback_status"] = "Stopped"
            emit_properties_changed(
                {
                    "PlaybackStatus": get_player_property("PlaybackStatus"),
                    "Metadata": get_player_property("Metadata"),
                    "CanPause": get_player_property("CanPause"),
                    "CanGoNext": get_player_property("CanGoNext"),
                    "CanGoPrevious": get_player_property("CanGoPrevious"),
                    "CanSeek": get_player_property("CanSeek"),
                }
            )
        return False

    def trace_worker() -> None:
        while not stop_event.is_set():
            proc: subprocess.Popen[str] | None = None
            try:
                proc = subprocess.Popen(
                    [soloist_bin, "ctl", "-D", data_dir, "trace"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    bufsize=1,
                )
                with trace_proc_lock:
                    trace_proc[0] = proc
                assert proc.stdout is not None
                for raw_line in proc.stdout:
                    if stop_event.is_set():
                        break
                    msg = parse_trace_line(raw_line)
                    if msg is not None:
                        GLib.idle_add(apply_trace_message, msg)
            except OSError:
                pass
            finally:
                with trace_proc_lock:
                    trace_proc[0] = None
                if proc is not None:
                    try:
                        proc.terminate()
                        proc.wait(timeout=1)
                    except Exception:
                        try:
                            proc.kill()
                        except Exception:
                            pass
            if not stop_event.is_set():
                GLib.idle_add(reset_disconnected)
                stop_event.wait(1.0)

    def on_bus_acquired(connection: Any, name: str) -> None:
        dbus_conn[0] = connection
        connection.register_object(
            OBJECT_PATH,
            root_iface,
            on_method_call,
            on_get_property,
            on_set_property,
        )
        connection.register_object(
            OBJECT_PATH,
            player_iface,
            on_method_call,
            on_get_property,
            on_set_property,
        )

    def shutdown(*_args: Any) -> None:
        stop_event.set()
        with trace_proc_lock:
            proc = trace_proc[0]
            if proc is not None:
                try:
                    proc.terminate()
                except Exception:
                    pass
        GLib.idle_add(loop.quit)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    owner_id = Gio.bus_own_name(
        Gio.BusType.SESSION,
        BUS_NAME,
        Gio.BusNameOwnerFlags.REPLACE | Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT,
        on_bus_acquired,
        None,
        None,
    )

    worker = threading.Thread(target=trace_worker, daemon=True)
    worker.start()

    try:
        loop.run()
    finally:
        stop_event.set()
        with trace_proc_lock:
            proc = trace_proc[0]
            if proc is not None:
                try:
                    proc.terminate()
                except Exception:
                    pass
        Gio.bus_unown_name(owner_id)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="MPRIS2 D-Bus bridge for Spotify Soloist")
    parser.add_argument(
        "--soloist-bin",
        default=os.path.expanduser("~/.local/lib/quick-spotify/soloist"),
        help="Path to the soloist binary",
    )
    parser.add_argument(
        "--data-dir",
        default=os.path.join(
            os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
            "soloist",
        ),
        help="Soloist persistent data directory",
    )
    parser.add_argument(
        "--identity",
        default="Quick Spotify",
        help="MPRIS2 Identity string",
    )
    args = parser.parse_args()
    return run_bridge(args.soloist_bin, args.data_dir, args.identity)


if __name__ == "__main__":
    sys.exit(main())
