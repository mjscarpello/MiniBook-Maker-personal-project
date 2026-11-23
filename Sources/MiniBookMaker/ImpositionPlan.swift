import Foundation

enum MiniBookSheetSide: String, CaseIterable, Identifiable {
    case front = "Front"
    case back = "Back"

    var id: String { rawValue }
}

enum MiniBookTilePosition: Int, CaseIterable, Identifiable {
    case topLeft = 0
    case topRight = 1
    case bottomLeft = 2
    case bottomRight = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var pileLetter: String {
        switch self {
        case .topLeft: return "A"
        case .topRight: return "B"
        case .bottomLeft: return "C"
        case .bottomRight: return "D"
        }
    }
}

/// One physical US Letter sheet after cut-stack duplex imposition.
///
/// The values are ZERO-BASED indices into the logical `bookPages` reading-order
/// array. A nil value means that tile is intentionally blank.
struct PhysicalSheetPlan: Equatable, Identifiable {
    let sheetIndex: Int
    let batchIndex: Int
    let sheetIndexInBatch: Int
    let sheetsInBatch: Int
    let front: [Int?]
    let back: [Int?]

    var id: Int { sheetIndex }

    init(
        sheetIndex: Int,
        batchIndex: Int,
        sheetIndexInBatch: Int,
        sheetsInBatch: Int,
        front: [Int?],
        back: [Int?]
    ) {
        precondition(front.count == 4 && back.count == 4)
        self.sheetIndex = sheetIndex
        self.batchIndex = batchIndex
        self.sheetIndexInBatch = sheetIndexInBatch
        self.sheetsInBatch = sheetsInBatch
        self.front = front
        self.back = back
    }

    func indices(for side: MiniBookSheetSide) -> [Int?] {
        side == .front ? front : back
    }
}

struct CutBatchPlan: Equatable, Identifiable {
    let batchIndex: Int
    let firstLeafIndex: Int
    let leafCount: Int
    let sheetCount: Int
    let firstPhysicalSheetIndex: Int

    var id: Int { batchIndex }

    var leafRange: Range<Int> {
        firstLeafIndex..<(firstLeafIndex + leafCount)
    }
}

struct ImpositionValidationResult: Equatable {
    let isValid: Bool
    let message: String

    static let valid = ImpositionValidationResult(
        isValid: true,
        message: "Cut-stack duplex imposition verified."
    )
}

/// The ONLY component allowed to convert logical reading order into physical
/// printer order.
///
/// Manufacturing rule:
/// - One cutting batch contains at most 8 physical Letter sheets.
/// - One batch therefore contains at most 32 physical mini-book leaves / 64 logical pages.
/// - The four cut piles are contiguous reading-order ranges.
/// - For a full 64-page batch, front sheet 1 is 1,17,33,49 and back is 18,2,50,34.
/// - After all 8 sheets are cut together, pile A is pages 1-16, B 17-32,
///   C 33-48, and D 49-64. Stack A→B→C→D.
enum MiniBookImposition {
    static let maximumSheetsPerCutBatch = 8
    static let leavesPerPhysicalSheet = 4
    static let logicalPagesPerLeaf = 2
    static let maximumLeavesPerCutBatch = maximumSheetsPerCutBatch * leavesPerPhysicalSheet // 32
    static let maximumLogicalPagesPerCutBatch = maximumLeavesPerCutBatch * logicalPagesPerLeaf // 64

    /// With portrait long-edge duplex printing, the reverse of front TL is back
    /// TR, front TR is back TL, front BL is back BR, and front BR is back BL.
    static let longEdgeReversePosition = [1, 0, 3, 2]

