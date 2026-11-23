import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        let text = "SELF-TEST FAILED: \(message)\n"
        FileHandle.standardError.write(Data(text.utf8))
        exit(1)
    }
}

func approx(_ a: Double, _ b: Double, tolerance: Double = 0.000_001) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: - Exact 64-page cut-stack contract

let full = MiniBookImposition.makePlan(bookPageCount: 64)
require(full.count == 8, "64 book pages must produce exactly 8 physical Letter sheets")

let expectedFront: [[Int]] = [
    [1, 17, 33, 49],
    [3, 19, 35, 51],
    [5, 21, 37, 53],
    [7, 23, 39, 55],
    [9, 25, 41, 57],
    [11, 27, 43, 59],
    [13, 29, 45, 61],
    [15, 31, 47, 63]
]

let expectedBack: [[Int]] = [
    [18, 2, 50, 34],
    [20, 4, 52, 36],
    [22, 6, 54, 38],
    [24, 8, 56, 40],
    [26, 10, 58, 42],
    [28, 12, 60, 44],
    [30, 14, 62, 46],
    [32, 16, 64, 48]
]

for i in 0..<8 {
    let front = full[i].front.map { $0.map { $0 + 1 } }
    let back = full[i].back.map { $0.map { $0 + 1 } }
    require(front == expectedFront[i].map(Optional.some), "sheet \(i + 1) front mismatch: \(front)")
    require(back == expectedBack[i].map(Optional.some), "sheet \(i + 1) back mismatch: \(back)")
}

require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 0, bookPageCount: 64) == "Pages 1–16", "pile A must be pages 1–16")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 1, bookPageCount: 64) == "Pages 17–32", "pile B must be pages 17–32")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 2, bookPageCount: 64) == "Pages 33–48", "pile C must be pages 33–48")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 3, bookPageCount: 64) == "Pages 49–64", "pile D must be pages 49–64")

// MARK: - Partial final batches use only the needed sheets

let forty = MiniBookImposition.makePlan(bookPageCount: 40)
require(forty.count == 5, "40 book pages / 20 leaves should require only 5 sheets")
require(forty[0].front.map { $0.map { $0 + 1 } } == [1, 11, 21, 31].map(Optional.some), "40-page first sheet front should be 1,11,21,31")
require(forty[0].back.map { $0.map { $0 + 1 } } == [12, 2, 32, 22].map(Optional.some), "40-page first sheet back should be 12,2,32,22")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 0, bookPageCount: 40) == "Pages 1–10", "40-page pile A")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 1, bookPageCount: 40) == "Pages 11–20", "40-page pile B")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 2, bookPageCount: 40) == "Pages 21–30", "40-page pile C")
require(MiniBookImposition.bookPageRangeTextForPile(batchIndex: 0, pilePosition: 3, bookPageCount: 40) == "Pages 31–40", "40-page pile D")

// MARK: - Multiple batches restart the cut-stack pattern correctly

let oneTwentyEight = MiniBookImposition.makePlan(bookPageCount: 128)
require(oneTwentyEight.count == 16, "128 pages should produce 16 physical sheets")
require(oneTwentyEight[8].front.map { $0.map { $0 + 1 } } == [65, 81, 97, 113].map(Optional.some), "batch 2 sheet 1 front must be 65,81,97,113")
require(oneTwentyEight[8].back.map { $0.map { $0 + 1 } } == [82, 66, 114, 98].map(Optional.some), "batch 2 sheet 1 back must be 82,66,114,98")

// MARK: - Exhaustive imposition validation

for count in 1...513 {
    let plan = MiniBookImposition.makePlan(bookPageCount: count)
    let validation = MiniBookImposition.validate(plan: plan, bookPageCount: count)
    require(validation.isValid, "imposition validation failed for \(count) pages: \(validation.message)")

    let all = plan.flatMap { ($0.front + $0.back).compactMap { $0 } }.sorted()
    require(all == Array(0..<count), "every logical page must appear exactly once for \(count) pages")

    // Every front leaf must pair with the next logical page on the mirrored back tile.
    for sheet in plan {
        for frontPosition in 0..<4 {
            guard let f = sheet.front[frontPosition] else { continue }
            let backPosition = MiniBookImposition.longEdgeReversePosition[frontPosition]
            let b = sheet.back[backPosition]
            if f + 1 < count {
                require(b == f + 1, "front/back physical leaf mismatch for \(count) pages")
            } else {
                require(b == nil, "last unmatched page should have blank back")
            }
        }
    }
}

