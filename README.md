# Rig Viewer (native iOS)

This branch only holds the Rig Viewer app. It has nothing to do with the game on `main`.

- `RigViewer/` is the SwiftUI + SceneKit project (generated with XcodeGen).
- GitHub Actions builds an unsigned `RigViewer.ipa` on every push to this branch and publishes it to the `rig-viewer-builds` branch.
