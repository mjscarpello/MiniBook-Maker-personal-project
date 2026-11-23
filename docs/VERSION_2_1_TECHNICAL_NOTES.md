# MiniBook Maker 2.1

MiniBook Maker 2.1 is a native macOS app for turning PDFs into 4.25 × 5.5 inch ring-bound mini-books printed four-up on US Letter paper.

Version 2.1 changes the physical manufacturing workflow in two important ways:

1. **Cut-stack imposition:** up to 8 Letter sheets / 64 logical book pages are arranged so each quarter becomes an already-sorted pile after the stack is cut.
2. **Adaptive punch guides:** each physical mini-book leaf receives four 0.10-inch circular punch targets whose vertical spacing follows the geometry of the selected circular binder ring.

## 64-page cut-stack contract

For a full 8-sheet cutting batch, the physical sheets are:

| Sheet | Front TL | Front TR | Front BL | Front BR | Back TL | Back TR | Back BL | Back BR |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 17 | 33 | 49 | 18 | 2 | 50 | 34 |
| 2 | 3 | 19 | 35 | 51 | 20 | 4 | 52 | 36 |
| 3 | 5 | 21 | 37 | 53 | 22 | 6 | 54 | 38 |
| 4 | 7 | 23 | 39 | 55 | 24 | 8 | 56 | 40 |
| 5 | 9 | 25 | 41 | 57 | 26 | 10 | 58 | 42 |
| 6 | 11 | 27 | 43 | 59 | 28 | 12 | 60 | 44 |
| 7 | 13 | 29 | 45 | 61 | 30 | 14 | 62 | 46 |
| 8 | 15 | 31 | 47 | 63 | 32 | 16 | 64 | 48 |

Print portrait, **Two-Sided**, **Flip on Long Edge**, **100% / Actual Size**.

Keep all eight sheets aligned and cut the stack once vertically and once horizontally. The four cut piles are then:

- **Pile A / Top Left:** pages 1–16
- **Pile B / Top Right:** pages 17–32
- **Pile C / Bottom Left:** pages 33–48
- **Pile D / Bottom Right:** pages 49–64

Stack **A → B → C → D**. No individual page sorting is required.

The next full batch restarts the same pattern at page 65: sheet 1 of that batch is front 65,81,97,113 and back 82,66,114,98.

### Partial final batches

The app does not force blank sheets just to complete 64 pages. If a final batch needs fewer than eight Letter sheets, it recalculates the four contiguous piles using only the sheets required.

For example, a 40-page book uses five Letter sheets and produces cut piles 1–10, 11–20, 21–30, and 31–40.

## Adaptive ring punch guides

Each physical leaf consists of two logical pages:

- page 1 / page 2 = physical leaf 1
- page 3 / page 4 = physical leaf 2
- etc.

Both sides of one physical leaf use the same vertical punch geometry. The back-side targets are mirrored horizontally so the circles occupy the same physical holes after long-edge duplex printing.

Default binding settings:

- Ring diameter: **1.00 inch**
- Punch target circle: **0.10 inch diameter**
- Binding-edge inset: **0.375 inch**
- Upper ring center: **1.50 inches from the top**
- Lower ring center: **4.00 inches from the top**
- Estimated paper caliper: **0.004 inch per physical leaf**

For a 1-inch diameter ring, the app calculates each leaf's hole-pair spacing using the circular chord equation:

`spacing = 2 × sqrt(radius² - depth²)`

The middle leaves are widest, approximately 1.000 inch apart. The first and last leaves move inward symmetrically.

For a 200-page / 100-leaf book using the default 0.004-inch paper-caliper estimate, the regression test produces approximately:

- first leaf spacing: **0.918 in**
- middle leaf spacing: **1.000 in**
- last leaf spacing: **0.918 in**

At the middle leaf, the four target centers are approximately:

- 1.00 in from top
- 2.00 in from top
- 3.50 in from top
- 4.50 in from top

You can switch the Binding panel from **Estimated** thickness to **Measured** thickness and enter the actual finished stack thickness for greater accuracy.

If the finished stack is too thick for the selected ring diameter, export is blocked instead of producing impossible punch locations.

## Select & Arrange is separate

**Keep Reading Order** applies only inside Select & Arrange Pages. It determines the logical book sequence before printing. It never controls the physical cut-stack imposition.

The pipeline is:

1. Import source PDF
2. Interpret full pages / two-page spreads
3. Select and arrange logical reading order
4. Pair logical pages into physical leaves
5. Calculate adaptive punch geometry for each leaf
6. Group leaves into cutting batches of up to 32 leaves / 8 Letter sheets
7. Apply cut-stack duplex imposition
8. Export the validated PDF

## Build and install

After unzipping the project:

```bash
cd ~/Downloads/MiniBookMaker-v2.1
xattr -dr com.apple.quarantine .
chmod +x "Build MiniBook Maker.command"
./"Build MiniBook Maker.command"
```

The builder first runs the pure-Swift cut-stack and binding regression tests. If they pass, it builds the native macOS app, installs it at:

`~/Applications/MiniBook Maker 2.app`

and opens that exact newly built copy.

## Recommended first test

Use **Export → Export 64-Page Cut-Stack Calibration…**.

It creates eight duplex Letter sheets with large numbers 1–64. Print all eight sheets, keep them aligned, cut them into quarters, and verify:

- A = 1–16
- B = 17–32
- C = 33–48
- D = 49–64

Then stack A → B → C → D.

After that, use **Export First Cutting Batch…** with the actual book before committing to the complete export.
