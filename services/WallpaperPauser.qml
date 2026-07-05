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

    Settings {
        id: pauserSettings
        category: "WallpaperPauser"
        property bool pauseOnBattery: false
        property bool pauseOnWindowOverlap: true
        property string hwDecoder: "none"
    }

    property alias pauseOnBattery: pauserSettings.pauseOnBattery
    property alias pauseOnWindowOverlap: pauserSettings.pauseOnWindowOverlap
    property alias hwDecoder: pauserSettings.hwDecoder
    property bool paused: false
    property bool _loaded: false

    Process {
        id: saveHwDecoderProcess
    }

    function recalculate() {
        let newPaused = false;
        let reason = "None";

        // Rule #1 — Battery
        if (pauseOnBattery && UPower.onBattery) {
            newPaused = true;
            reason = "Battery";
        } else if (pauseOnWindowOverlap) {
            const monitor = Hyprland.focusedMonitor;
            const ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace : Hyprland.focusedWorkspace;

            if (ws) {
                // Strictly filter global toplevels to ONLY the focused workspace
                const toplevels = Hyprland.toplevels.values.filter(t => {
                    const obj = t.lastIpcObject;
                    return obj && obj.workspace && obj.workspace.id === ws.id;
                });

                // Rule #3 — 2+ visible windows
                if (toplevels.length >= 2) {
                    newPaused = true;
                    reason = "2+ windows (" + toplevels.length + " total)";
                } else {
                    // Rule #2 — 70% of monitor area
                    if (monitor) {
                        const screen = Quickshell.screens.find(s => s.name === monitor.name);
                        if (screen) {
                            const screenArea = screen.width * screen.height;
                            if (screenArea > 0) {
                                const threshold = screenArea * 0.7;
                                for (const t of toplevels) {
                                    const size = t.lastIpcObject.size;
                                    if (size && size.length >= 2 && size[0] * size[1] >= threshold) {
                                        newPaused = true;
                                        reason = "70% area rule by: " + t.lastIpcObject.title + " (" + size[0] + "x" + size[1] + ")";
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        paused = newPaused;
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
            const n = event.name;
            if (n.startsWith("workspace") || n.startsWith("activewindow") || n.startsWith("createworkspace") || n.startsWith("destroyworkspace") || ["fullscreen", "changefloatingmode", "minimize", "movewindow", "openwindow", "closewindow", "moveworkspace", "focusedmon"].includes(n)) {
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
        interval: 150
        onTriggered: root.recalculate()
    }

    onPauseOnBatteryChanged: {
        recalculate();
    }

    onPauseOnWindowOverlapChanged: {
        recalculate();
    }

    onHwDecoderChanged: {
        // We still need to sync this to a text file because the python CLI needs to read it
        // BEFORE the Qt application starts in order to inject the environment variables.
        if (root._loaded) {
            saveHwDecoderProcess.command = ["sh", "-c", "echo '" + root.hwDecoder + "' > ~/.cache/caelestia/hwDecoder.txt && nohup sh -c 'sleep 0.5 && caelestia shell -d' >/dev/null 2>&1 & caelestia shell -k"];
            saveHwDecoderProcess.running = true;
        }
    }

    Component.onCompleted: {
        root._loaded = true;
        recalculate();
    }
}
