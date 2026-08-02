pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import QtQuick.Effects
import M3Shapes
import qs.components
import qs.components.images
import qs.services

Item {
    id: root

    property string source: Wallpapers.current
    property Item current: null
    property bool completed: false
    property string settledSource: ""

    readonly property int sourceChangeDebounceMs: 80

    readonly property string currentSchemeName: (Colours.showPreview ? Colours["previewScheme"] : Colours.scheme) || ""
    readonly property string currentVariantName: (Colours.showPreview ? Colours["previewVariant"] : Colours.variant) || ""
    readonly property string currentFlavourName: (Colours.showPreview ? Colours["previewFlavour"] : Colours.flavour) || ""
    readonly property bool isDynamicScheme: root.currentSchemeName.startsWith("dynamic")
    readonly property bool isDynamicMonochrome: root.isDynamicScheme && root.currentVariantName === "monochrome"
    readonly property bool shouldRecolor: !!(Config.background && Config.background["wallpaperRecolor"]) && (!root.isDynamicScheme || root.isDynamicMonochrome)
    readonly property real hardFlavourContrastBoost: 0.45

    readonly property var shapes: [MaterialShape.Circle, MaterialShape.Square, MaterialShape.Diamond, MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Clover4Leaf, MaterialShape.SoftBurst, MaterialShape.Cookie6Sided]

    function toFileUrl(path) {
        if (!path)
            return "";
        const clean = String(path).trim();
        if (clean.startsWith("file://"))
            return clean;
        if (clean.startsWith("/"))
            return "file://" + clean;
        return Qt.resolvedUrl(clean);
    }

    function activateLayer(layer, path) {
        layer.path = path;
        layer.state = "active";
        root.current = layer;
    }

    // Coalesce rapid source changes during fast list scrolling
    Timer {
        id: coalesceTimer
        interval: root.sourceChangeDebounceMs
        repeat: false
        onTriggered: root.applySourceChange()
    }

    onSourceChanged: coalesceTimer.restart()

    function applySourceChange() {
        if (source === settledSource && root.current?.state === "active")
            return;

        settledSource = source;

        if (!settledSource) {
            one.state = "inactive";
            two.state = "inactive";
            root.current = null;
            return;
        }

        const prevLayer = root.current;
        const nextLayer = prevLayer === one ? two : one;

        if (nextLayer.state === "background")
            nextLayer.state = "inactive";
        if (prevLayer)
            prevLayer.state = "background";

        activateLayer(nextLayer, settledSource);
    }

    Component.onCompleted: {
        if (source) {
            settledSource = source;
            activateLayer(one, settledSource);
        }
        completed = true;
    }

    // Background placeholder for missing or empty wallpaper source
    Loader {
        asynchronous: true
        anchors.fill: parent
        active: root.completed && !root.source
        sourceComponent: StyledRect {
            color: (Colours.palette && Colours.palette.m3surfaceContainer) || "transparent"
        }
    }

    // Persistent fallback thumbnail preventing black screen glitches during async loads
    CachingImage {
        id: rootFallbackThumb
        anchors.fill: parent
        path: root.settledSource
        source: {
            if (!root.settledSource)
                return "";
            if (Wallpapers.isVideo(root.settledSource)) {
                const thumb = Wallpapers.getWallpaperThumb(root.settledSource, Wallpapers.cacheBuster);
                return typeof thumb === "string" ? thumb : "";
            }
            return root.settledSource;
        }
        asynchronous: true
        visible: path !== ""
    }

    Img {
        id: one
    }
    Img {
        id: two
    }

    // Layer component handling state transitions, recoloring effects, and Material reveal masks
    component Img: Item {
        id: img

        property string path: ""
        state: "inactive"

        readonly property bool isVideo: Wallpapers.isVideo(path)
        readonly property bool animsEnabled: !!Wallpapers.enableAnimation
        readonly property int fadeMs: 400
        readonly property int maskDurationMs: 2500
        readonly property int maskCleanupBufferMs: 100
        readonly property real maskCompletionEpsilon: 1.5
        readonly property int resumeDelayMs: 150

        property bool renderActive: false
        property bool pendingVideoAnim: false

        readonly property bool isPlayerPlaying: !!(videoChannelLoader.item?.playing)
        readonly property bool videoFailed: isVideo && !!(videoChannelLoader.item?.hasError)

        anchors.fill: parent
        opacity: 0

        onIsPlayerPlayingChanged: {
            if (isPlayerPlaying && pendingVideoAnim && animsEnabled && state === "active") {
                pendingVideoAnim = false;
                maskRadius = 0;
                maskAnim.restart();
            }
        }

        onVideoFailedChanged: {
            if (videoFailed && pendingVideoAnim && animsEnabled && state === "active") {
                pendingVideoAnim = false;
                maskRadius = 0;
                maskAnim.restart();
            }
        }

        Timer {
            id: cleanupTimer
            interval: (img.animsEnabled && root.completed) ? (img.maskDurationMs + img.maskCleanupBufferMs) : (img.fadeMs + 20)
            repeat: false
            onTriggered: img.state = "inactive"
        }

        states: [
            State {
                name: "active"
                PropertyChanges {
                    img.opacity: 1
                    img.z: 1
                    img.renderActive: true
                }
            },
            State {
                name: "background"
                PropertyChanges {
                    img.opacity: 1
                    img.z: 0
                    img.renderActive: true
                }
            },
            State {
                name: "inactive"
                PropertyChanges {
                    img.opacity: 0
                    img.z: 0
                    img.renderActive: false
                }
            }
        ]

        transitions: [
            Transition {
                from: "inactive"
                to: "active"
                enabled: root.completed
                NumberAnimation {
                    property: "opacity"
                    duration: img.fadeMs
                    easing.type: Easing.InOutQuad
                }
            }
        ]

        onStateChanged: {
            if (state === "active") {
                cleanupTimer.stop();
                if (animsEnabled && root.completed) {
                    if (isVideo) {
                        if (WallpaperPauser.paused) {
                            pendingVideoAnim = false;
                            maskRadius = 0;
                            maskAnim.restart();
                        } else {
                            pendingVideoAnim = true;
                            maskRadius = 0;
                        }
                    } else {
                        pendingVideoAnim = false;
                        maskRadius = 0;
                        maskAnim.restart();
                    }
                } else {
                    pendingVideoAnim = false;
                    maskRadius = maxRadius;
                }
            } else if (state === "background") {
                pendingVideoAnim = false;
                cleanupTimer.restart();
                if (animsEnabled) {
                    maskRadius = maxRadius;
                    currentShape = root.shapes[Math.floor(Math.random() * root.shapes.length)];
                }
            } else {
                pendingVideoAnim = false;
                cleanupTimer.stop();
            }
        }

        Loader {
            id: maskLoader
            anchors.fill: parent
            active: img.animsEnabled

            sourceComponent: Item {
                anchors.fill: parent
                readonly property Item maskSource: maskSourceItem

                Item {
                    id: maskWrapper
                    anchors.fill: parent
                    visible: img.needsMask
                    MaterialShape {
                        anchors.centerIn: parent
                        width: img.maxRadius * 2
                        height: img.maxRadius * 2
                        shape: img.currentShape
                        color: "white"
                        scale: img.maxRadius > 0 ? (img.maskRadius / img.maxRadius) : 0
                    }
                }

                ShaderEffectSource {
                    id: maskSourceItem
                    sourceItem: maskWrapper
                    anchors.fill: parent
                    hideSource: true
                    live: img.needsMask
                    visible: false
                }
            }
        }

        readonly property real maxRadius: Math.sqrt(width * width + height * height)
        property real maskRadius: 0
        property int currentShape: MaterialShape.Circle

        onMaxRadiusChanged: {
            if (!root.completed || (!maskAnim.running && (state === "active" || state === "background"))) {
                maskRadius = maxRadius;
            }
        }

        readonly property bool needsMask: animsEnabled && img.state === "active" && img.maskRadius < (img.maxRadius - img.maskCompletionEpsilon) && !!maskLoader.item

        Component.onCompleted: maskRadius = maxRadius

        Item {
            id: contentItem
            anchors.fill: parent

            // Offscreen Framebuffer Object (FBO) pass is strictly bound to active mask animations or recolor filters
            layer.enabled: img.needsMask || (root.shouldRecolor && img.renderActive)
            layer.effect: MultiEffect {
                maskEnabled: img.needsMask
                maskSource: maskLoader.item?.maskSource ?? null

                shadowEnabled: img.needsMask && !img.isVideo
                shadowColor: "black"
                shadowBlur: 1.0
                shadowVerticalOffset: 15
                shadowHorizontalOffset: 5

                saturation: (root.shouldRecolor && root.isDynamicMonochrome) ? -1 : 0
                colorization: (root.shouldRecolor && !root.isDynamicMonochrome) ? (Config.background ? Config.background["wallpaperRecolorStrength"] : 0) : 0
                colorizationColor: (Colours.palette && Colours.palette.m3primary) || "transparent"
                contrast: (root.shouldRecolor && root.currentFlavourName === "hard") ? root.hardFlavourContrastBoost : 0.0

                Behavior on saturation {
                    enabled: img.animsEnabled && img.state === "active"
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on colorization {
                    enabled: img.animsEnabled && img.state === "active"
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on contrast {
                    enabled: img.animsEnabled && img.state === "active"
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on colorizationColor {
                    enabled: img.animsEnabled && img.state === "active"
                    CAnim {}
                }
            }

            CachingImage {
                id: thumbImg
                anchors.fill: parent
                path: img.path
                source: {
                    if (!img.path)
                        return "";
                    if (img.isVideo) {
                        const thumb = Wallpapers.getWallpaperThumb(img.path, Wallpapers.cacheBuster);
                        return typeof thumb === "string" ? thumb : "";
                    }
                    return img.path;
                }

                visible: !img.isVideo || ((WallpaperPauser.paused || img.videoFailed) && !img.isPlayerPlaying)
                asynchronous: true

                onStatusChanged: {
                    if (status === Image.Ready && !img.isVideo && img.path === root.settledSource)
                        root.current = img;
                }
            }

            Loader {
                id: videoChannelLoader
                anchors.fill: parent
                asynchronous: true
                active: img.isVideo && img.path !== "" && img.renderActive
                source: "VideoWallpaper.qml"

                Timer {
                    id: resumeTimer
                    interval: img.resumeDelayMs
                    repeat: false
                    onTriggered: {
                        if (videoChannelLoader.item && img.isVideo && !WallpaperPauser.paused && img.state === "active") {
                            videoChannelLoader.item.play();
                        }
                    }
                }

                Connections {
                    target: WallpaperPauser
                    ignoreUnknownSignals: true
                    enabled: img.isVideo && videoChannelLoader.active

                    function onPausedChanged() {
                        if (!videoChannelLoader.item || !img.isVideo)
                            return;
                        if (WallpaperPauser.paused) {
                            resumeTimer.stop();
                            videoChannelLoader.item.pause();
                        } else if (img.state === "active") {
                            resumeTimer.restart();
                        }
                    }
                }

                onLoaded: {
                    if (item && img.path !== "") {
                        item.videoSource = root.toFileUrl(img.path);
                        item.autoStart = !WallpaperPauser.paused;
                    }
                }
            }
        }

        Anim {
            id: maskAnim
            target: img
            property: "maskRadius"
            from: 0
            to: img.maxRadius
            type: Anim.Emphasized
            duration: img.maskDurationMs
        }
    }
}
