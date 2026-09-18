import SwiftUI

struct InspectorPanel: View {
    @Binding var episode: Episode
    var clipID: UUID
    var playhead: TimeInterval
    var mediaRoot: URL
    @EnvironmentObject private var store: EpisodeStore
    @State private var enhanceError: String?

    private var clip: Clip? { episode.clip(id: clipID) }

    var body: some View {
        Group {
            if let clip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Klip adı", text: nameBinding(clip))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BoothTheme.text)
                            .textFieldStyle(.plain)

                        metric("Başlangıç", TimeCode.format(clip.startOnTimeline))
                        metric("Süre", TimeCode.format(clip.duration))
                        metric("Bitiş", TimeCode.format(clip.endTime))

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Ses")
                                Spacer()
                                Text(TimeCode.decibels(clip.gainDB))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(BoothTheme.secondary)
                            }
                            .foregroundStyle(BoothTheme.text)
                            Slider(value: gainBinding(clip), in: -12...12)
                        }

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Fade in").font(.system(size: 12)).foregroundStyle(BoothTheme.secondary)
                                Stepper(TimeCode.short(clip.fadeIn), value: fadeBinding(clip, \.fadeIn), in: 0...5, step: 0.1)
                            }
                            VStack(alignment: .leading) {
                                Text("Fade out").font(.system(size: 12)).foregroundStyle(BoothTheme.secondary)
                                Stepper(TimeCode.short(clip.fadeOut), value: fadeBinding(clip, \.fadeOut), in: 0...5, step: 0.1)
                            }
                        }
                        .foregroundStyle(BoothTheme.text)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Katman")
                                .font(.system(size: 12))
                                .foregroundStyle(BoothTheme.secondary)
                            Picker("Katman", selection: trackMoveBinding(clip)) {
                                ForEach(episode.tracks) { track in
                                    Text(track.name).tag(track.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(BoothTheme.text)
                        }

                        HStack {
                            Button("Böl") {
                                store.checkpoint(episode)
                                episode.splitClip(clip.id, at: playhead)
                            }
                                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                            Button("Sil", role: .destructive) {
                                store.checkpoint(episode)
                                episode.removeClip(clip.id)
                            }
                                .buttonStyle(BoothButtonStyle(fill: BoothTheme.accent.opacity(0.2), foreground: BoothTheme.accent))
                        }
                        Button("Ripple sil") {
                            store.checkpoint(episode)
                            episode.removeClip(clip.id, ripple: true)
                        }
                        .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                        Button("Önceki boşluğu sil") {
                            guard let gap = episode.gap(before: clip.id) else { return }
                            store.checkpoint(episode)
                            episode.closeGap(on: gap.trackID, start: gap.start, duration: gap.duration)
                        }
                        .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                        .disabled(episode.gap(before: clip.id) == nil)
                        Button("Katmandaki boşlukları kapat") {
                            guard let trackID = episode.track(containing: clip.id)?.id else { return }
                            store.checkpoint(episode)
                            episode.closeGaps(on: trackID)
                        }
                        .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                        .disabled(episode.track(containing: clip.id).map { MixMath.gaps(in: $0.clips).isEmpty } ?? true)
                        Button("Sessizliği oy") {
                            stripSilence(clip)
                        }
                        .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                        Button("Transkript") {
                            transcribe(clip)
                        }
                        .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                        Button("Filler kes") {
                            store.checkpoint(episode)
                            episode.stripFillers(clipID: clip.id)
                            store.save(episode)
                        }
                        .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                        .disabled(clip.transcriptSegments.filter(\.isFiller).isEmpty)
                        if !clip.transcriptSegments.isEmpty {
                            Text(clip.transcriptSegments.map(\.text).joined(separator: " "))
                                .font(.system(size: 12))
                                .foregroundStyle(BoothTheme.secondary)
                        }
                        if let enhanceError {
                            Text(enhanceError)
                                .font(.system(size: 12))
                                .foregroundStyle(BoothTheme.accent)
                        }

                        Toggle("A/B orijinal", isOn: effectBinding(clip, \.bypassEffects))
                            .foregroundStyle(BoothTheme.text)
                            .tint(BoothTheme.accent)

                        Divider().background(BoothTheme.hairline)
                        Text("Efektler").font(.system(size: 16, weight: .semibold)).foregroundStyle(BoothTheme.text)
                        effects(clip)
                    }
                    .padding(16)
                }
            } else {
                Text("Klip seçin")
                    .foregroundStyle(BoothTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BoothTheme.surface)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(BoothTheme.secondary)
            Spacer()
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundStyle(BoothTheme.text)
        }
        .font(.system(size: 13))
    }

    private func effects(_ clip: Clip) -> some View {
        VStack(spacing: 12) {
            toggleRow("Voice Isolator", isOn: isolatorEnabledBinding(clip)) {
                Picker("Preset", selection: effectBinding(clip, \.isolatorPreset)) {
                    Text("Clean Vocals").tag(VoiceIsolatorPreset.cleanVocals)
                    Text("Lecture").tag(VoiceIsolatorPreset.lecture)
                }
                .pickerStyle(.segmented)
                Text(clip.effects.isolatorPreset.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(BoothTheme.secondary)
                labeledSlider("Miktar", value: effectBinding(clip, \.isolatorAmount), range: 0...1)
                Button(clip.enhancedFilename == nil ? "Temizle (gelişmiş izolasyon)" : "Temiz kopya var") {
                    enhance(clip)
                }
                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                .disabled(clip.enhancedFilename != nil)
            }
            toggleRow("High-pass", isOn: effectBinding(clip, \.highPassEnabled)) {
                labeledSlider("Kesim Hz", value: effectBinding(clip, \.highPassHz), range: 40...180)
            }
            toggleRow("De-esser", isOn: effectBinding(clip, \.deEssEnabled)) {
                labeledSlider("Miktar", value: effectBinding(clip, \.deEssAmount), range: 0...1)
            }
            toggleRow("EQ", isOn: effectBinding(clip, \.eqEnabled)) {
                Picker("EQ", selection: eqPresetBinding(clip)) {
                    ForEach(EQPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                labeledSlider("Bas", value: effectBinding(clip, \.bass), range: -6...6)
                labeledSlider("Orta", value: effectBinding(clip, \.mid), range: -6...6)
                labeledSlider("Tiz", value: effectBinding(clip, \.treble), range: -6...6)
            }
            toggleRow("Gürültü azaltma", isOn: effectBinding(clip, \.noiseEnabled)) {
                labeledSlider("Miktar", value: effectBinding(clip, \.noiseAmount), range: 0...1)
            }
            toggleRow("Yankı azaltma", isOn: effectBinding(clip, \.echoEnabled)) {
                Text("Kayıttaki oda yansımasını ve eko kuyruğunu keser.")
                    .font(.system(size: 12))
                    .foregroundStyle(BoothTheme.secondary)
                labeledSlider("Miktar", value: effectBinding(clip, \.echoAmount), range: 0...1)
            }
            toggleRow("Kompresör", isOn: effectBinding(clip, \.compressorEnabled)) {
                Picker("Kompresör", selection: effectBinding(clip, \.compressorPreset)) {
                    ForEach(CompressorPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                labeledSlider("Makeup", value: effectBinding(clip, \.makeupGainDB), range: 0...6)
            }

            mixCard
            markersCard
        }
    }

    private var mixCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mix").font(.system(size: 16, weight: .semibold)).foregroundStyle(BoothTheme.text)
            Toggle("Müzik ducking", isOn: $episode.mix.duckingEnabled)
            if episode.mix.duckingEnabled {
                labeledSlider("Ducking", value: $episode.mix.duckingAmount, range: 0...1)
            }
            Toggle("Auto-level konuşma", isOn: $episode.mix.autoLevelEnabled)
            Toggle("Limiter", isOn: $episode.mix.limiterEnabled)
            Toggle("Kayıtta Voice Isolation", isOn: $episode.mix.captureVoiceIsolation)
            ForEach($episode.tracks) { $track in
                HStack {
                    Text("\(track.name) pan")
                        .font(.system(size: 12))
                        .foregroundStyle(BoothTheme.secondary)
                    Slider(value: $track.pan, in: -1...1)
                }
            }
            labeledSlider("Crossfade sn", value: Binding(
                get: { episode.mix.crossfade },
                set: { episode.mix.crossfade = $0 }
            ), range: 0...0.2)
        }
        .foregroundStyle(BoothTheme.text)
        .padding(12)
        .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var markersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("İşaretler / Chapter").font(.system(size: 16, weight: .semibold)).foregroundStyle(BoothTheme.text)
            ForEach($episode.markers) { $marker in
                HStack {
                    TextField("Ad", text: $marker.label)
                        .textFieldStyle(.plain)
                    Toggle("Ch", isOn: $marker.isChapter)
                        .labelsHidden()
                    Text(TimeCode.short(marker.time))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BoothTheme.secondary)
                }
            }
            Button("Playhead’e işaret") {
                store.checkpoint(episode)
                episode.markers.append(Marker(time: playhead, label: "İşaret"))
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
        }
        .foregroundStyle(BoothTheme.text)
        .padding(12)
        .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleRow<Content: View>(_ title: String, isOn: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: isOn)
                .foregroundStyle(BoothTheme.text)
                .tint(BoothTheme.accent)
            if isOn.wrappedValue {
                content()
            }
        }
        .padding(12)
        .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(BoothTheme.secondary)
            Slider(value: value, in: range)
        }
    }

    private func gainBinding(_ clip: Clip) -> Binding<Double> {
        Binding(
            get: { clip.gainDB },
            set: { value in episode.updateClip(clip.id) { $0.gainDB = value } }
        )
    }

    private func fadeBinding(_ clip: Clip, _ keyPath: WritableKeyPath<Clip, TimeInterval>) -> Binding<TimeInterval> {
        Binding(
            get: { clip[keyPath: keyPath] },
            set: { value in episode.updateClip(clip.id) { $0[keyPath: keyPath] = value } }
        )
    }

    private func isolatorEnabledBinding(_ clip: Clip) -> Binding<Bool> {
        Binding(
            get: { clip.effects.isolatorPreset.isOn },
            set: { enabled in
                episode.updateClip(clip.id) { current in
                    current.effects.isolatorPreset = enabled ? .cleanVocals : .off
                    if enabled, current.effects.isolatorAmount < 0.15 {
                        current.effects.isolatorAmount = 0.75
                    }
                }
            }
        )
    }

    private func nameBinding(_ clip: Clip) -> Binding<String> {
        Binding(
            get: { clip.name },
            set: { value in episode.updateClip(clip.id) { $0.name = value } }
        )
    }

    private func transcribe(_ clip: Clip) {
        enhanceError = nil
        guard let url = mediaRoot.boothFile(clip.playbackFilename) else { return }
        Task {
            do {
                let result = try await SpeechTranscriber.transcribe(url: url)
                store.checkpoint(episode)
                episode.applyTranscript(clipID: clip.id, text: result.text, segments: result.segments)
                store.save(episode)
            } catch {
                enhanceError = error.localizedDescription
            }
        }
    }

    private func stripSilence(_ clip: Clip) {
        store.checkpoint(episode)
        guard let url = mediaRoot.boothFile(clip.playbackFilename) else { return }
        do {
            let loaded = try SpectralEnhancer.loadMono(url: url)
            let hop = max(32, Int(0.01 * loaded.sampleRate))
            let levels = SpectralEnhancer.frameLevels(samples: loaded.samples, hop: hop)
            let regions = MixMath.voicedRegions(
                levels: levels,
                sampleRate: loaded.sampleRate,
                hop: hop,
                threshold: 0.02,
                minSilence: 0.35,
                minKeep: 0.12
            )
            let local = regions.compactMap { region -> MixMath.Region? in
                let start = max(region.start, clip.sourceOffset) - clip.sourceOffset
                let end = min(region.end, clip.sourceOffset + clip.duration) - clip.sourceOffset
                guard end - start > 0.08 else { return nil }
                return MixMath.Region(start: start, duration: end - start)
            }
            if !local.isEmpty {
                episode.replaceClip(clip.id, with: local)
            }
        } catch {
            enhanceError = error.localizedDescription
        }
    }

    private func enhance(_ clip: Clip) {
        store.checkpoint(episode)
        let filename = "clean-\(clip.id.uuidString.prefix(8)).caf"
        guard let source = mediaRoot.boothFile(clip.filename),
              let dest = mediaRoot.boothFile(filename) else { return }
        do {
            try SpectralEnhancer.enhanceFile(
                at: source,
                to: dest,
                amount: clip.effects.isolatorAmount == 0 ? 0.75 : clip.effects.isolatorAmount,
                lecture: clip.effects.isolatorPreset == .lecture
            )
            MediaPath.protect(dest)
            episode.updateClip(clip.id) {
                $0.enhancedFilename = filename
                $0.effects.spectralEnhance = true
                if !$0.effects.isolatorPreset.isOn {
                    $0.effects.isolatorPreset = .cleanVocals
                }
            }
        } catch {
            enhanceError = error.localizedDescription
        }
    }

    private func trackMoveBinding(_ clip: Clip) -> Binding<UUID> {
        Binding(
            get: { episode.track(containing: clip.id)?.id ?? episode.tracks.first?.id ?? clip.id },
            set: { episode.moveClip(clip.id, to: $0) }
        )
    }

    private func eqPresetBinding(_ clip: Clip) -> Binding<EQPreset> {
        Binding(
            get: { clip.effects.eqPreset },
            set: { preset in
                episode.updateClip(clip.id) { $0.effects.apply(preset: preset) }
            }
        )
    }

    private func effectBinding<T>(_ clip: Clip, _ keyPath: WritableKeyPath<ClipEffects, T>) -> Binding<T> {
        Binding(
            get: { clip.effects[keyPath: keyPath] },
            set: { value in episode.updateClip(clip.id) { $0.effects[keyPath: keyPath] = value } }
        )
    }
}
