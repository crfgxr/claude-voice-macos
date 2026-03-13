import SwiftUI

struct WaveformView: View {
    let state: VoiceState
    let level: CGFloat

    private let barCount = 30
    @State private var phase: Double = 0
    @State private var timerSubscription: Timer.TimerPublisher? = nil

    // Only animate when active — 15fps is plenty for a waveform
    private var timer: Timer.TimerPublisher {
        Timer.publish(every: 1.0 / 15.0, on: .main, in: .common)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let norm = Double(i) / Double(barCount)
                    let height = barHeight(index: i, norm: norm, totalHeight: geo.size.height)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(norm: norm))
                        .frame(width: 4, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onReceive(timer.autoconnect()) { _ in
            guard state == .speaking || state == .listening else { return }
            phase += 0.12
        }
    }

    private func barHeight(index: Int, norm: Double, totalHeight: CGFloat) -> CGFloat {
        guard state == .speaking || state == .listening else {
            // Idle/processing: static low bars (no animation)
            return max(2, totalHeight * 0.08)
        }

        let effectiveLevel = max(0.2, Double(level))
        let wave1 = sin(norm * .pi * 3.0 + phase) * 0.4
        let wave2 = sin(norm * .pi * 5.0 - phase * 1.3) * 0.2
        let envelope = sin(norm * .pi)
        let combined = (0.25 + (wave1 + wave2) * envelope) * effectiveLevel
        let clamped = min(max(combined, 0.05), 1.0)

        return max(2, totalHeight * clamped * 0.9)
    }

    private func barColor(norm: Double) -> Color {
        switch state {
        case .speaking:
            return Color(hue: 0.72 + norm * 0.06, saturation: 0.65, brightness: 0.55 + Double(level) * 0.3)
        case .listening:
            return Color(hue: 0.55 + norm * 0.1, saturation: 0.6, brightness: 0.5 + Double(level) * 0.35)
        case .processing:
            return Color(hue: 0.72, saturation: 0.4, brightness: 0.4)
        case .idle:
            return Color(hue: 0.72, saturation: 0.2, brightness: 0.25)
        }
    }
}