// MARK: - Adaptive 1-inch ring punch geometry

var settings = BindingGuideSettings()
settings.enabled = true
settings.ringDiameterInches = 1.0
settings.targetDiameterInches = 0.10
settings.bindingEdgeInsetInches = 0.375
settings.thicknessMode = .estimated
settings.paperCaliperInches = 0.004

let pageCount = 200
let leaves = MiniBookImposition.physicalLeafCount(forBookPageCount: pageCount)
require(leaves == 100, "200 logical pages must produce 100 physical leaves")
let bindingValidation = AdaptivePunchGeometry.validate(bookPageCount: pageCount, settings: settings)
require(bindingValidation.isValid, "default 200-page binding geometry must validate: \(bindingValidation.message)")

let firstSpacing = AdaptivePunchGeometry.holeSpacingInches(leafIndex: 0, totalLeaves: leaves, settings: settings)!
let middleSpacing1 = AdaptivePunchGeometry.holeSpacingInches(leafIndex: 49, totalLeaves: leaves, settings: settings)!
let middleSpacing2 = AdaptivePunchGeometry.holeSpacingInches(leafIndex: 50, totalLeaves: leaves, settings: settings)!
let lastSpacing = AdaptivePunchGeometry.holeSpacingInches(leafIndex: 99, totalLeaves: leaves, settings: settings)!

require(firstSpacing < middleSpacing1, "first leaf holes must be closer than middle leaf holes")
require(lastSpacing < middleSpacing2, "last leaf holes must be closer than middle leaf holes")
require(approx(firstSpacing, lastSpacing), "first and last leaf spacing must be symmetric")
require(approx(middleSpacing1, middleSpacing2), "two center leaves must be symmetric")
require(abs(middleSpacing1 - 1.0) < 0.0001, "middle spacing should round to 1.000 inch for a 1-inch ring")

let middleTargets = AdaptivePunchGeometry.targetYFromTopInches(leafIndex: 49, totalLeaves: leaves, settings: settings)!
require(abs(middleTargets[0] - 1.0) < 0.001, "middle upper target 1 should be approximately 1.00 inch from top")
require(abs(middleTargets[1] - 2.0) < 0.001, "middle upper target 2 should be approximately 2.00 inches from top")
require(abs(middleTargets[2] - 3.5) < 0.001, "middle lower target 1 should be approximately 3.50 inches from top")
require(abs(middleTargets[3] - 4.5) < 0.001, "middle lower target 2 should be approximately 4.50 inches from top")

require(AdaptivePunchGeometry.bindingEdge(forLogicalPageIndex: 0) == .left, "leaf front punch guides must be on the left edge")
require(AdaptivePunchGeometry.bindingEdge(forLogicalPageIndex: 1) == .right, "leaf back punch guides must mirror to the right edge for physical alignment")
require(AdaptivePunchGeometry.physicalLeafIndex(forLogicalPageIndex: 0) == AdaptivePunchGeometry.physicalLeafIndex(forLogicalPageIndex: 1), "pages 1/2 must share one physical leaf")
require(AdaptivePunchGeometry.physicalLeafIndex(forLogicalPageIndex: 98) == AdaptivePunchGeometry.physicalLeafIndex(forLogicalPageIndex: 99), "pages 99/100 must share one physical leaf")

// Impossible ring geometry must block export.
var tooSmallRing = settings
tooSmallRing.ringDiameterInches = 0.30
let impossible = AdaptivePunchGeometry.validate(bookPageCount: pageCount, settings: tooSmallRing)
require(!impossible.isValid, "ring smaller than the stack thickness must be rejected")

print("✓ 64-page cut-stack order: sheet 1 front 1,17,33,49 / back 18,2,50,34")
print("✓ Sheet 8: front 15,31,47,63 / back 32,16,64,48")
print("✓ Cut piles A/B/C/D = 1–16 / 17–32 / 33–48 / 49–64")
print("✓ Partial final batches use only the physical sheets they need")
print("✓ Cut-stack + long-edge pairing validated for page counts 1...513")
print("✓ 200-page / 100-leaf adaptive 1-inch ring geometry validated")
print(String(format: "✓ Punch spacing first %.3f in • middle %.3f in • last %.3f in", firstSpacing, middleSpacing1, lastSpacing))
print("✓ Front/back punch targets share physical holes by left/right mirroring")
