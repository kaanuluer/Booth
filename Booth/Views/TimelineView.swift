import SwiftUI

struct TimelineView: View {
    @Binding var episode: Episode
    @Binding var selectedClipID: UUID?
    @Binding var playhead: TimeInterval
    var pixelsPerSecond: CGFloat
    var snapEnabled: Bool
    var mediaRoot: URL
    var onSeek: (TimeInterval) -> Void

    @State private var dragOrigins: [UUID: TimeInterval] = [:]

    private let trackHeight: CGFloat = 88
    private let headerWidth: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = max(geo.size.width, headerWidth + CGFloat(episode.timelineDuration) * pixelsPerSecond)
                ScrollView([.horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ruler(width: width)
                        ForEach($episode.tracks) { $track in
                            trackLane(track: $track, width: width)
                        }
                        addLane(width: width)
                    }
                    .frame(minWidth: width, minHeight: geo.size.height, alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        playheadLine(height: geo.size.height)
                    }
                }
            }
        }
        .background(BoothTheme.canvas)
    }

    private func ruler(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            BoothTheme.surface
            Path { path in
                let seconds = Int(episode.timelineDuration)
                for s in stride(from: 0, through: seconds, by: 5) {
                    let x = headerWidth + CGFloat(s) * pixelsPerSecond
                    path.move(to: CGPoint(x: x, y: 22))
                    path.addLine(to: CGPoint(x: x, y: 36))
                }
            }
            .stroke(BoothTheme.hairline, lineWidth: 1)

            ForEach(Array(stride(from: 0, through: Int(episode.timelineDuration), by: 10)), id: \.self) { s in
                Text(TimeCode.format(TimeInterval(s)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BoothTheme.secondary)
                    .offset(x: headerWidth + CGFloat(s) * pixelsPerSecond + 4, y: 4)
            }
        }
        .frame(width: width, height: 36)
        .contentShape(Rectangle())
        .gesture(seekGesture)
    }

    private func trackLane(track: Binding<Track>, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(BoothTheme.trackColor(track.wrappedValue.kind)).frame(width: 8, height: 8)
                    Text(track.wrappedValue.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BoothTheme.text)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Button(track.wrappedValue.muted ? "M" : "M") {
                        track.wrappedValue.muted.toggle()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(track.wrappedValue.muted ? BoothTheme.accent : BoothTheme.secondary)
                    Button("S") { track.wrappedValue.solo.toggle() }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(track.wrappedValue.solo ? BoothTheme.music : BoothTheme.secondary)
                }
            }
            .padding(8)
            .frame(width: headerWidth, height: trackHeight, alignment: .topLeading)
            .background(BoothTheme.surface)

            ZStack(alignment: .leading) {
                Rectangle().fill(BoothTheme.canvas)
                ForEach(track.wrappedValue.clips) { clip in
                    clipBlock(clip, trackColor: BoothTheme.trackColor(track.wrappedValue.kind))
                }
            }
            .frame(width: width - headerWidth, height: trackHeight)
            .clipped()
        }
        .overlay(alignment: .bottom) { Divider().background(BoothTheme.hairline) }
    }

    private func clipBlock(_ clip: Clip, trackColor: Color) -> some View {
        let x = CGFloat(clip.startOnTimeline) * pixelsPerSecond
        let w = max(28, CGFloat(clip.duration) * pixelsPerSecond)
        let selected = selectedClipID == clip.id
        return FileWaveform(url: mediaRoot.appendingPathComponent(clip.filename), color: trackColor)
            .overlay(alignment: .topLeading) {
                Text(clip.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .padding(6)
                    .lineLimit(1)
            }
            .frame(width: w, height: trackHeight - 16)
            .background(trackColor.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.white : trackColor.opacity(0.7), lineWidth: selected ? 2 : 1)
            )
            .offset(x: x, y: 8)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        selectedClipID = clip.id
                        if dragOrigins[clip.id] == nil {
                            dragOrigins[clip.id] = clip.startOnTimeline
                        }
                        let origin = dragOrigins[clip.id] ?? clip.startOnTimeline
                        var next = origin + TimeInterval(value.translation.width / pixelsPerSecond)
                        next = max(0, next)
                        if snapEnabled { next = (next * 10).rounded() / 10 }
                        episode.updateClip(clip.id) { $0.startOnTimeline = next }
                    }
                    .onEnded { _ in
                        dragOrigins[clip.id] = nil
                    }
            )
            .onTapGesture { selectedClipID = clip.id }
            .contextMenu {
                Button("Böl") { episode.splitClip(clip.id, at: playhead) }
                Button("Sil", role: .destructive) { episode.removeClip(clip.id) }
            }
    }

    private func addLane(width: CGFloat) -> some View {
        Button {
            episode.addAuxTrack()
        } label: {
            HStack {
                Text("+ Katman ekle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BoothTheme.secondary)
                    .frame(width: headerWidth)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .foregroundStyle(BoothTheme.hairline)
                    .frame(height: 52)
            }
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
        }
            .buttonStyle(.plain)
        .disabled(episode.tracks.count >= Episode.maxTracks)
    }

    private func playheadLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(BoothTheme.text)
            .frame(width: 2, height: height)
            .offset(x: headerWidth + CGFloat(playhead) * pixelsPerSecond)
            .allowsHitTesting(false)
    }

    private var seekGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let t = TimeInterval((value.location.x - headerWidth) / pixelsPerSecond)
                if t >= 0 {
                    onSeek(min(max(0, t), episode.timelineDuration))
                }
            }
    }
}
