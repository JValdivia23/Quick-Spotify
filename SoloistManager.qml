import QtQuick
import Quickshell
import Quickshell.Io

import "Api.js" as Api

// Supervises the optional Spotify Soloist local receiver (`quick-spotify-soloist.service`)
// and manages private stdin API key setup without exposing secrets in settings or argv.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property string pluginDir: ""
  property string deviceName: "Quick Spotify"
  property bool installed: false
  property bool keyConfigured: false
  property bool running: false
  property bool loggedIn: false
  property bool unitReady: false
  property bool desktopHelperAvailable: false
  property string version: ""
  property bool statusChecked: false
  property bool busy: setupProc.running || startProc.running || stopProc.running || clearProc.running
  property bool setupBusy: setupProc.running
  property string lastError: ""
  property string pendingApiKey: ""

  signal setupSucceeded()
  signal setupFailed(string reason)
  signal paired()
  signal clipboardLoaded(string text)

  function safeError(value) {
    return Api.redact(String(value || ""))
  }

  function refresh() {
    if (!pluginDir || statusProc.running) return
    statusProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "status"]
    statusProc.running = true
  }

  function configureDeviceName(name) {
    if (!pluginDir || !unitReady || configProc.running) return
    var clean = String(name || "Quick Spotify").trim() || "Quick Spotify"
    configProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "configure",
      "--device-name", clean]
    configProc.running = true
  }

  function saveApiKey(rawKey, targetDeviceName) {
    if (!pluginDir || setupProc.running) return false
    var trimmed = String(rawKey || "").trim()
    if (trimmed.length < 16) {
      lastError = "Paste a valid Spotify Soloist API key (at least 16 characters)."
      setupFailed(lastError)
      return false
    }
    lastError = ""
    pendingApiKey = trimmed
    var cleanName = String(targetDeviceName || deviceName || "Quick Spotify").trim() || "Quick Spotify"
    setupProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "setup-key",
      "--device-name", cleanName]
    setupProc.running = true
    return true
  }

  function start() {
    if (!pluginDir || !keyConfigured || startProc.running || setupProc.running) return
    lastError = ""
    startProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "start"]
    startProc.running = true
  }

  function stop() {
    if (!pluginDir || stopProc.running) return
    stopProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "stop"]
    stopProc.running = true
  }

  function clearKey() {
    if (!pluginDir || clearProc.running || setupProc.running) return
    lastError = ""
    clearProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "clear-key"]
    clearProc.running = true
  }

  function openDocs() {
    if (browserProc.running) return
    browserProc.command = ["xdg-open", "https://developer.spotify.com/documentation/soloist"]
    browserProc.running = true
  }

  function readClipboard() {
    if (!pluginDir || clipboardProc.running) return
    clipboardProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "clipboard"]
    clipboardProc.running = true
  }

  function activateLocal() {
    if (!pluginDir || activateProc.running) return
    activateProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "activate"]
    activateProc.running = true
  }

  function launchPairHelper() {
    if (!pluginDir || helperProc.running) return
    helperProc.command = ["/usr/bin/env", "bash",
      pluginDir + "/scripts/soloist-runtime.sh", "launch-pair-helper"]
    helperProc.running = true
  }

  onPluginDirChanged: if (pluginDir) refresh()
  onDeviceNameChanged: if (pluginDir && unitReady) configureDeviceName(deviceName)

  Timer {
    id: pollTimer
    interval: root.running && !root.loggedIn ? 3000 : 10000
    repeat: true
    running: !!root.pluginDir && (root.keyConfigured || root.running)
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }
    onExited: function(code) {
      var wasLoggedIn = root.loggedIn
      root.statusChecked = true
      if (code !== 0) return
      var parsed = Api.parseJson(statusStdout.text, null)
      if (!parsed) return
      root.installed = parsed.installed === true
      root.keyConfigured = parsed.keyConfigured === true
      root.running = parsed.running === true
      root.loggedIn = parsed.loggedIn === true
      root.unitReady = parsed.unitReady === true
      root.desktopHelperAvailable = parsed.desktopHelperAvailable === true
      root.version = String(parsed.version || "")
      if (!wasLoggedIn && root.loggedIn)
        root.paired()
    }
  }

  Process {
    id: setupProc
    stdinEnabled: true
    stderr: StdioCollector {
      id: setupStderr
      waitForEnd: true
    }
    onStarted: {
      if (root.pendingApiKey !== "") {
        write(root.pendingApiKey + "\n")
        root.pendingApiKey = ""
      }
    }
    onExited: function(code) {
      root.pendingApiKey = ""
      root.refresh()
      if (code === 0) {
        root.running = true
        root.keyConfigured = true
        root.installed = true
        root.lastError = ""
        root.setupSucceeded()
      } else {
        var err = root.safeError(String(setupStderr.text || "").trim())
        root.lastError = err || "Could not configure Spotify Soloist. Check your API key and network."
        root.setupFailed(root.lastError)
      }
    }
  }

  Process {
    id: configProc
    onExited: root.refresh()
  }

  Process {
    id: startProc
    stderr: StdioCollector {
      id: startStderr
      waitForEnd: true
    }
    onExited: function(code) {
      root.refresh()
      if (code !== 0) {
        var err = root.safeError(String(startStderr.text || "").trim())
        root.lastError = err || "Spotify Soloist could not start."
      }
    }
  }

  Process {
    id: stopProc
    onExited: {
      root.running = false
      root.refresh()
    }
  }

  Process {
    id: clearProc
    onExited: {
      root.running = false
      root.keyConfigured = false
      root.loggedIn = false
      root.refresh()
    }
  }

  Process {
    id: activateProc
  }

  Process {
    id: helperProc
  }

  Process {
    id: browserProc
  }

  Process {
    id: clipboardProc
    stdout: StdioCollector {
      id: clipboardStdout
      waitForEnd: true
    }
    onExited: function(code) {
      if (code === 0)
        root.clipboardLoaded(String(clipboardStdout.text || "").trim())
    }
  }
}
