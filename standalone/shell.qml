import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Theme
import "plugin" as Plugin

ShellRoot {
  id: root

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configHome: {
    var explicit = String(Quickshell.env("XDG_CONFIG_HOME") || "").trim()
    return explicit ? explicit : (homeDir + "/.config")
  }
  readonly property string settingsDir: configHome + "/quick-spotify"
  readonly property string settingsPath: settingsDir + "/settings.json"

  property var settingsEntry: ({
    id: "quickshell.spotify",
    deviceName: "Quick Spotify",
    builtInReceiver: "On",
    soloistReceiver: "Off",
    idleShutdownMinutes: 15,
    showMiniPlayer: "On",
    showVinylRecord: "Off",
    shortcutPlayer: "Full player",
    shortcutHints: "On",
    showLyrics: "Off",
    showArtwork: "On",
    showTrackTitle: "On",
    showArtistName: "Off",
    showPausedTrack: "On",
    scrollBarText: "Off",
    scrollSpeed: "1",
    maxBarTextWidth: "240",
    fixedBarWidth: "Off",
    audioQuality: "320 kbps"
  })

  property var barWidgets: []

  function registerWidget(w) {
    if (barWidgets.indexOf(w) < 0)
      barWidgets = barWidgets.concat([w])
  }

  function unregisterWidget(w) {
    barWidgets = barWidgets.filter(function(item) { return item && item !== w })
  }

  function hideAllMiniPlayers() {
    for (var i = 0; i < barWidgets.length; i++) {
      if (barWidgets[i] && barWidgets[i].popupOpen)
        barWidgets[i].close()
    }
  }

  function mergeSettings(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "{}")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return
    var merged = {}
    for (var k in root.settingsEntry) merged[k] = root.settingsEntry[k]
    for (var pk in parsed) {
      if (parsed[pk] !== undefined && parsed[pk] !== null)
        merged[pk] = parsed[pk]
    }
    merged.id = "quickshell.spotify"
    root.settingsEntry = merged
    spotifyService.syncSettings()
  }

  property string pendingSettingsJson: ""

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    printErrors: false
    onLoaded: root.mergeSettings(text())
    onLoadFailed: spotifyService.syncSettings()
  }

  Process {
    id: settingsDirMaker
    command: ["/usr/bin/env", "sh", "-c", "mkdir -p -- \"$1\"", "sh", root.settingsDir]
    onExited: function(code) {
      if (code === 0 && root.pendingSettingsJson.length > 0) {
        settingsFile.setText(root.pendingSettingsJson)
        root.pendingSettingsJson = ""
      }
    }
  }

  QtObject {
    id: host
    readonly property var shellConfig: ({
      plugins: [root.settingsEntry]
    })
    readonly property var bar: QtObject {
      function hideBarWidget(moduleName) {
        root.hideAllMiniPlayers()
        return true
      }
    }

    function serviceFor(moduleName) {
      return moduleName === "quickshell.spotify" ? spotifyService : null
    }

    function isPluginOpen(moduleName) {
      return moduleName === "quickshell.spotify" && panel.opened
    }

    function summon(moduleName, payloadJson) {
      if (moduleName !== "quickshell.spotify") return false
      root.hideAllMiniPlayers()
      panel.open(payloadJson || "{}")
      return true
    }

    function hide(moduleName) {
      if (moduleName !== "quickshell.spotify") return false
      panel.close()
      return true
    }

    function toggle(moduleName, payloadJson) {
      if (moduleName !== "quickshell.spotify") return false
      if (panel.opened) {
        panel.close()
        return false
      }
      root.hideAllMiniPlayers()
      panel.open(payloadJson || "{}")
      return true
    }

    function updateEntryInline(pluginId, next) {
      if (pluginId !== "quickshell.spotify" || !next) return
      var updated = {}
      for (var k in root.settingsEntry) updated[k] = root.settingsEntry[k]
      for (var nk in next) updated[nk] = next[nk]
      updated.id = "quickshell.spotify"
      root.settingsEntry = updated
      root.pendingSettingsJson = JSON.stringify(updated, null, 2) + "\n"
      if (!settingsDirMaker.running)
        settingsDirMaker.running = true
    }
  }

  Plugin.Service {
    id: spotifyService
    shell: host
    manifest: ({
      id: "quickshell.spotify",
      name: "Quick Spotify",
      version: "1.1.0"
    })
  }

  Plugin.Panel {
    id: panel
    shell: host
    manifest: spotifyService.manifest
    service: spotifyService
  }

  // Per-monitor zero-input-region top anchor so the mini-player KeyboardPanel
  // opens cleanly below any desktop bar (Noctalia, Waybar, KDE, GNOME, etc.)
  // on whichever output currently holds focus, without intercepting clicks.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: anchorWin
        required property var modelData

        screen: modelData
        visible: true
        color: "transparent"
        implicitHeight: 36
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quick-spotify-anchor"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          left: true
          right: true
        }

        mask: Region {}

        QtObject {
          id: screenBar
          readonly property var shell: host
          readonly property bool vertical: false
          readonly property bool foregroundAnimationEnabled: false
          readonly property int barSize: 36
          readonly property string fontFamily: Style.font.family
          readonly property string position: "top"
          readonly property color foreground: Theme.Color.foreground
          readonly property color barForeground: Theme.Color.foreground
          readonly property color background: Theme.Color.background
          property var activePopout: null

          function requestPopout(key) {
            activePopout = key
          }

          function releasePopout(key) {
            if (activePopout === key) activePopout = null
          }

          function isBarWidgetOpen(moduleName) {
            return widget.popupOpen
          }

          function summonBarWidget(moduleName) {
            widget.open()
            return widget.popupOpen
          }

          function hideBarWidget(moduleName) {
            widget.close()
            return true
          }

          function run(cmd) {
            if (String(cmd || "").indexOf("omarchy launch spotify") === 0) {
              host.toggle("quickshell.spotify", JSON.stringify({ shortcutLatch: true }))
              return
            }
            Quickshell.execDetached(["/usr/bin/env", "sh", "-c", String(cmd || "")])
          }
        }

        Plugin.BarWidget {
          id: widget
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          opacity: 0
          enabled: false
          bar: screenBar
          settings: root.settingsEntry

          Component.onCompleted: root.registerWidget(widget)
          Component.onDestruction: root.unregisterWidget(widget)
        }
      }
    }
  }

  IpcHandler {
    target: "quick.spotify"

    function ping(): string {
      return "pong"
    }

    function toggle(): string {
      return spotifyService.invokePlayerShortcut("toggleConfiguredPlayerShortcut")
    }

    function full(): string {
      return spotifyService.invokePlayerShortcut("toggleFullPlayerShortcut")
    }

    function mini(): string {
      return spotifyService.invokePlayerShortcut("toggleMiniPlayerShortcut")
    }

    function summon(payloadJson: string): string {
      host.summon("quickshell.spotify", payloadJson || "{}")
      return "opened"
    }

    function close(): string {
      host.hide("quickshell.spotify")
      root.hideAllMiniPlayers()
      return "closed"
    }

    function playPause(): string {
      spotifyService.togglePlayback()
      return "ok"
    }

    function next(): string {
      spotifyService.next()
      return "ok"
    }

    function previous(): string {
      spotifyService.previous()
      return "ok"
    }

    function volumeUp(): string {
      var surface = spotifyService.shortcutSurface()
      return surface && surface.adjustVolume(0.05) ? "ok" : "unavailable"
    }

    function volumeDown(): string {
      var surface = spotifyService.shortcutSurface()
      return surface && surface.adjustVolume(-0.05) ? "ok" : "unavailable"
    }

    function mute(): string {
      spotifyService.toggleMute()
      return "ok"
    }

    function status(): string {
      return JSON.stringify({
        playing: spotifyService.playing,
        hasMedia: spotifyService.hasMedia,
        title: spotifyService.title,
        artist: spotifyService.artist,
        album: spotifyService.album,
        artUrl: spotifyService.artUrl,
        volume: Math.round(spotifyService.volume * 100)
      })
    }
  }
}
