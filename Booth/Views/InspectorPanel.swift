import SwiftUI

struct InspectorPanel: View {
    @Binding var episode: Episode
    var clipID: UUID
    var playhead: TimeInterval
    var mediaRoot: URL

    private var clip: Clip? { episode.clip(id: clipID) }

    var body: some View {
        Group {
            if let clip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Seçili: \(clip.name)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BoothTheme.text)

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

                        HStack {
                            Button("Böl") { episode.splitClip(clip.id, at: playhead) }
                                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                            Button("Sil", role: .destructive) { episode.removeClip(clip.id) }
                                .buttonStyle(BoothButtonStyle(fill: BoothTheme.accent.opacity(0.2), foreground: BoothTheme.accent))
                        }

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
        }
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
