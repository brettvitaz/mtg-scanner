#if DEBUG
import Darwin
import Foundation

enum ProbeMetrics {
    static func memory() -> [String: UInt64] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return [:] }
        return ["residentBytes": info.resident_size, "peakResidentBytes": info.resident_size_peak,
                "footprintBytes": info.phys_footprint]
    }

    static func diskBytes(_ root: URL) -> Int64 {
        guard let paths = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var bytes: Int64 = 0
        for case let path as URL in paths {
            bytes += Int64((try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return bytes
    }
}

final class ProbeSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Credentials must never follow a redirect; public data downloads may redirect normally.
        let original = task.originalRequest
        let authenticated = original?.value(forHTTPHeaderField: "Authorization") != nil
            || original?.value(forHTTPHeaderField: "x-api-key") != nil
        completionHandler(authenticated ? nil : request)
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 1800
        return URLSession(configuration: configuration, delegate: ProbeSessionDelegate(), delegateQueue: nil)
    }
}
#endif
