import Foundation

struct EdgeInfo: Equatable {
    var colo: String?
    var loc: String?
    var http: String?
    var city: String?
}

struct SpeedTestResult: Equatable {
    var downloadMbps: Double
    var uploadMbps: Double
    var pingMs: Double
    var jitterMs: Double
    var pingSamples: Int
    var downloadBytes: Int64
    var uploadBytes: Int64
    var edge: EdgeInfo?
}

enum TestPhase: String {
    case idle, discover, ping, download, upload, done, failed
}

struct SpeedTestEvent {
    var phase: TestPhase
    var progress: Double
    var statusLine: String
    var liveMbps: Double? = nil
    var pingMs: Double? = nil
    var jitterMs: Double? = nil
    var downloadMbps: Double? = nil
    var uploadMbps: Double? = nil
    var edge: EdgeInfo? = nil
    var result: SpeedTestResult? = nil
    var error: String? = nil
}

enum CloudflareEndpoints {
    static let origin = "https://speed.cloudflare.com"
    static let trace = "\(origin)/cdn-cgi/trace"
    static let download = "\(origin)/__down"
    static let upload = "\(origin)/__up"
    static let userAgent = "RootforgeSpeedTest/1.0.0 (iOS; com.rootforge.speedtest)"
    static func downloadURL(bytes: Int64) -> URL {
        URL(string: "\(download)?bytes=\(bytes)")!
    }
}

enum Stats {
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2.0
    }

    static func meanConsecutiveDiff(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<values.count { sum += abs(values[i] - values[i - 1]) }
        return sum / Double(values.count - 1)
    }

    static func mbps(bytes: Int64, nanos: UInt64) -> Double {
        guard bytes > 0, nanos > 0 else { return 0 }
        let bits = Double(bytes) * 8.0
        let seconds = Double(nanos) / 1_000_000_000.0
        return bits / seconds / 1_000_000.0
    }

    static func formatMbps(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    static func formatMs(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return mb >= 10 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
    }
}

