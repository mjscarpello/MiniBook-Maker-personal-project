# Repository verification

The original standalone regression suite was compiled and run successfully in a Linux environment during repository preparation. Native macOS build, GUI and physical prints were not rerun.

```text
Swift version 6.2.1 (swift-6.2.1-RELEASE)
Target: x86_64-unknown-linux-gnu
✓ 64-page cut-stack order: sheet 1 front 1,17,33,49 / back 18,2,50,34
✓ Sheet 8: front 15,31,47,63 / back 32,16,64,48
✓ Cut piles A/B/C/D = 1–16 / 17–32 / 33–48 / 49–64
✓ Partial final batches use only the physical sheets they need
✓ Cut-stack + long-edge pairing validated for page counts 1...513
✓ 200-page / 100-leaf adaptive 1-inch ring geometry validated
✓ Punch spacing first 0.918 in • middle 1.000 in • last 0.918 in
✓ Front/back punch targets share physical holes by left/right mirroring

```
