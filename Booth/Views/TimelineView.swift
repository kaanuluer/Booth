import SwiftUI

struct TimelineView: View {
    @Binding var episode: Episode
    @Binding var selectedClipID: UUID?
    @Binding var playhead: TimeInterval
    var pixelsPerSecond: CGFloat
    var snapEnabled: Bool
    var mediaRoot: URL
    var onSeek: (TimeInterval) -> Void
    var onCheckpoint: () -> Void

    @State private var dragOrigins: [UUID: TimeInterval] = [:]
    @State private var draggingClipID: UUID?
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var hoverTrackID: UUID?
    @State private var trimOrigins: [UUID: (offset: TimeInterval, duration: TimeInterval, start: TimeInterval)] = [:]

    private let trackHeight: CGFloat = 84
    private let headerWidth: CGFloat = 108
    private let rulerHeight: CGFloat = 36
    private let addLaneHeight: CGFloat = 52
    private let clipInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(
                geo.size.width - headerWidth,
                CGFloat(episode.timelineDuration) * pixelsPerSecond
            )
            let rowsHeight = rulerHeight + CGFloat(episode.tracks.count) * trackHeight + addLaneHeight
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    headerColumn
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ruler(width: contentWidth)
                            ForEach($episode.tracks) { $track in
                                clipLane(track: $track, width: contentWidth)
                                    .zIndex(isDragging(from: track) ? 20 : 0)
                            }
                            addLane(width: contentWidth)
                        }
                        .frame(width: contentWidth, height: rowsHeight, alignment: .topLeading)
                        .overlay(alignment: .topLeading) {
                            playheadLine(height: rowsHeight)
                        }
                        .overlay(alignment: .topLeading) {
                            markersOverlay(width: contentWidth, height: rowsHeight)
                        }
                        .animation(nil, value: playhead)
                    }
                    .frame(width: max(0, geo.size.width - headerWidth), height: rowsHeight, alignment: .top)
                    .contentMargins(.all, 0, for: .scrollContent)
                    .contentMargins(.all, 0, for: .scrollIndicators)
                }
                .frame(width: geo.size.width, height: rowsHeight, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentMargins(.all, 0, for: .scrollContent)
        }
        .background(BoothTheme.canvas)
    }

    private var headerColumn: some View {
        VStack(spacing: 0) {
            BoothTheme.surface
                .frame(width: headerWidth, height: rulerHeight)
            ForEach($episode.tracks) { $track in
                trackHeader($track)
            }
            Button {
                episode.addAuxTrack()
            } label: {
                Text("+ Katman")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BoothTheme.secondary)
                    .frame(width: headerWidth, height: addLaneHeight)
            }
            .buttonStyle(.plain)
            .disabled(episode.tracks.count >= Episode.maxTracks)
        }
        .frame(width: headerWidth, alignment: .top)
        .clipped()
        .background(BoothTheme.surface)
    }

    private func trackHeader(_ track: Binding<Track>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(BoothTheme.trackColor(track.wrappedValue.kind)).frame(width: 8, height: 8)
                Text(track.wrappedValue.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                muteSoloButton("M", active: track.wrappedValue.muted, color: BoothTheme.accent) {
                    onCheckpoint()
                    track.wrappedValue.muted.toggle()
                }
                muteSoloButton("S", active: track.wrappedValue.solo, color: BoothTheme.music) {
                    onCheckpoint()
                    track.wrappedValue.solo.toggle()
                }
            }
            volumeBar(track)
            panBar(track)
        }
        .padding(8)
        .frame(width: headerWidth, height: trackHeight, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottom) { Divider().background(BoothTheme.hairline) }
    }

    private func volumeBar(_ track: Binding<Track>) -> some View {
        GeometryReader { geo in
            let ratio = max(0, min(1, track.wrappedValue.volume / 1.5))
            ZStack(alignment: .leading) {
                Capsule().fill(BoothTheme.elevated)
                Capsule()
                    .fill(BoothTheme.trackColor(track.wrappedValue.kind))
                    .frame(width: max(6, geo.size.width * ratio))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let next = Double(value.location.x / max(geo.size.width, 1)) * 1.5
                        track.wrappedValue.volume = max(0, min(1.5, next))
                    }
            )
        }
        .frame(height: 10)
    }

    private func panBar(_ track: Binding<Track>) -> some View {
        GeometryReader { geo in
            let ratio = (track.wrappedValue.pan + 1) / 2
            ZStack(alignment: .leading) {
                Capsule().fill(BoothTheme.elevated)
                Capsule()
                    .fill(BoothTheme.secondary)
                    .frame(width: 10)
                    .offset(x: max(0, min(geo.size.width - 10, geo.size.width * ratio - 5)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let next = Double(value.location.x / max(geo.size.width, 1)) * 2 - 1
                        track.wrappedValue.pan = max(-1, min(1, next))
                    }
            )
        }
        .frame(height: 8)
    }

    private func muteSoloButton(_ title: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? color : BoothTheme.secondary)
                .frame(width: 28, height: 24)
                .background(active ? color.opacity(0.16) : BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(BoothTheme.surface))
            let seconds = Int(episode.timelineDuration)
            var ticks = Path()
            for s in stride(from: 0, through: seconds, by: 5) {
                let x = CGFloat(s) * pixelsPerSecond
                ticks.move(to: CGPoint(x: x, y: s % 10 == 0 ? 16 : 22))
                ticks.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(ticks, with: .color(BoothTheme.hairline), lineWidth: 1)
            for s in stride(from: 0, through: seconds, by: 10) {
                let label = Text(TimeCode.format(TimeInterval(s)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BoothTheme.secondary)
                context.draw(label, at: CGPoint(x: CGFloat(s) * pixelsPerSecond + 4, y: 8), anchor: .topLeading)
            }
        }
        .frame(width: width, height: rulerHeight)
        .contentShape(Rectangle())
        .onTapGesture { location in
            let t = TimeInterval(location.x / pixelsPerSecond)
            if t >= 0 {
                onSeek(min(max(0, t), episode.timelineDuration))
            }
        }
    }

    private func clipLane(track: Binding<Track>, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            BoothTheme.canvas
            if hoverTrackID == track.wrappedValue.id {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BoothTheme.trackColor(track.wrappedValue.kind).opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(BoothTheme.trackColor(track.wrappedValue.kind).opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    )
                    .padding(4)
            }
            ForEach(track.wrappedValue.clips) { clip in
                clipBlock(clip, track: track.wrappedValue)
            }
        }
        .frame(width: width, height: trackHeight, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().background(BoothTheme.hairline) }
    }

    private func clipBlock(_ clip: Clip, track: Track) -> some View {
        let x = CGFloat(clip.startOnTimeline) * pixelsPerSecond
        let w = max(28, CGFloat(clip.duration) * pixelsPerSecond)
        let selected = selectedClipID == clip.id
        let dragging = draggingClipID == clip.id
        let previewKind = dragging ? (episode.tracks.first(where: { $0.id == hoverTrackID })?.kind ?? track.kind) : track.kind
        let trackColor = BoothTheme.trackColor(previewKind)
        let fileURL = mediaRoot.boothFile(clip.playbackFilename)
        let bars = min(120, max(24, Int(w / 4)))
        return FileWaveform(url: fileURL, color: trackColor, barCount: bars)
            .frame(width: w, height: trackHeight - clipInset * 2)
            .background(trackColor.opacity(dragging ? 0.42 : 0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .top) {
                Text(clip.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .padding(.horizontal, 6)
                    .lineLimit(1)
                    .frame(width: w, height: 22, alignment: .leading)
                    .background(Color.black.opacity(0.28))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                beginDrag(clip, on: track, translation: value.translation)
                            }
                            .onEnded { value in
                                finishDrag(clip, from: track, translation: value.translation)
                            }
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected || dragging ? Color.white : trackColor.opacity(0.7), lineWidth: selected || dragging ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: dragging ? .black.opacity(0.45) : .clear, radius: 12, y: 6)
            .overlay(alignment: .leading) {
                trimHandle(clip: clip, edge: .start)
            }
            .overlay(alignment: .trailing) {
                trimHandle(clip: clip, edge: .end)
            }
            .frame(width: w, height: trackHeight - clipInset * 2)
            .offset(x: x + (dragging ? dragOffsetX : 0), y: clipInset + (dragging ? dragOffsetY : 0))
            .zIndex(dragging ? 50 : 0)
            .onTapGesture { selectedClipID = clip.id }
            .contextMenu {
                Button("Böl") {
                    onCheckpoint()
                    episode.splitClip(clip.id, at: playhead)
                }
                Menu("Katmana taşı") {
                    ForEach(episode.tracks) { destination in
                        Button(destination.name) {
                            onCheckpoint()
                            episode.moveClip(clip.id, to: destination.id)
                        }
                        .disabled(destination.id == track.id)
                    }
                }
                Button("Sil", role: .destructive) {
                    onCheckpoint()
                    episode.removeClip(clip.id)
                }
                Button("Ripple sil", role: .destructive) {
                    onCheckpoint()
                    episode.removeClip(clip.id, ripple: true)
                }
            }
    }

    private func beginDrag(_ clip: Clip, on track: Track, translation: CGSize) {
        selectedClipID = clip.id
        draggingClipID = clip.id
        dragOffsetX = translation.width
        dragOffsetY = translation.height
        if dragOrigins[clip.id] == nil {
            onCheckpoint()
            dragOrigins[clip.id] = clip.startOnTimeline
        }
        if let source = episode.tracks.firstIndex(where: { $0.id == track.id }) {
            hoverTrackID = destinationTrack(from: source, translationY: translation.height)?.id
        }
    }

    private func finishDrag(_ clip: Clip, from track: Track, translation: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let origin = dragOrigins[clip.id] ?? clip.startOnTimeline
            var next = origin + TimeInterval(translation.width / pixelsPerSecond)
            next = max(0, next)
            if snapEnabled { next = (next * 10).rounded() / 10 }
            episode.updateClip(clip.id) { $0.startOnTimeline = next }
            if let source = episode.tracks.firstIndex(where: { $0.id == track.id }),
               let destination = destinationTrack(from: source, translationY: translation.height),
               destination.id != track.id {
                episode.moveClip(clip.id, to: destination.id)
            }
            dragOrigins[clip.id] = nil
            draggingClipID = nil
            dragOffsetX = 0
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
        Rectangle()
            .fill(BoothTheme.canvas)
            .frame(width: width, height: addLaneHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .foregroundStyle(BoothTheme.hairline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            .allowsHitTesting(false)
    }

    private func playheadLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(BoothTheme.accent)
            .frame(width: 2, height: height)
            .offset(x: CGFloat(playhead) * pixelsPerSecond)
            .allowsHitTesting(false)
    }

    private func markersOverlay(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(episode.markers) { marker in
                Rectangle()
                    .fill(marker.isChapter ? BoothTheme.music : BoothTheme.accent)
                    .frame(width: 2, height: height)
                    .offset(x: CGFloat(marker.time) * pixelsPerSecond)
                    .overlay(alignment: .top) {
                        Text(marker.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(BoothTheme.text)
                            .offset(x: 6, y: 2)
                    }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func trimHandle(clip: Clip, edge: TrimEdge) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.85))
            .frame(width: 8, height: trackHeight - 24)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        selectedClipID = clip.id
                        if trimOrigins[clip.id] == nil {
                            onCheckpoint()
                            trimOrigins[clip.id] = (clip.sourceOffset, clip.duration, clip.startOnTimeline)
                        }
                        guard let origin = trimOrigins[clip.id] else { return }
                        episode.updateClip(clip.id) { current in
                            current.sourceOffset = origin.offset
                            current.duration = origin.duration
                            current.startOnTimeline = origin.start
                        }
                        let delta = TimeInterval(value.translation.width / pixelsPerSecond)
                        let snapped = snapEnabled ? (delta * 10).rounded() / 10 : delta
                        episode.trimClip(clip.id, edge: edge, delta: snapped)
                    }
                    .onEnded { _ in
                        trimOrigins[clip.id] = nil
                    }
            )
    }
}
