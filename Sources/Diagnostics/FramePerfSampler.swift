import Foundation

/// Rolling frame-time samples and derived statistics. Kept separate from I/O so
/// the render loop only appends doubles.
struct FramePerfSampler: Sendable {
    struct TimingTotals: Sendable {
        var simulationSeconds: Double = 0
        var presentationSeconds: Double = 0
    }

    private(set) var frameSeconds: [Double] = []
    private(set) var timing = TimingTotals()
    private(set) var sampleCount: Int = 0

    mutating func record(
        frameSeconds frame: Double,
        simulationSeconds sim: Double,
        presentationSeconds pres: Double
    ) {
        frameSeconds.append(frame)
        timing.simulationSeconds += sim
        timing.presentationSeconds += pres
        sampleCount += 1
    }

    // MARK: - Statistics

    struct FrameStats: Codable, Sendable {
        var sampleCount: Int
        var meanMs: Double
        var medianMs: Double
        var p95Ms: Double
        var p99Ms: Double
        var worstMs: Double
        var fpsMean: Double
        var longFrameCount: Int
        var droppedFrameCount: Int
        var framesOverBudgetCount: Int
        var framesOverBudgetPercent: Double
        var budgetMs: Double
        var simulationMeanMs: Double
        var presentationMeanMs: Double
    }

    func statistics(budgetSeconds: Double) -> FrameStats? {
        guard !frameSeconds.isEmpty else { return nil }
        let sorted = frameSeconds.sorted()
        let count = sorted.count
        let mean = sorted.reduce(0, +) / Double(count)
        let budget = budgetSeconds * 1000
        let longThreshold = budget * 1.5
        let droppedThreshold = budget * 2.0

        var longCount = 0
        var droppedCount = 0
        var overBudgetCount = 0
        for sample in sorted {
            let ms = sample * 1000
            if ms > budget { overBudgetCount += 1 }
            if ms > longThreshold { longCount += 1 }
            if ms > droppedThreshold { droppedCount += 1 }
        }

        return FrameStats(
            sampleCount: count,
            meanMs: mean * 1000,
            medianMs: percentile(sorted, 0.50) * 1000,
            p95Ms: percentile(sorted, 0.95) * 1000,
            p99Ms: percentile(sorted, 0.99) * 1000,
            worstMs: sorted.last! * 1000,
            fpsMean: mean > 0 ? 1.0 / mean : 0,
            longFrameCount: longCount,
            droppedFrameCount: droppedCount,
            framesOverBudgetCount: overBudgetCount,
            framesOverBudgetPercent: Double(overBudgetCount) / Double(count) * 100,
            budgetMs: budget,
            simulationMeanMs: timing.simulationSeconds / Double(count) * 1000,
            presentationMeanMs: timing.presentationSeconds / Double(count) * 1000
        )
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[index]
    }
}
