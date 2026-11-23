import Foundation

enum BindingThicknessMode: String, CaseIterable, Identifiable, Codable {
    case estimated = "Estimated"
    case measured = "Measured"

    var id: String { rawValue }
}

enum MiniBookBindingEdge: String, Codable {
    case left
    case right
}

struct BindingGuideSettings: Equatable, Codable {
    var enabled: Bool = true
    var ringDiameterInches: Double = 1.0
    var targetDiameterInches: Double = 0.10
    var bindingEdgeInsetInches: Double = 0.375

    // These centers produce the requested middle-leaf holes:
    // upper = 1.00 / 2.00 in, lower = 3.50 / 4.50 in.
    var upperRingCenterFromTopInches: Double = 1.50
    var lowerRingCenterFromTopInches: Double = 4.00

    var thicknessMode: BindingThicknessMode = .estimated
    var paperCaliperInches: Double = 0.004
    var measuredStackThicknessInches: Double = 0.40

    func resolvedStackThicknessInches(totalLeaves: Int) -> Double {
        guard totalLeaves > 0 else { return 0 }
        switch thicknessMode {
        case .estimated:
            return Double(totalLeaves) * max(0, paperCaliperInches)
        case .measured:
            return max(0, measuredStackThicknessInches)
        }
    }

    var cacheKey: String {
        [
            enabled ? "1" : "0",
            f(ringDiameterInches),
            f(targetDiameterInches),
            f(bindingEdgeInsetInches),
            f(upperRingCenterFromTopInches),
            f(lowerRingCenterFromTopInches),
            thicknessMode.rawValue,
            f(paperCaliperInches),
            f(measuredStackThicknessInches)
        ].joined(separator: "|")
    }

    private func f(_ value: Double) -> String {
        String(format: "%.5f", value)
    }
}

struct BindingGeometryValidation: Equatable {
    let isValid: Bool
    let message: String

    static let valid = BindingGeometryValidation(isValid: true, message: "Adaptive punch geometry verified.")
}

enum AdaptivePunchGeometry {
    static let miniPageHeightInches = 5.5

    static func physicalLeafIndex(forLogicalPageIndex logicalPageIndex: Int) -> Int {
        max(0, logicalPageIndex / 2)
    }

    /// Odd-numbered logical pages are the fronts of leaves. Even-numbered pages
    /// are the backs and their punch targets are mirrored horizontally so the
    /// printed target circles occupy the same physical holes after duplexing.
    static func bindingEdge(forLogicalPageIndex logicalPageIndex: Int) -> MiniBookBindingEdge {
        logicalPageIndex % 2 == 0 ? .left : .right
    }

    static func leafCenterDepthInches(
        leafIndex: Int,
        totalLeaves: Int,
        stackThicknessInches: Double
    ) -> Double {
        guard totalLeaves > 0 else { return 0 }
        let leafThickness = stackThicknessInches / Double(totalLeaves)
        return (Double(leafIndex + 1) - Double(totalLeaves + 1) / 2.0) * leafThickness
    }

    /// Chord length through a circular ring at the physical depth of this leaf.
    /// For a 1-inch diameter ring, the maximum spacing is 1 inch at the center.
    static func holeSpacingInches(
        leafIndex: Int,
        totalLeaves: Int,
        settings: BindingGuideSettings
    ) -> Double? {
        guard totalLeaves > 0,
              leafIndex >= 0,
              leafIndex < totalLeaves,
              settings.ringDiameterInches > 0 else {
            return nil
        }

        let radius = settings.ringDiameterInches / 2.0
        let stackThickness = settings.resolvedStackThicknessInches(totalLeaves: totalLeaves)
        let z = leafCenterDepthInches(
            leafIndex: leafIndex,
            totalLeaves: totalLeaves,
            stackThicknessInches: stackThickness
        )

        let inside = radius * radius - z * z
        guard inside >= 0 else { return nil }
        return 2.0 * sqrt(inside)
    }

    /// Four target-center distances measured down from the top edge of a finished
    /// 4.25 × 5.5 inch mini page.
    static func targetYFromTopInches(
        leafIndex: Int,
        totalLeaves: Int,
        settings: BindingGuideSettings
    ) -> [Double]? {
        guard let spacing = holeSpacingInches(
            leafIndex: leafIndex,
            totalLeaves: totalLeaves,
            settings: settings
        ) else { return nil }

        let half = spacing / 2.0
        return [
            settings.upperRingCenterFromTopInches - half,
            settings.upperRingCenterFromTopInches + half,
            settings.lowerRingCenterFromTopInches - half,
            settings.lowerRingCenterFromTopInches + half
        ]
    }

    static func validate(
        bookPageCount: Int,
        settings: BindingGuideSettings
    ) -> BindingGeometryValidation {
        guard settings.enabled else { return .valid }
        guard bookPageCount > 0 else {
            return BindingGeometryValidation(isValid: false, message: "A book needs at least one page before punch guides can be calculated.")
        }
        guard settings.ringDiameterInches > 0 else {
            return BindingGeometryValidation(isValid: false, message: "Ring diameter must be greater than zero.")
        }
        guard settings.targetDiameterInches > 0, settings.targetDiameterInches <= 0.25 else {
            return BindingGeometryValidation(isValid: false, message: "Punch target diameter must be greater than 0 and no larger than 0.25 inch.")
        }
        guard settings.bindingEdgeInsetInches > settings.targetDiameterInches / 2.0,
              settings.bindingEdgeInsetInches < 1.0 else {
            return BindingGeometryValidation(isValid: false, message: "Binding-edge inset must keep the target circle fully on the mini page.")
        }

        let totalLeaves = MiniBookImposition.physicalLeafCount(forBookPageCount: bookPageCount)
        let stack = settings.resolvedStackThicknessInches(totalLeaves: totalLeaves)
        guard stack < settings.ringDiameterInches else {
            return BindingGeometryValidation(
                isValid: false,
                message: String(format: "The %.3f-inch finished stack is too thick for a %.3f-inch diameter ring. Use a larger ring or a thinner stack.", stack, settings.ringDiameterInches)
            )
        }

        for leafIndex in 0..<totalLeaves {
            guard let targets = targetYFromTopInches(
                leafIndex: leafIndex,
                totalLeaves: totalLeaves,
                settings: settings
            ) else {
                return BindingGeometryValidation(isValid: false, message: "The circular ring geometry is impossible for leaf \(leafIndex + 1).")
            }
            let radius = settings.targetDiameterInches / 2.0
            guard targets.allSatisfy({ $0 - radius >= 0 && $0 + radius <= miniPageHeightInches }) else {
                return BindingGeometryValidation(isValid: false, message: "A punch target would fall outside the finished mini page.")
            }
        }

        return .valid
    }
}