    static func physicalLeafCount(forBookPageCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + 1) / 2
    }

    static func physicalSheetCount(forBookPageCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (physicalLeafCount(forBookPageCount: count) + leavesPerPhysicalSheet - 1) / leavesPerPhysicalSheet
    }

    static func cutBatchCount(forBookPageCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (physicalLeafCount(forBookPageCount: count) + maximumLeavesPerCutBatch - 1) / maximumLeavesPerCutBatch
    }

    static func makeBatches(bookPageCount: Int) -> [CutBatchPlan] {
        let totalLeaves = physicalLeafCount(forBookPageCount: bookPageCount)
        guard totalLeaves > 0 else { return [] }

        var result: [CutBatchPlan] = []
        var firstLeaf = 0
        var firstSheet = 0
        var batchIndex = 0

        while firstLeaf < totalLeaves {
            let leafCount = min(maximumLeavesPerCutBatch, totalLeaves - firstLeaf)
            let sheetCount = (leafCount + leavesPerPhysicalSheet - 1) / leavesPerPhysicalSheet
            result.append(
                CutBatchPlan(
                    batchIndex: batchIndex,
                    firstLeafIndex: firstLeaf,
                    leafCount: leafCount,
                    sheetCount: sheetCount,
                    firstPhysicalSheetIndex: firstSheet
                )
            )
            firstLeaf += leafCount
            firstSheet += sheetCount
            batchIndex += 1
        }

        return result
    }

    static func makePlan(bookPageCount: Int) -> [PhysicalSheetPlan] {
        guard bookPageCount > 0 else { return [] }

        var result: [PhysicalSheetPlan] = []
        result.reserveCapacity(physicalSheetCount(forBookPageCount: bookPageCount))

        for batch in makeBatches(bookPageCount: bookPageCount) {
            // Each quadrant/pile contains up to `m` physical leaves, where m is
            // the number of Letter sheets in this cutting batch.
            let m = batch.sheetCount
            let batchLeafEnd = batch.firstLeafIndex + batch.leafCount

            for i in 0..<m {
                let candidateLeaves: [Int] = [
                    batch.firstLeafIndex + i,          // pile A / front TL
                    batch.firstLeafIndex + m + i,      // pile B / front TR
                    batch.firstLeafIndex + 2 * m + i,  // pile C / front BL
                    batch.firstLeafIndex + 3 * m + i   // pile D / front BR
                ]

                let frontLeaves: [Int?] = candidateLeaves.map { leaf in
                    leaf < batchLeafEnd ? leaf : nil
                }

                let front = frontLeaves.map { leaf -> Int? in
                    guard let leaf else { return nil }
                    let logicalIndex = leaf * logicalPagesPerLeaf
                    return logicalIndex < bookPageCount ? logicalIndex : nil
                }

                // Back positions are horizontally mirrored so each leaf's even
                // page lands physically behind its odd page with long-edge duplex.
                var back = Array<Int?>(repeating: nil, count: 4)
                for frontPosition in 0..<4 {
                    guard let leaf = frontLeaves[frontPosition] else { continue }
                    let backLogicalIndex = leaf * logicalPagesPerLeaf + 1
                    let backPosition = longEdgeReversePosition[frontPosition]
                    back[backPosition] = backLogicalIndex < bookPageCount ? backLogicalIndex : nil
                }

                result.append(
                    PhysicalSheetPlan(
                        sheetIndex: result.count,
                        batchIndex: batch.batchIndex,
                        sheetIndexInBatch: i,
                        sheetsInBatch: m,
                        front: front,
                        back: back
                    )
                )
            }
        }

        return result
    }

    static func validatedPlan(bookPageCount: Int) throws -> [PhysicalSheetPlan] {
        let plan = makePlan(bookPageCount: bookPageCount)
        let validation = validate(plan: plan, bookPageCount: bookPageCount)
        guard validation.isValid else {
            throw ImpositionPlanError.invalid(validation.message)
        }
        return plan
    }

    static func validate(plan: [PhysicalSheetPlan], bookPageCount: Int) -> ImpositionValidationResult {
        let expectedSheetCount = physicalSheetCount(forBookPageCount: bookPageCount)
        guard plan.count == expectedSheetCount else {
            return invalid("Expected \(expectedSheetCount) physical sheets but received \(plan.count).")
        }

        guard longEdgeReversePosition == [1, 0, 3, 2] else {
            return invalid("Long-edge reverse-position mapping changed.")
        }

        let batches = makeBatches(bookPageCount: bookPageCount)

        for (sheetIndex, sheet) in plan.enumerated() {
            guard sheet.sheetIndex == sheetIndex else {
                return invalid("Physical sheet indices are out of order.")
            }
            guard batches.indices.contains(sheet.batchIndex) else {
                return invalid("Sheet \(sheetIndex + 1) references an invalid cutting batch.")
            }
            let batch = batches[sheet.batchIndex]
            guard sheet.sheetsInBatch == batch.sheetCount,
                  sheet.sheetIndexInBatch >= 0,
                  sheet.sheetIndexInBatch < batch.sheetCount else {
                return invalid("Sheet \(sheetIndex + 1) has incorrect cutting-batch metadata.")
            }

            // Every nonblank front must be an odd-numbered logical book page
            // (zero-based even index), and its paired back must be the next page.
            for frontPosition in 0..<4 {
                guard let frontIndex = sheet.front[frontPosition] else { continue }
                guard frontIndex % 2 == 0 else {
                    return invalid("Sheet \(sheetIndex + 1) front contains an even-numbered book page.")
                }

                let reversePosition = longEdgeReversePosition[frontPosition]
                let backIndex = sheet.back[reversePosition]
                if frontIndex + 1 < bookPageCount {
                    guard backIndex == frontIndex + 1 else {
                        return invalid("Sheet \(sheetIndex + 1) does not pair book pages \(frontIndex + 1)/\(frontIndex + 2) after long-edge duplexing.")
                    }
                } else if backIndex != nil {
                    return invalid("The final unmatched front page must have a blank reverse.")
                }
            }
        }

        // Every logical page must appear exactly once in the whole exported plan.
        let all = plan.flatMap { ($0.front + $0.back).compactMap { $0 } }
        guard all.count == bookPageCount else {
            return invalid("The physical plan contains \(all.count) placed pages for a \(bookPageCount)-page book.")
        }
        guard Set(all).count == all.count else {
            return invalid("A logical book page is duplicated in the physical plan.")
        }
        guard all.sorted() == Array(0..<bookPageCount) else {
            return invalid("At least one logical book page is missing from the physical plan.")
        }

        // Prove the cut-stack property for every batch. Each pile must contain a
        // contiguous run of physical leaves so the user can stack A→B→C→D without sorting.
        for batch in batches {
            let batchSheets = plan.filter { $0.batchIndex == batch.batchIndex }
            guard batchSheets.count == batch.sheetCount else {
                return invalid("Cutting batch \(batch.batchIndex + 1) has the wrong number of sheets.")
            }

            for pilePosition in 0..<4 {
                let expectedStart = batch.firstLeafIndex + pilePosition * batch.sheetCount
                let expectedEnd = min(expectedStart + batch.sheetCount, batch.firstLeafIndex + batch.leafCount)
                let expectedLeaves = expectedStart < expectedEnd ? Array(expectedStart..<expectedEnd) : []

                let actualLeaves = batchSheets.compactMap { sheet -> Int? in
                    guard let frontIndex = sheet.front[pilePosition] else { return nil }
                    return frontIndex / logicalPagesPerLeaf
                }

                guard actualLeaves == expectedLeaves else {
                    return invalid("Cutting batch \(batch.batchIndex + 1), pile \(MiniBookTilePosition(rawValue: pilePosition)?.pileLetter ?? "?") is not a contiguous reading-order leaf stack.")
                }
            }
        }

        // Exact full-batch contract requested by the user.
        if bookPageCount >= 64 {
            let firstEight = Array(plan.prefix(8))
            guard firstEight.count == 8 else { return invalid("A 64-page batch must contain 8 physical sheets.") }
            guard firstEight[0].front == [0, 16, 32, 48] else {
                return invalid("Sheet 1 front must be book pages 1,17,33,49.")
            }
            guard firstEight[0].back == [17, 1, 49, 33] else {
                return invalid("Sheet 1 back must be book pages 18,2,50,34.")
            }
            guard firstEight[7].front == [14, 30, 46, 62] else {
                return invalid("Sheet 8 front must be book pages 15,31,47,63.")
            }
            guard firstEight[7].back == [31, 15, 63, 47] else {
                return invalid("Sheet 8 back must be book pages 32,16,64,48.")
            }
        }

        return .valid
    }

    static func displayedBookNumbers(
        sheetIndex: Int,
        side: MiniBookSheetSide,
        pageCount: Int
    ) -> [Int?] {
        let plan = makePlan(bookPageCount: pageCount)
        guard plan.indices.contains(sheetIndex) else { return [nil, nil, nil, nil] }
        return plan[sheetIndex].indices(for: side).map { $0.map { $0 + 1 } }
    }

    static func batchForPhysicalSheet(sheetIndex: Int, bookPageCount: Int) -> CutBatchPlan? {
        guard sheetIndex >= 0 else { return nil }
        return makeBatches(bookPageCount: bookPageCount).first { batch in
            sheetIndex >= batch.firstPhysicalSheetIndex &&
            sheetIndex < batch.firstPhysicalSheetIndex + batch.sheetCount
        }
    }

    /// Returns the ZERO-BASED physical leaf indices in one cut pile.
    static func leafIndicesForPile(
        batchIndex: Int,
        pilePosition: Int,
        bookPageCount: Int
    ) -> [Int] {
        let batches = makeBatches(bookPageCount: bookPageCount)
        guard batches.indices.contains(batchIndex), (0..<4).contains(pilePosition) else { return [] }
        let batch = batches[batchIndex]
        let start = batch.firstLeafIndex + pilePosition * batch.sheetCount
        let end = min(start + batch.sheetCount, batch.firstLeafIndex + batch.leafCount)
        guard start < end else { return [] }
        return Array(start..<end)
    }

    static func bookPageRangeTextForPile(
        batchIndex: Int,
        pilePosition: Int,
        bookPageCount: Int
    ) -> String {
        let leaves = leafIndicesForPile(batchIndex: batchIndex, pilePosition: pilePosition, bookPageCount: bookPageCount)
        guard let firstLeaf = leaves.first, let lastLeaf = leaves.last else { return "Blank" }
        let firstPage = firstLeaf * 2 + 1
        let lastPage = min(bookPageCount, lastLeaf * 2 + 2)
        return firstPage == lastPage ? "Page \(firstPage)" : "Pages \(firstPage)–\(lastPage)"
    }

    private static func invalid(_ message: String) -> ImpositionValidationResult {
        ImpositionValidationResult(isValid: false, message: message)
    }
}

enum ImpositionPlanError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return "Cut-stack duplex imposition validation failed: \(message)"
        }
    }
}
