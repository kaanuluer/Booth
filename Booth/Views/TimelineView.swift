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
    @State private var draggingClipID: UUID?
    @State private var dragOffsetY: CGFloat = 0
    @State private var hoverTrackID: UUID?

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
                                .zIndex(isDragging(from: track) ? 20 : 0)
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
                RoundedRectangle(cornerRadius: 0)
                    .fill(hoverTrackID == track.wrappedValue.id ? BoothTheme.trackColor(track.wrappedValue.kind).opacity(0.14) : BoothTheme.canvas)
                if hoverTrackID == track.wrappedValue.id {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(BoothTheme.trackColor(track.wrappedValue.kind).opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                        .padding(4)
                }
                ForEach(track.wrappedValue.clips) { clip in
                    clipBlock(clip, track: track.wrappedValue)
                }
            }
            .frame(width: width - headerWidth, height: trackHeight)
        }
        .overlay(alignment: .bottom) { Divider().background(BoothTheme.hairline) }
    }

    private func clipBlock(_ clip: Clip, track: Track) -> some View {
        let x = CGFloat(clip.startOnTimeline) * pixelsPerSecond
        let w = max(28, CGFloat(clip.duration) * pixelsPerSecond)
        let selected = selectedClipID == clip.id
        let dragging = draggingClipID == clip.id
        let previewKind = dragging ? (episode.tracks.first(where: { $0.id == hoverTrackID })?.kind ?? track.kind) : track.kind
        let trackColor = BoothTheme.trackColor(previewKind)
        return FileWaveform(url: mediaRoot.appendingPathComponent(clip.filename), color: trackColor)
            .overlay(alignment: .topLeading) {
                Text(clip.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .padding(6)
                    .lineLimit(1)
            }
            .frame(width: w, height: trackHeight - 16)
            .background(trackColor.opacity(dragging ? 0.42 : 0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected || dragging ? Color.white : trackColor.opacity(0.7), lineWidth: selected || dragging ? 2 : 1)
            )
            .shadow(color: dragging ? .black.opacity(0.45) : .clear, radius: 12, y: 6)
            .offset(x: x, y: 8 + (dragging ? dragOffsetY : 0))
            .zIndex(dragging ? 50 : 0)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        beginDrag(clip, on: track, translation: value.translation)
                    }
                    .onEnded { value in
                        finishDrag(clip, from: track, translation: value.translation)
                    }
            )
            .onTapGesture { selectedClipID = clip.id }
            .contextMenu {
                Button("Böl") { episode.splitClip(clip.id, at: playhead) }
                Menu("Katmana taşı") {
                    ForEach(episode.tracks) { destination in
                        Button(destination.name) {
                            episode.moveClip(clip.id, to: destination.id)
                        }
                        .disabled(destination.id == track.id)
                    }
                }
                Button("Sil", role: .destructive) { episode.removeClip(clip.id) }
            }
    }

    private func beginDrag(_ clip: Clip, on track: Track, translation: CGSize) {
        selectedClipID = clip.id
        draggingClipID = clip.id
        dragOffsetY = translation.height
        if dragOrigins[clip.id] == nil {
            dragOrigins[clip.id] = clip.startOnTimeline
        }
        let origin = dragOrigins[clip.id] ?? clip.startOnTimeline
        var next = origin + TimeInterval(translation.width / pixelsPerSecond)
        next = max(0, next)
        if snapEnabled { next = (next * 10).rounded() / 10 }
        episode.updateClip(clip.id) { $0.startOnTimeline = next }
        if let source = episode.tracks.firstIndex(where: { $0.id == track.id }) {
            hoverTrackID = destinationTrack(from: source, translationY: translation.height)?.id
        }
    }

    private func finishDrag(_ clip: Clip, from track: Track, translation: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let source = episode.tracks.firstIndex(where: { $0.id == track.id }),
               let destination = destinationTrack(from: source, translationY: translation.height),
               destination.id != track.id {
                episode.moveClip(clip.id, to: destination.id)
            }
            dragOrigins[clip.id] = nil
            draggingClipID = nil
            dragOffsetY = 0
            hoverTrackID = nil
        }
    }

    private func destinationTrack(from sourceIndex: Int, translationY: CGFloat) -> Track? {
        guard !episode.tracks.isEmpty else { return nil }
        let raw = sourceIndex + Int((translationY / trackHeight).rounded())
        let index = min(max(0, raw), episode.tracks.count - 1)
        return episode.tracks[index]
    }

    private func isDragging(from track: Track) -> Bool {
        guard let draggingClipID else { return false }
        return track.clips.contains { $0.id == draggingClipID }
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
