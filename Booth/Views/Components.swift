import SwiftUI
import AVFoundation

struct BoothButtonStyle: ButtonStyle {
    var fill: Color = BoothTheme.accent
    var foreground: Color = .white
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 10)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    }
}

struct BoothIconButton: View {
    var systemName: String
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? BoothTheme.text : BoothTheme.secondary)
                .frame(width: 36, height: 36)
                .background(selected ? BoothTheme.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct WaveformView: View {
    var samples: [Float]
    var color: Color
    var progress: Double? = nil

    var body: some View {
        Canvas { context, size in
            let count = max(samples.count, 1)
            let mid = size.height / 2
            let step = size.width / CGFloat(count)
            let barWidth = max(1, step - (count > 80 ? 0.4 : 1))
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * step
                let amp = max(1.5, CGFloat(sample) * size.height * 0.46)
                let rect = CGRect(x: x, y: mid - amp, width: barWidth, height: amp * 2)
                let faded = progress.map { CGFloat(index) / CGFloat(count) < $0 } ?? true
                context.fill(Path(rect), with: .color(color.opacity(faded ? 0.92 : 0.26)))
            }
        }
        .clipped()
    }
}

struct FileWaveform: View, Equatable {
    var url: URL?
    var color: Color
    var barCount: Int = 64
    var progress: Double? = nil
    @State private var samples: [Float] = []

    static func == (lhs: FileWaveform, rhs: FileWaveform) -> Bool {
        lhs.url == rhs.url && lhs.color == rhs.color && lhs.barCount == rhs.barCount && lhs.progress == rhs.progress
    }

    var body: some View {
        WaveformView(samples: samples.isEmpty ? [0.12, 0.2, 0.16, 0.28, 0.18] : samples, color: color, progress: progress)
            .task(id: "\(url?.path ?? "")#\(barCount)") {
                guard let captured = url, captured.isFileURL else { return }
                let count = barCount
                if let cached = WaveformCache.shared.cached(url: captured, count: count) {
                    samples = cached
                    return
                }
                samples = await Task.detached(priority: .utility) {
                    WaveformCache.shared.peaks(url: captured, count: count)
                }.value
            }
    }
}

struct MeterBar: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(BoothTheme.elevated)
                Capsule()
                    .fill(levelColor)
                    .frame(height: max(4, height * CGFloat(level)))
            }
        }
        .frame(width: 10)
    }

    private var levelColor: Color {
        if level > 0.9 { return BoothTheme.accent }
        if level > 0.55 { return BoothTheme.success }
        return BoothTheme.voice
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
