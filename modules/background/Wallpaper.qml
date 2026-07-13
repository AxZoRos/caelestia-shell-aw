pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import QtQuick.Effects
import M3Shapes
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    property var current: null
    property bool completed

    readonly property bool sourceIsVideo: Wallpapers.isVideo(source)

    function toFileUrl(path) {
        const clean = String(path || "").trim();
        if (!clean) return "";
        if (clean.indexOf("file://") === 0) return clean;
        if (clean[0] === "/") return "file://" + clean;
        return Qt.resolvedUrl(clean).toString();
    }

    onSourceChanged: {
        if (!source) {
            current = null;
            return;
        }

        if (current === one)
            two.update();
        else
            one.update();
    }

    Component.onCompleted: {
        if (source) {
            Qt.callLater(() => {
                one.update();
                completed = true;
            });
        } else {
            completed = true;
        }
    }

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: root.completed && !root.source
        sourceComponent: StyledRect { color: Colours.palette.m3surfaceContainer }
    }

    Img { id: one }
    Img { id: two }

    component Img: Item {
        id: img

        property string path: ""
        readonly property bool isVideo: Wallpapers.isVideo(path)
        readonly property bool animsEnabled: !!Wallpapers.enableAnimation

        // Resource Guard: controls delay cleaner for background structures
        property bool renderActive: true

        Timer {
            id: resourceCleanerTimer
            interval: 300 // Safe overhead margin covering fade timelines (250ms)
            repeat: false
            onTriggered: img.renderActive = false
        }

        // Hot reload pipeline management
        onPathChanged: {
            if (videoChannelLoader.item && isVideo && path !== "") {
                videoChannelLoader.item.autoStart = !WallpaperPauser.paused;
                videoChannelLoader.item.videoSource = root.toFileUrl(path);
                root.current = img;
            }
        }

        function update(): void {
            if (path === root.source) {
                root.current = this;
                return;
            }
            path = root.source;
        }

        anchors.fill: parent
        z: root.current === img ? 1 : 0
        
        // Leaf-over-leaf crossfade structure
        opacity: animsEnabled ? 1 : (root.current === img ? 1 : (root.current && root.current.opacity < 1 ? 1 : 0))

        Behavior on opacity {
            enabled: !img.animsEnabled && root.current === img
            NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
        }

        readonly property real maxRadius: Math.sqrt(width * width + height * height)
        property real maskRadius: 0
        property int currentShape: MaterialShape.Circle

        readonly property var shapes: [
            MaterialShape.Circle, MaterialShape.Square, MaterialShape.Diamond,
            MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem,
            MaterialShape.Clover4Leaf, MaterialShape.SoftBurst, MaterialShape.Cookie6Sided
        ]

        readonly property bool needsMask: animsEnabled && img.z === 1 && img.maskRadius < img.maxRadius

        onZChanged: {
            if (z === 1) {
                resourceCleanerTimer.stop();
                img.renderActive = true; // Instantly restore textures on wake-up
                if (animsEnabled) {
                    maskRadius = 0;
                    maskAnim.restart();
                }
            } else {
                resourceCleanerTimer.start(); // Trigger deferred resource unloader
                if (animsEnabled) {
                    maskRadius = maxRadius;
                    currentShape = shapes[Math.floor(Math.random() * shapes.length)];
                }
            }
        }
        Component.onCompleted: maskRadius = maxRadius

        Item {
            id: maskWrapper
            anchors.fill: parent
            visible: img.needsMask
            MaterialShape {
                anchors.centerIn: parent
                width: 2000; height: 2000
                shape: img.currentShape
                color: "white"
                scale: img.maxRadius > 0 ? (img.maskRadius * 2) / 2000 : 0
            }
        }

        ShaderEffectSource {
            id: maskSourceItem
            sourceItem: maskWrapper
            anchors.fill: parent
            hideSource: true
            live: img.needsMask
            visible: img.needsMask
        }

        readonly property string currentSchemeName: Colours.showPreview ? Colours.previewScheme : Colours.scheme
        readonly property string currentVariantName: Colours.showPreview ? Colours.previewVariant : Colours.variant
        readonly property bool isDynamicScheme: currentSchemeName.startsWith("dynamic")
        readonly property bool isDynamicMonochrome: isDynamicScheme && currentVariantName === "monochrome"
        readonly property bool shouldRecolor: Config.background.wallpaperRecolor && (!isDynamicScheme || isDynamicMonochrome)

        Item {
            id: contentItem
            anchors.fill: parent

            // GPU Fix: Completely cuts FBO context generation when the layer finishes fading out
            layer.enabled: img.needsMask || (img.shouldRecolor && img.renderActive)
            layer.effect: MultiEffect {
                maskEnabled: img.needsMask
                maskSource: maskSourceItem

                shadowEnabled: img.needsMask && !img.isVideo
                shadowColor: "black"; shadowBlur: 1.0; shadowVerticalOffset: 15; shadowHorizontalOffset: 5

                saturation: (img.shouldRecolor && img.isDynamicMonochrome) ? -1 : 0
                colorization: (img.shouldRecolor && !img.isDynamicMonochrome) ? Config.background.wallpaperRecolorStrength : 0
                colorizationColor: Colours.palette.m3primary
                
                readonly property string currentFlavourName: Colours.showPreview ? Colours.previewFlavour : Colours.flavour
                contrast: (img.shouldRecolor && currentFlavourName === "hard") ? 0.45 : 0.0

                Behavior on saturation { Anim { type: Anim.DefaultEffects } }
                Behavior on colorization { Anim { type: Anim.DefaultEffects } }
                Behavior on contrast { Anim { type: Anim.DefaultEffects } }
                Behavior on colorizationColor { CAnim {} }
            }

            CachingImage {
                anchors.fill: parent
                path: img.path || ""
                source: (img.path && img.path !== "") ? (img.isVideo ? (Wallpapers.getWallpaperThumb(img.path, Wallpapers.cacheBuster) || "") : (img.path || "")) : ""
                visible: !img.isVideo || !videoChannelLoader.item || !videoChannelLoader.item.playing
                asynchronous: true
                onStatusChanged: {
                    if (status === Image.Ready && !img.isVideo)
                        root.current = img;
                }
            }

            Loader {
                id: videoChannelLoader
                anchors.fill: parent
                asynchronous: true
                
                // Keep background context streaming until transition finishes, then kill immediately
                active: img.isVideo && img.path !== "" && (root.current === img || img.path === root.source || img.renderActive)
                source: "VideoWallpaper.qml"

                Connections {
                    target: WallpaperPauser
                    ignoreUnknownSignals: true
                    function onPausedChanged() {
                        if (videoChannelLoader.item && img.isVideo) {
                            if (WallpaperPauser.paused) {
                                videoChannelLoader.item.pause();
                            } else {
                                if (root.current === img) {
                                    videoChannelLoader.item.play();
                                }
                            }
                        }
                    }
                }

                onLoaded: {
                    if (img.path && img.path !== "") {
                        item.videoSource = root.toFileUrl(img.path);
                    }
                    item.autoStart = !WallpaperPauser.paused;
                    root.current = img;
                }
            }
        }

        // Heavy profile shape reveal animator
        Anim {
            id: maskAnim
            target: img
            property: "maskRadius"
            from: 0
            to: img.maxRadius
            type: Anim.Emphasized
            duration: 2500
        }
    }
}
