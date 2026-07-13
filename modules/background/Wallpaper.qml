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

    function toFileUrl(path) {
        if (!path || path === "undefined") return "";
        const clean = String(path).trim();
        if (clean.indexOf("file://") === 0) return clean;
        if (clean[0] === "/") return "file://" + clean;
        return Qt.resolvedUrl(clean);
    }

    onSourceChanged: {
        if (!source) {
            one.state = "inactive";
            two.state = "inactive";
            current = null;
            return;
        }

        let nextLayer = null;
        let prevLayer = null;

        if (one.state === "active") {
            prevLayer = one;
            nextLayer = two;
        } else if (two.state === "active") {
            prevLayer = two;
            nextLayer = one;
        } else {
            prevLayer = null;
            nextLayer = one;
        }

        if (nextLayer.state === "background") {
            nextLayer.state = "inactive";
        }

        if (prevLayer) {
            prevLayer.state = "background";
        }

        nextLayer.path = source;
        nextLayer.state = "active";
        root.current = nextLayer;
    }

    Component.onCompleted: {
        if (source) {
            one.path = source;
            one.state = "active";
            root.current = one;
            completed = true;
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
        state: "inactive" 
        
        readonly property bool isVideo: Wallpapers.isVideo(path)
        readonly property bool animsEnabled: !!Wallpapers.enableAnimation
        readonly property string verifiedPath: (path && path !== "undefined") ? path : ""

        property bool renderActive: false

        anchors.fill: parent
        opacity: 0 

        Timer {
            id: cleanupTimer
            interval: 420 
            repeat: false
            onTriggered: img.state = "inactive"
        }

        states: [
            State {
                name: "active"
                PropertyChanges { target: img; opacity: 1; z: 1; renderActive: true }
            },
            State {
                name: "background"
                PropertyChanges { target: img; opacity: 1; z: 0; renderActive: true }
            },
            State {
                name: "inactive"
                PropertyChanges { target: img; opacity: 0; z: 0; renderActive: false }
            }
        ]

        transitions: [
            Transition {
                from: "inactive"; to: "active"
                enabled: root.completed
                NumberAnimation { property: "opacity"; duration: 400; easing.type: Easing.InOutQuad }
            }
        ]

        onStateChanged: {
            if (state === "active") {
                cleanupTimer.stop();
                if (animsEnabled && root.completed) {
                    maskRadius = 0;
                    maskAnim.restart();
                } else {
                    maskRadius = maxRadius;
                }
            } else if (state === "background") {
                cleanupTimer.restart(); 
                if (animsEnabled) {
                    maskRadius = maxRadius;
                    currentShape = shapes[Math.floor(Math.random() * shapes.length)];
                }
            } else {
                cleanupTimer.stop();
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

        readonly property var shapes: [
            MaterialShape.Circle, MaterialShape.Square, MaterialShape.Diamond,
            MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem,
            MaterialShape.Clover4Leaf, MaterialShape.SoftBurst, MaterialShape.Cookie6Sided
        ]

        readonly property bool needsMask: animsEnabled && img.z === 1 && img.maskRadius < img.maxRadius

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

            layer.enabled: img.needsMask || (img.shouldRecolor && img.renderActive)
            layer.effect: MultiEffect {
                maskEnabled: img.needsMask
                maskSource: maskSourceItem

                shadowEnabled: img.needsMask && !img.isVideo
                shadowColor: "black"; shadowBlur: 1.0; shadowVerticalOffset: 15; shadowHorizontalOffset: 5

                saturation: (img.shouldRecolor && img.isDynamicMonochrome) ? -1 : 0
                colorization: (img.shouldRecolor && !img.isDynamicMonochrome) ? Config.background.wallpaperRecolorStrength : 0
                colorizationColor: Colours.palette.m3primary ?? "transparent"
                
                readonly property string currentFlavourName: (Colours.showPreview ? Colours.previewFlavour : Colours.flavour) ?? ""
                contrast: (img.shouldRecolor && currentFlavourName === "hard") ? 0.45 : 0.0

                Behavior on saturation { enabled: img.state === "active"; Anim { type: Anim.DefaultEffects } }
                Behavior on colorization { enabled: img.state === "active"; Anim { type: Anim.DefaultEffects } }
                Behavior on contrast { enabled: img.state === "active"; Anim { type: Anim.DefaultEffects } }
                Behavior on colorizationColor { enabled: img.state === "active"; CAnim {} }
            }

            CachingImage {
                anchors.fill: parent
                path: img.verifiedPath
                source: (img.verifiedPath !== "") ? (img.isVideo ? (Wallpapers.getWallpaperThumb(img.verifiedPath, Wallpapers.cacheBuster) ?? "") : img.verifiedPath) : ""
                visible: !img.isVideo || !videoChannelLoader.item || !videoChannelLoader.item.playing
                asynchronous: true
                onStatusChanged: {
                    if (status === Image.Ready && !img.isVideo && img.verifiedPath === root.source)
                        root.current = img;
                }
            }

            Loader {
                id: videoChannelLoader
                anchors.fill: parent
                asynchronous: true
                
                active: img.isVideo && img.verifiedPath !== "" && img.renderActive
                source: "VideoWallpaper.qml"

                Connections {
                    target: WallpaperPauser
                    ignoreUnknownSignals: true
                    function onPausedChanged() {
                        if (videoChannelLoader.item && img.isVideo) {
                            if (WallpaperPauser.paused) {
                                videoChannelLoader.item.pause();
                            } else {
                                if (img.state === "active") {
                                    videoChannelLoader.item.play();
                                }
                            }
                        }
                    }
                }

                onLoaded: {
                    if (item && img.verifiedPath !== "") {
                        item.videoSource = root.toFileUrl(img.verifiedPath);
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
            duration: 2500
        }
    }
}
