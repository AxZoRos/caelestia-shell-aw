import QtQuick
import QtMultimedia

// Lightweight single-stream video wallpaper renderer with explicit VRAM deallocation logic.
Item {
    id: root

    property url videoSource
    property bool autoStart: true
    property bool _isDestroying: false

    readonly property alias playbackState: player.playbackState
    readonly property alias mediaStatus: player.mediaStatus
    readonly property alias error: player.error
    readonly property alias errorString: player.errorString
    readonly property bool playing: !_isDestroying && playbackState === MediaPlayer.PlayingState
    readonly property bool hasError: !_isDestroying && (mediaStatus === MediaPlayer.InvalidMedia || error !== MediaPlayer.NoError)

    function play() {
        if (!_isDestroying && videoSource.toString())
            player.play();
    }

    function pause() {
        if (!_isDestroying)
            player.pause();
    }

    function stop() {
        player.stop();
    }

    anchors.fill: parent

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    MediaPlayer {
        id: player

        videoOutput: output
        audioOutput: null
        loops: MediaPlayer.Infinite
        autoPlay: false
        source: root.videoSource

        onErrorOccurred: (err, str) => {
            if (!root._isDestroying && err !== MediaPlayer.NoError)
                console.warn("[VideoWallpaper] MediaPlayer Error:", str);
        }

        onMediaStatusChanged: {
            if (root._isDestroying)
                return;
            if (mediaStatus === MediaPlayer.LoadedMedia && root.autoStart) {
                player.play();
            }
        }
    }

    Component.onCompleted: {
        if (videoSource.toString() && autoStart) {
            player.play();
        }
    }

    // Explicitly destroy stream context on component unmount to immediately release VRAM
    Component.onDestruction: {
        _isDestroying = true;
        player.stop();
    }
}
