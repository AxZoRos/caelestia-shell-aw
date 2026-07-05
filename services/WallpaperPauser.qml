pragma Singleton

import QtQuick
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
    property bool paused: false
    property bool _loaded: false
    property bool _windowLoaded: false
    property bool _hwDecoderLoaded: false

    Process {
        id: loadProcess
        command: ["cat", Quickshell.env("HOME") + "/.cache/caelestia/pauseOnBattery.txt"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.pauseOnBattery = (data.trim() === "true");
                root._loaded = true;
                recalcTimer.restart();
            }
        }
        onExited: {
            if (!root._loaded) {
                root._loaded = true;
                recalcTimer.restart();
            }
        }
    }

    Process {
        id: saveProcess
    }

    Process {
        id: loadWindowProcess
        command: ["cat", Quickshell.env("HOME") + "/.cache/caelestia/pauseOnWindowOverlap.txt"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.pauseOnWindowOverlap = (data.trim() !== "false");
                root._windowLoaded = true;
                recalcTimer.restart();
            }
        }
        onExited: {
            if (!root._windowLoaded) {
                root._windowLoaded = true;
                recalcTimer.restart();
            }
        }
    }

    Process {
        id: saveWindowProcess
    }

    Process {
        id: loadHwDecoderProcess
        command: ["cat", Quickshell.env("HOME") + "/.cache/caelestia/hwDecoder.txt"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const text = data.trim();
                if (text) root.hwDecoder = text;
                root._hwDecoderLoaded = true;
            }
        }
        onExited: {
            if (!root._hwDecoderLoaded) {
                root._hwDecoderLoaded = true;
            }
        }
    }

    Process {
        id: saveHwDecoderProcess
    }

    function saveSetting() {
        saveProcess.command = ["sh", "-c", "echo '" + root.pauseOnBattery + "' > ~/.cache/caelestia/pauseOnBattery.txt"];
        saveProcess.running = true;
    }

    function saveWindowSetting() {
        saveWindowProcess.command = ["sh", "-c", "echo '" + root.pauseOnWindowOverlap + "' > ~/.cache/caelestia/pauseOnWindowOverlap.txt"];
        saveWindowProcess.running = true;
    }

    function saveHwDecoderSetting() {
        saveHwDecoderProcess.command = ["sh", "-c", "echo '" + root.hwDecoder + "' > ~/.cache/caelestia/hwDecoder.txt && nohup sh -c 'sleep 0.5 && caelestia shell -d' >/dev/null 2>&1 & caelestia shell -k"];
        saveHwDecoderProcess.running = true;
    }

    function recalculate() {
        if (!_loaded)
            return;

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
                    const monitor = Hyprland.focusedMonitor;
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

    Timer {
        id: recalcTimer
        interval: 150
        onTriggered: root.recalculate()
    }

    onPauseOnBatteryChanged: {
        if (_loaded) {
            saveSetting();
            recalculate();
        }
    }

    onPauseOnWindowOverlapChanged: {
        if (_windowLoaded) {
            saveWindowSetting();
            recalculate();
        }
    }

    onHwDecoderChanged: {
        if (_hwDecoderLoaded) {
            saveHwDecoderSetting();
        }
    }
}
