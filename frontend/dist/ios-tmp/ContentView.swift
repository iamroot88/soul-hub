import SwiftUI

private let hudCyan = Color(red: 0.0, green: 0.90, blue: 0.95)
private let hudMagenta = Color(red: 0.95, green: 0.20, blue: 0.70)
private let hudLime = Color(red: 0.55, green: 0.95, blue: 0.35)
private let hudDanger = Color(red: 1.0, green: 0.30, blue: 0.35)
private let hudMuted = Color(white: 0.55)
private let hudText = Color(white: 0.92)
private let hudBg = Color(red: 0.04, green: 0.05, blue: 0.08)

struct ContentView: View {
    @StateObject private var model = SpeedTestViewModel()
    @State private var showAbout = false

    var body: some View {
        ZStack {
            hudBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ROOTFORGE")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(hudCyan)
                            Text("SPEED TEST")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .tracking(3)
                                .foregroundStyle(hudText)
                            Text("v1.0.0  ·  FREE  ·  NO IAP")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(hudMuted)
                        }
                        Spacer()
                        Button("About") { showAbout = true }
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hudMagenta)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(hudMagenta, lineWidth: 1))
                    }

                    Text(edgeLine)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(hudMuted)

                    Button(action: primaryAction) {
                        Text(primaryLabel)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(hudBg)
                            .background(model.isRunning ? hudMagenta : hudCyan)
                            .cornerRadius(6)
                    }

                    ProgressView(value: progressValue)
                        .tint(progressColor)
                        .scaleEffect(x: 1, y: 1.6, anchor: .center)

                    Text(model.statusLine)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.phase == .failed ? hudDanger : hudLime)

                    if let err = model.error, model.phase == .failed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LINK DOWN").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(hudDanger)
                            Text(err).font(.system(size: 14, design: .monospaced)).foregroundStyle(hudText)
                            Text("No numbers were invented. Fix the path and re-run.")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(hudMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(hudDanger, lineWidth: 1))
                    }

                    Text("RESULTS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(hudMuted)

                    HStack(spacing: 10) {
                        MetricCard(label: "Download", value: Stats.formatMbps(model.downloadMbps), unit: "Mbps", accent: hudCyan, live: model.phase == .download)
                        MetricCard(label: "Upload", value: Stats.formatMbps(model.uploadMbps), unit: "Mbps", accent: hudMagenta, live: model.phase == .upload)
                    }
                    HStack(spacing: 10) {
                        MetricCard(label: "Ping", value: Stats.formatMs(model.pingMs), unit: "ms", accent: hudLime, live: model.phase == .ping)
                        MetricCard(label: "Jitter", value: Stats.formatMs(model.jitterMs), unit: "ms", accent: hudLime, live: model.phase == .ping)
                    }

                    if let result = model.result {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SAMPLES").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(hudCyan)
                            Text("ping n=\(result.pingSamples)  dl=\(Stats.formatBytes(result.downloadBytes))  ul=\(Stats.formatBytes(result.uploadBytes))")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(hudMuted)
                            Text("origin speed.cloudflare.com  ·  real HTTP, not a stub")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(hudMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(hudCyan.opacity(0.5), lineWidth: 1))
                    }

                    Text("DIY first. Paid help is optional — see About.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(hudMuted)
                        .padding(.top, 4)
                }
                .padding(18)
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .preferredColorScheme(.dark)
    }

    private var edgeLine: String {
        if let e = model.edge {
            let city = e.city.map { " · \($0)" } ?? ""
            return "colo \(e.colo ?? "?") · loc \(e.loc ?? "?")\(city)"
        }
        return "colo — · loc — · waiting"
    }

    private var progressValue: Double {
        if model.isRunning { return model.progress }
        if model.result != nil { return 1 }
        return 0
    }

    private var progressColor: Color {
        switch model.phase {
        case .failed: return hudDanger
        case .upload: return hudMagenta
        case .download: return hudCyan
        default: return hudLime
        }
    }

    private var primaryLabel: String {
        if model.isRunning { return "Abort" }
        if model.result != nil { return "Re-run test" }
        return "▶  Run test"
    }

    private func primaryAction() {
        if model.isRunning { model.abort() } else { model.runTest() }
    }
}

private struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let accent: Color
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(hudText)
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(hudMuted)
            }
            if live {
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.45), lineWidth: 1))
    }
}

@MainActor
final class SpeedTestViewModel: ObservableObject {
    @Published var phase: TestPhase = .idle
    @Published var progress: Double = 0
    @Published var statusLine: String = "idle · tap run"
    @Published var pingMs: Double?
    @Published var jitterMs: Double?
    @Published var downloadMbps: Double?
    @Published var uploadMbps: Double?
    @Published var edge: EdgeInfo?
    @Published var result: SpeedTestResult?
    @Published var error: String?
    @Published var isRunning = false

    private var task: Task<Void, Never>?
    private let engine = SpeedTestEngine()

    func runTest() {
        abort()
        isRunning = true
        error = nil
        result = nil
        task = Task {
            do {
                _ = try await engine.run { [weak self] event in
                    Task { @MainActor in
                        self?.apply(event)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isRunning = false
                    if self.phase != .failed && self.phase != .done {
                        self.statusLine = "aborted"
                        self.phase = .idle
                    }
                }
            } catch {
                await MainActor.run { self.isRunning = false }
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    func abort() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func apply(_ event: SpeedTestEvent) {
        phase = event.phase
        progress = event.progress
        statusLine = event.statusLine
        if let v = event.pingMs { pingMs = v }
        if let v = event.jitterMs { jitterMs = v }
        if let v = event.downloadMbps { downloadMbps = v }
        if let v = event.uploadMbps { uploadMbps = v }
        if let v = event.edge { edge = v }
        if let v = event.result { result = v }
        if let v = event.error { error = v }
    }
}

#Preview { ContentView() }
