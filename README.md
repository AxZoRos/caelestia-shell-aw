<h1 align=center>Caelestia-AW (Animated Wallpapers)</h1>

<div align=center>
  <b>A feature addition fork of the Caelestia Desktop Shell</b>
</div>

<br>

This repository is a customized fork of the original [caelestia-shell](https://github.com/caelestia-dots/shell) that natively implements full animated video wallpaper support along with several UI and QoL enhancements for managing your backgrounds.

## ✨ Features Added in this Fork

*   **Native Video Wallpaper Support**: Replaces the static image renderer with a high-performance, hardware-accelerated QtMultimedia `VideoWallpaper` component. Supports `.mp4`, `.webm`, and `.mkv`.
*   **Intelligent Pauser Service**: Automatically pauses the animated wallpaper to save CPU/GPU resources under the following conditions:
    *   When the system is running on battery power.
    *   When the current workspace has overlapping windows.
    *   *(Fully configurable through the Nexus settings panel)*
*   **Revamped Wallpaper UI Picker**: 
    *   The `WallpaperAndStyle` Nexus page now has dedicated tabs to easily switch between "Static" and "Animated" wallpaper directories.
    *   Added keyboard shortcuts: Use `Ctrl + Tab` to seamlessly toggle between the Static and Animated lists, and the `Up/Down` arrows to navigate the grid.
*   **High-Quality Thumbnails**: Generates full 720p thumbnails of your videos via FFmpeg, completely replacing the blurry 128x128 placeholders from the original version.

## 📥 Installation

Because this fork relies on backend changes to both the shell and the CLI, we provide a unified patcher script to automatically install these features over your existing Caelestia setup.

### Prerequisites

Ensure you have the base Caelestia dotfiles installed first. Then, run the patcher script to apply the Animated Wallpaper fork:

```bash
# Clone the patcher repository (if you have it)
git clone https://github.com/AdiAmbassador/caelestia-aw-installer.git
cd caelestia-aw-installer

# Run the patch installer
./patch.sh
```

*(The `patch.sh` script automatically fetches this repo, copies the patched QML files to `/etc/xdg/quickshell/caelestia/`, installs `qt6-multimedia`, updates your Hyprland env vars, and restarts the shell).*

## 🖼️ Usage

1.  Add your video files (`.mp4`, `.webm`, `.mkv`) to `~/Pictures/Wallpapers/Animated/`.
2.  Open the Caelestia Launcher and search for **"Wallpaper"**.
3.  Click the new **"Animated"** tab (or press `Ctrl+Tab`).
4.  Click the **Refresh** icon in the bottom right corner to generate your 720p thumbnails.
5.  Select a video to apply it!

---

> **Note:** This repository tracks the `shell` frontend. The companion CLI modifications that power the video thumbnail generation and color scheme extraction can be found in the [caelestia-cli-aw](https://github.com/AdiAmbassador/caelestia-cli-aw) repository.