final class SpeedTestEngine {
    private let session: URLSession
    private let pingSamples = 8
    private let downloadStreams = 3
    private let uploadStreams = 2
    private let targetSeconds = 6.0
    private let warmupDownload: Int64 = 256 * 1024
    private let probeDownload: Int64 = 1 * 1024 * 1024
    private let warmupUpload: Int64 = 128 * 1024
    private let probeUpload: Int64 = 512 * 1024
    private let minBytes: Int64 = 64 * 1024

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": CloudflareEndpoints.userAgent,
            "Cache-Control": "no-store"
        ]
        session = URLSession(configuration: config)
    }

    func run(onEvent: @escaping (SpeedTestEvent) -> Void) async throws -> SpeedTestResult {
        do {
            onEvent(SpeedTestEvent(phase: .discover, progress: 0.04, statusLine: "discover · GET /cdn-cgi/trace"))
            let edge = try await fetchEdge()
            onEvent(SpeedTestEvent(phase: .discover, progress: 0.08, statusLine: formatEdge(edge), edge: edge))

            onEvent(SpeedTestEvent(phase: .ping, progress: 0.10, statusLine: "ping · HTTP GET \(pingSamples)× /__down?bytes=0", edge: edge))
            var rtts: [Double] = []
            for i in 1...pingSamples {
                try Task.checkCancellation()
                let ms = try await timedGet(CloudflareEndpoints.downloadURL(bytes: 0))
                rtts.append(ms)
                onEvent(SpeedTestEvent(
                    phase: .ping,
                    progress: 0.10 + 0.18 * (Double(i) / Double(pingSamples)),
                    statusLine: String(format: "ping · sample %d/%d  %.1f ms", i, pingSamples, ms),
                    edge: edge
                ))
            }
            let usable = rtts.count >= 4 ? Array(rtts.dropFirst()) : rtts
            guard usable.count >= 3 else { throw SpeedTestError.message("Not enough ping samples. Check the network and retry.") }
            let pingMs = Stats.median(usable)
            let jitterMs = Stats.meanConsecutiveDiff(usable)
            onEvent(SpeedTestEvent(
                phase: .ping, progress: 0.30,
                statusLine: "ping · median \(Stats.formatMs(pingMs)) ms · jitter \(Stats.formatMs(jitterMs)) ms",
                pingMs: pingMs, jitterMs: jitterMs, edge: edge
            ))

            onEvent(SpeedTestEvent(
                phase: .download, progress: 0.32,
                statusLine: "download · GET /__down (multi-chunk)",
                pingMs: pingMs, jitterMs: jitterMs, edge: edge
            ))
            let download = try await measureDownload(onProgress: { fraction, live, bytes in
                onEvent(SpeedTestEvent(
                    phase: .download,
                    progress: 0.32 + 0.34 * fraction,
                    statusLine: "download · \(Stats.formatBytes(bytes))  \(Stats.formatMbps(live)) Mbps",
                    liveMbps: live, pingMs: pingMs, jitterMs: jitterMs, downloadMbps: live, edge: edge
                ))
            })
            onEvent(SpeedTestEvent(
                phase: .download, progress: 0.66,
                statusLine: "download · \(Stats.formatMbps(download.mbps)) Mbps (\(Stats.formatBytes(download.bytes)))",
                pingMs: pingMs, jitterMs: jitterMs, downloadMbps: download.mbps, edge: edge
            ))

            onEvent(SpeedTestEvent(
                phase: .upload, progress: 0.68,
                statusLine: "upload · POST /__up",
                pingMs: pingMs, jitterMs: jitterMs, downloadMbps: download.mbps, edge: edge
            ))
            let upload = try await measureUpload(onProgress: { fraction, live, bytes in
                onEvent(SpeedTestEvent(
                    phase: .upload,
                    progress: 0.68 + 0.28 * fraction,
                    statusLine: "upload · \(Stats.formatBytes(bytes))  \(Stats.formatMbps(live)) Mbps",
                    liveMbps: live, pingMs: pingMs, jitterMs: jitterMs,
                    downloadMbps: download.mbps, uploadMbps: live, edge: edge
                ))
            })

            let result = SpeedTestResult(
                downloadMbps: download.mbps, uploadMbps: upload.mbps,
                pingMs: pingMs, jitterMs: jitterMs, pingSamples: usable.count,
                downloadBytes: download.bytes, uploadBytes: upload.bytes, edge: edge
            )
            onEvent(SpeedTestEvent(
                phase: .done, progress: 1,
                statusLine: "done · \(formatEdge(edge))",
                pingMs: pingMs, jitterMs: jitterMs,
                downloadMbps: download.mbps, uploadMbps: upload.mbps,
                edge: edge, result: result
            ))
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let message = Self.humanize(error)
            onEvent(SpeedTestEvent(phase: .failed, progress: 0, statusLine: "link down · \(message)", error: message))
            throw SpeedTestError.message(message)
        }
    }

    private struct Throughput {
        var bytes: Int64
        var nanos: UInt64
        var mbps: Double
    }

    private func fetchEdge() async throws -> EdgeInfo {
        do {
            var req = URLRequest(url: URL(string: CloudflareEndpoints.trace)!)
            req.httpMethod = "GET"
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let body = String(data: data, encoding: .utf8), !body.isEmpty {
                let map = Self.parseTrace(body)
                return EdgeInfo(colo: map["colo"], loc: map["loc"], http: map["http"], city: nil)
            }
        } catch { /* fall through */ }

        var probe = URLRequest(url: CloudflareEndpoints.downloadURL(bytes: 0))
        probe.httpMethod = "GET"
        let (_, response) = try await session.data(for: probe)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.message("Edge probe failed")
        }
        return EdgeInfo(
            colo: http.value(forHTTPHeaderField: "cf-meta-colo") ?? http.value(forHTTPHeaderField: "colo"),
            loc: http.value(forHTTPHeaderField: "cf-meta-country") ?? http.value(forHTTPHeaderField: "country"),
            http: nil,
            city: http.value(forHTTPHeaderField: "cf-meta-city") ?? http.value(forHTTPHeaderField: "city")
        )
    }

    private func timedGet(_ url: URL) async throws -> Double {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let start = DispatchTime.now().uptimeNanoseconds
        let (_, response) = try await session.data(for: req)
        let nanos = DispatchTime.now().uptimeNanoseconds - start
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.message("Ping probe failed")
        }
        return Double(nanos) / 1_000_000.0
    }

    private func measureDownload(onProgress: @escaping (Double, Double, Int64) -> Void) async throws -> Throughput {
        _ = try await downloadOnce(warmupDownload) { _, _ in }
        let probe = try await downloadOnce(probeDownload) { _, _ in }
        guard probe.bytes >= minBytes else { throw SpeedTestError.message("Download stalled after \(Stats.formatBytes(probe.bytes)).") }
        let probeMbps = max(probe.mbps, 1.0)
        let target = clampBytes(Int64((probeMbps * 1_000_000.0 / 8.0) * targetSeconds), min: 2 * 1024 * 1024, max: 40 * 1024 * 1024)
        let perStream = max(Int64(1 * 1024 * 1024), target / Int64(downloadStreams))
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let streams: [Throughput] = try await withThrowingTaskGroup(of: Throughput.self) { group in
            for _ in 0..<downloadStreams {
                group.addTask {
                    try await self.downloadOnce(perStream) { loaded, _ in
                        let approx = loaded * Int64(self.downloadStreams)
                        let elapsed = DispatchTime.now().uptimeNanoseconds - wallStart
                        let live = Stats.mbps(bytes: approx, nanos: elapsed)
                        onProgress(min(1, Double(loaded) / Double(perStream)), live, approx)
                    }
                }
            }
            var out: [Throughput] = []
            for try await t in group { out.append(t) }
            return out
        }
        let wallNanos = DispatchTime.now().uptimeNanoseconds - wallStart
        let totalBytes = streams.reduce(Int64(0)) { $0 + $1.bytes }
        guard totalBytes >= minBytes else { throw SpeedTestError.message("Download transferred too little data to measure.") }
        let mbps = Stats.mbps(bytes: totalBytes, nanos: wallNanos)
        onProgress(1, mbps, totalBytes)
        return Throughput(bytes: totalBytes, nanos: wallNanos, mbps: mbps)
    }

    private func downloadOnce(_ bytes: Int64, onChunk: @escaping (Int64, UInt64) -> Void) async throws -> Throughput {
        var req = URLRequest(url: CloudflareEndpoints.downloadURL(bytes: bytes))
        req.httpMethod = "GET"
        let start = DispatchTime.now().uptimeNanoseconds
        let (bytesData, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.message("Download returned HTTP error")
        }
        let loaded = Int64(bytesData.count)
        guard loaded > 0 else { throw SpeedTestError.message("Download returned zero bytes.") }
        let nanos = DispatchTime.now().uptimeNanoseconds - start
        onChunk(loaded, nanos)
        return Throughput(bytes: loaded, nanos: nanos, mbps: Stats.mbps(bytes: loaded, nanos: nanos))
    }

    private func measureUpload(onProgress: @escaping (Double, Double, Int64) -> Void) async throws -> Throughput {
        _ = try await uploadOnce(warmupUpload)
        let probe = try await uploadOnce(probeUpload)
        guard probe.bytes >= minBytes else { throw SpeedTestError.message("Upload stalled after \(Stats.formatBytes(probe.bytes)).") }
        let probeMbps = max(probe.mbps, 0.5)
        let target = clampBytes(Int64((probeMbps * 1_000_000.0 / 8.0) * targetSeconds), min: 1 * 1024 * 1024, max: 20 * 1024 * 1024)
        let perStream = max(Int64(512 * 1024), target / Int64(uploadStreams))
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let streams: [Throughput] = try await withThrowingTaskGroup(of: Throughput.self) { group in
            for _ in 0..<uploadStreams {
                group.addTask {
                    let t = try await self.uploadOnce(perStream)
                    let approx = t.bytes * Int64(self.uploadStreams)
                    let elapsed = DispatchTime.now().uptimeNanoseconds - wallStart
                    let live = Stats.mbps(bytes: approx, nanos: elapsed)
                    onProgress(min(1, Double(t.bytes) / Double(perStream)), live, approx)
                    return t
                }
            }
            var out: [Throughput] = []
            for try await t in group { out.append(t) }
            return out
        }
        let wallNanos = DispatchTime.now().uptimeNanoseconds - wallStart
        let totalBytes = streams.reduce(Int64(0)) { $0 + $1.bytes }
        guard totalBytes >= minBytes else { throw SpeedTestError.message("Upload transferred too little data to measure.") }
        let mbps = Stats.mbps(bytes: totalBytes, nanos: wallNanos)
        onProgress(1, mbps, totalBytes)
        return Throughput(bytes: totalBytes, nanos: wallNanos, mbps: mbps)
    }

    private func uploadOnce(_ bytes: Int64) async throws -> Throughput {
        var req = URLRequest(url: URL(string: CloudflareEndpoints.upload)!)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(count: Int(bytes))
        let start = DispatchTime.now().uptimeNanoseconds
        let (_, response) = try await session.upload(for: req, from: payload)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.message("Upload returned HTTP error")
        }
        let nanos = DispatchTime.now().uptimeNanoseconds - start
        return Throughput(bytes: bytes, nanos: nanos, mbps: Stats.mbps(bytes: bytes, nanos: nanos))
    }

    private func clampBytes(_ bytes: Int64, min: Int64, max: Int64) -> Int64 {
        Swift.min(max, Swift.max(min, bytes))
    }

    private func formatEdge(_ edge: EdgeInfo) -> String {
        let colo = edge.colo ?? "?"
        let loc = edge.loc ?? "?"
        if let city = edge.city, !city.isEmpty { return "edge · colo \(colo) · \(city) · \(loc)" }
        return "edge · colo \(colo) · loc \(loc)"
    }

    static func parseTrace(_ body: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in body.split(whereSeparator: \.isNewline) {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard let idx = s.firstIndex(of: "=") else { continue }
            map[String(s[..<idx])] = String(s[s.index(after: idx)...])
        }
        return map
    }

    static func humanize(_ error: Error) -> String {
        if let e = error as? SpeedTestError { return e.localizedDescription }
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "No network. Check Wi-Fi or cellular and try again."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Could not reach speed.cloudflare.com. Check the network and retry."
        case NSURLErrorTimedOut:
            return "The speed-test origin timed out. Try again on a more stable link."
        default:
            let detail = error.localizedDescription
            return detail.isEmpty ? "Speed test failed." : "Speed test failed · \(detail)"
        }
    }
}

enum SpeedTestError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}
