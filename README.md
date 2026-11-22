# Kalam

A quiet daily journal for macOS (SwiftUI, macOS 14+).

- `./build.sh`: build `build/Kalam.app` (signed with the local identity from `Scripts/make-signing.sh`)
- `./package.sh`: universal build plus `dist/Kalam-<version>.pkg`, `.dmg`, `.zip` and `How to Install.txt`

Data lives in `~/Library/Application Support/Kalam/library.json`. For testing, set
`KALAM_DATA_DIR=/some/folder` to use sample data, and `KALAM_SNAPSHOT=/path.png` to save a window snapshot after launch.
