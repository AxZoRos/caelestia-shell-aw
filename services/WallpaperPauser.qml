pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Io

import qs.services

Singleton {
    id: root

    property bool pauseOnBattery: false
    property bool pauseOnWindowOverlap: true
    property string hwDecoder: "none"

    Settings {
        id: pauserSettings
        category: "WallpaperPauser"
        property alias pauseOnBattery: root.pauseOnBattery
        property alias pauseOnWindowOverlap: root.pauseOnWindowOverlap
        property alias hwDecoder: root.hwDecoder
    }

    property bool paused: false
    property bool _loaded: false
    property string pauseReason: "None"

    readonly property real largeWindowAreaRatio: 0.7

    Process {
        id: saveHwDecoderProcess
    }

    // Escapes single quotes for shell command execution
    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    // Rule #1 — Battery status check
    function checkBatteryReason() {
        if (pauseOnBattery && UPower.onBattery) {
            return "Battery";
        }
        return "";
    }

    // Rules #2 & #3 — Window overlap and screen coverage checks
    function checkWindowOverlapReason() {
        if (!pauseOnWindowOverlap)
            return "";

        const monitor = Hyprland.focusedMonitor;
        const ws = monitor?.activeWorkspace ?? Hyprland.focusedWorkspace;
        if (!ws)
            return "";

        const toplevels = ws.toplevels.values;

        // Rule #2 — 2+ visible windows threshold
        if (toplevels.length >= 2) {
            return `2+ windows (${toplevels.length} total)`;
        }

        // Rule #3 — Large single window coverage rule
        if (monitor) {
            const screen = Quickshell.screens.find(s => s.name === monitor.name);
            const screenArea = screen ? (screen.width * screen.height) : 0;
            if (screenArea > 0) {
                const threshold = screenArea * largeWindowAreaRatio;
                const percent = Math.round(largeWindowAreaRatio * 100);
                for (const t of toplevels) {
                    const size = t.lastIpcObject?.size;
                    if (size && size.length >= 2 && (size[0] * size[1]) >= threshold) {
                        const title = t.lastIpcObject?.title ?? "Unknown";
                        return `${percent}%+ area rule by: ${title} (${size[0]}x${size[1]})`;
                    }
                }
            }
        }

        return "";
    }

    function recalculate() {
        let reason = checkBatteryReason();

        if (!reason) {
            reason = checkWindowOverlapReason();
        }

        paused = !!reason;
        pauseReason = reason || "None";
    }

    readonly property var relevantEventPrefixes: ["workspace", "activewindow", "createworkspace", "destroyworkspace"]
    readonly property var relevantEventNames: ["fullscreen", "changefloatingmode", "minimize", "movewindow", "openwindow", "closewindow", "moveworkspace", "focusedmon"]

    function isRelevantHyprlandEvent(name) {
        return relevantEventPrefixes.some(prefix => name.startsWith(prefix)) || relevantEventNames.includes(name);
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.recalculate();
        }
        function onFocusedMonitorChanged() {
            root.recalculate();
        }
        function onRawEvent(event) {
            if (root.isRelevantHyprlandEvent(event.name)) {
                recalcTimer.restart();
            }
        }
    }

    Connections {
        target: UPower
        function onOnBatteryChanged() {
            recalcTimer.restart();
        }
    }

    Timer {
        id: recalcTimer
        interval: 50
        onTriggered: root.recalculate()
    }

    // Startup timer to ensure we catch asynchronously loaded Hyprland state
    Timer {
        id: startupTimer
        interval: 1000
        repeat: true
        running: true
        property int attempts: 0
        onTriggered: {
            root.recalculate();
            attempts++;
            if (attempts >= 5)
                running = false;
        }
    }

    onPauseOnBatteryChanged: recalculate()
    onPauseOnWindowOverlapChanged: recalculate()

    // Sync hwDecoder to disk for external CLI environment injection before Qt startup
    function _syncHwDecoder() {
        if (!root._loaded)
            return;
        const cmd = `echo ${shellQuote(root.hwDecoder)} > ~/.cache/caelestia/hwDecoder.txt && nohup sh -c 'sleep 0.5 && caelestia shell -d' >/dev/null 2>&1 & caelestia shell -k`;
        saveHwDecoderProcess.command = ["sh", "-c", cmd];
        saveHwDecoderProcess.running = true;
    }

    onHwDecoderChanged: _syncHwDecoder()

    Component.onCompleted: {
        root._loaded = true;
        recalculate();
    }
}
