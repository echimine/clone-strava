import Foundation

/// UTC epoch milliseconds, the time unit of trace v2 (ADR-019 §3, ADR-031 §12).
extension Date {
    var epochMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }

    init(epochMilliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(epochMilliseconds) / 1_000)
    }
}
