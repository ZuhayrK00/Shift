#if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
import Foundation

/// Local App Store photography only. Not compiled into normal Debug or Release builds.
enum StoreCaptureConfiguration {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--store-capture")
    static let owner = "7a247d9a-05c5-4d39-8419-601ad9ef9641"
    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--capture-screen"), args.indices.contains(index + 1) else { return "strength" }
        return args[index + 1]
    }
}
#endif
