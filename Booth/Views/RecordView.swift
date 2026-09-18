import SwiftUI

struct RecordView: View {
    @Binding var episode: Episode
    var punchIn: Bool = false
    var punchAt: TimeInterval = 0
    @EnvironmentObject private var store: EpisodeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = RecorderEngine()
    @State private var errorMessage: String?
    @State private var lastURL: URL?
    @FocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            BoothTheme.canvas.ignoresSafeArea()
            VStack(spacing: 20) {
                header
                waveformStage
                takesRow
                transport
            }
            .padding(28)
        }
        .onAppear {
            recorder.refreshInputs()
        }
        .alert("Kayıt", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            if recorder.isRecording {
                finishTake()
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .frame(width: 44, height: 44)
                    .background(BoothTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Bölüm adı", text: $episode.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($titleFocused)
                    .onSubmit { episode.rename(to: episode.title) }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { episode.rename(to: episode.title) }
                    }
                Text(punchIn ? "Punch-in · Konuşma katmanı üzerine yazılır" : "Kayıt katmana eklenecek: Konuşma")
                    .font(.system(size: 13))
                    .foregroundStyle(BoothTheme.secondary)
            }
            Spacer()
            Toggle("Voice Isolation", isOn: $episode.mix.captureVoiceIsolation)
                .tint(BoothTheme.accent)
                .foregroundStyle(BoothTheme.text)
                .frame(maxWidth: 220)
            if !recorder.availableInputs.isEmpty {
                Picker("Giriş", selection: Binding(
                    get: { recorder.selectedInputUID ?? recorder.availableInputs.first?.uid ?? "" },
                    set: { recorder.selectInput($0.isEmpty ? nil : $0) }
                )) {
                    ForEach(recorder.availableInputs, id: \.uid) { input in
                        Text(input.portName).tag(input.uid)
                    }
                }
                .tint(BoothTheme.text)
                .frame(maxWidth: 180)
            }
            Label("48 kHz", systemImage: "mic.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BoothTheme.success)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(BoothTheme.success.opacity(0.12), in: Capsule())
        }
    }

    private var waveformStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BoothTheme.surface)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recorder.isRecording ? (punchIn ? "PUNCH-IN" : "CANLI KAYIT") : "HAZIR")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(recorder.isRecording ? BoothTheme.accent : BoothTheme.secondary)
                    Text(TimeCode.format(recorder.duration))
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(BoothTheme.text)
                    WaveformView(
                        samples: recorder.livePeaks.isEmpty ? [0.08, 0.12, 0.1] : recorder.livePeaks,
                        color: BoothTheme.voice
                    )
                    .frame(height: 180)
                }
                MeterBar(level: recorder.level)
                    .frame(height: 220)
                    .padding(.trailing, 8)
            }
            .padding(28)
        }
        .frame(maxHeight: .infinity)
    }

    private var takesRow: some View {
        let takes = episode.tracks.first(where: { $0.kind == .voice })?.clips ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(takes.enumerated()), id: \.element.id) { index, clip in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Take \(index + 1)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BoothTheme.text)
                        Text(TimeCode.short(clip.duration))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(BoothTheme.secondary)
                    }
                    .padding(14)
                    .frame(width: 160, alignment: .leading)
                    .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Yeni take")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BoothTheme.text)
                    Text(recorder.isRecording ? "Kaydediliyor" : "Boş")
                        .font(.system(size: 12))
                        .foregroundStyle(BoothTheme.secondary)
                }
                .padding(14)
                .frame(width: 160, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(recorder.isRecording ? BoothTheme.accent : BoothTheme.hairline, lineWidth: recorder.isRecording ? 2 : 1)
                )
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 16) {
            Button {
                episode.markers.append(Marker(time: (punchIn ? punchAt : 0) + recorder.duration, label: punchIn ? "Punch" : "İşaret"))
                store.save(episode)
            } label: {
                Label("Bayrak", systemImage: "flag")
                    .frame(minWidth: 110)
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
            .disabled(!recorder.isRecording)

            Button {
                if recorder.isPaused {
                    recorder.resume()
                } else if recorder.isRecording {
                    recorder.pause()
                }
            } label: {
                Label(recorder.isPaused ? "Devam" : "Duraklat", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
            .disabled(!recorder.isRecording)

            Button {
                toggleRecord()
            } label: {
                ZStack {
                    Circle().fill(BoothTheme.accent).frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 38, style: .continuous)
                        .fill(Color.white)
                        .frame(width: recorder.isRecording ? 28 : 30, height: recorder.isRecording ? 28 : 30)
                }
            }

            Button("Bitir") {
                if recorder.isRecording { finishTake() }
                dismiss()
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))

            Button("Yeniden al") {
                retake()
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
            .disabled(episode.tracks.first(where: { $0.kind == .voice })?.clips.isEmpty ?? true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func toggleRecord() {
        if recorder.isRecording {
            finishTake()
        } else {
            startTake()
        }
    }

    private func startTake() {
        let filename = store.uniqueFilename(in: episode, preferred: "take.m4a")
        let url = store.mediaURL(for: episode, filename: filename)
        do {
            try recorder.start(to: url, voiceIsolation: episode.mix.captureVoiceIsolation)
            lastURL = url
            episode.status = .recording
            store.save(episode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishTake() {
        let duration = recorder.stop()
        guard duration > 0.2, let url = lastURL else { return }
        let takeIndex = (episode.tracks.first(where: { $0.kind == .voice })?.clips.count ?? 0) + 1
        let asset = MediaAsset(
            filename: url.lastPathComponent,
            displayName: punchIn ? "Punch \(takeIndex)" : "Take \(takeIndex)",
            duration: duration,
            kindHint: .voice
        )
        episode.appendRecording(asset, duration: duration, at: punchIn ? punchAt : nil, punch: punchIn)
        store.save(episode)
        lastURL = nil
    }

    private func retake() {
        guard let clip = episode.tracks.first(where: { $0.kind == .voice })?.clips.last else { return }
        let url = store.mediaURL(for: episode, filename: clip.filename)
        try? FileManager.default.removeItem(at: url)
        episode.removeClip(clip.id)
        episode.library.removeAll { $0.filename == clip.filename }
        store.save(episode)
    }
}
