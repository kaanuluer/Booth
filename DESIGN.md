# Booth — iPad Podcast Studio

Kaydet. Yerleştir. Yayına hazırla.

Booth, iPad’de tek başına bir bölümü bitirmeye yeten sade bir podcast stüdyosudur. Logic kadar kalabalık değildir. Ferrite kadar dokunmatiktir. Hedef: konuşmayı kaydetmek, ses dosyalarını katmanlara yerleştirmek, temel efektleri uygulamak ve tek bir yayın dosyası almak.

## Konumlandırma

| | |
|---|---|
| Platform | iPadOS 18+, landscape-first (11" ve 13") |
| Dil | Türkçe arayüz |
| Kategori | Music / Audio Production |
| Rakip referans | Ferrite (dokunuş), Logic for iPad (kalite), Riverside (kayıt) — hiçbiri kopyalanmaz |
| V1 dışı | Video, uzak konuk kaydı, MIDI, 12 bant EQ, otomasyon eğrileri |

## Ürün ilkeleri

1. Ekranda tek iş: kaydet, yerleştir veya dışa aktar.
2. Dalga formu içeriktir; chrome sessiz kalır.
3. 44pt dokunma alanları. Apple Pencil ile klip kenarları.
4. En fazla 6 katman. Plugin rafı yok.
5. Dışa aktarma, yayın standardına (-16 LUFS) otomatik hizalanır.

## Kullanıcı akışı

```
Bölümler  →  Kayıt kabini  →  Zaman çizelgesi  →  Klip efektleri  →  Yayına hazırla
   │              │                 │
   └──────── ses ekle / iCloud ─────┘
```

1. **Yeni bölüm** oluştur.
2. Konuşmayı **kabinde kaydet** (take’ler Konuşma katmanına düşer).
3. Intro, müzik, sting gibi dosyaları **Klipler** panosundan sürükle; zaman çizelgesinde **yerleştir, kes, fade**.
4. Seçili klipe **Ses / EQ / Gürültü / Kompresör** uygula.
5. **Yayına hazırla**: katmanlar tek AAC/WAV dosyasında birleşir.

## Ekranlar

| Ekran | İş |
|---|---|
| Bölümler | Taslak / Düzenleme / Hazır. Yeni bölüm. |
| Kayıt | Odaklanmış kabin. Take’ler. Marker. USB mic seviyesi. |
| Zaman çizelgesi | Katmanlı edit. Klip kütüphanesi. Denetçi. |
| Efektler | Klip bazlı 4 temel efekt. |
| Yayına hazırla | Mixdown, LUFS, format, Dosyalar / Paylaş. |

Mockup’lar: `design/screens/`

## Katman modeli

| Katman | Renk | Tipik içerik |
|---|---|---|
| Konuşma | Teal `#5EC8C5` | Take’ler, ana sohbet |
| Müzik | Amber `#E8A54B` | Intro bed, outro |
| Efekt | Violet `#8B7CFF` | Whoosh, sting |
| (opsiyonel) | — | Reklam, ortam, yedek |

Klip işlemleri: sürükle (yer), trim, böl, kes, fade in/out, mute/solo, ses seviyesi.

## Temel efektler (klipe özel)

- **Ses** — kazanç, fade in, fade out
- **EQ** — Bas / Orta / Tiz + hazır: Konuşma, Radyo, Düz
- **Gürültü azaltma** — tek miktar kaydırıcısı
- **Kompresör** — Kapalı, Doğal, Podcast, Yayın

Reverb ve delay V1’de yok. Mix bus’ta yalnızca podcast normalizasyonu var.

## Veri modeli

```
Episode
  id, title, status, createdAt, duration
  tracks: [Track]
  markers: [Marker]

Track
  id, name, kind (voice|music|sfx|aux), color, muted, solo, volume

Clip
  id, trackId, sourceURL, startOnTimeline, offsetInSource, duration
  gain, fadeIn, fadeOut
  effects: { eq, noise, compressor }

RecordingTake → Clip on voice track
ImportedFile  → Clip on chosen track
```

Yerel saklama: Application Support + FileManager. Proje JSON + ses dosyaları. iCloud Drive isteğe bağlı sonraki sürüm.

## Teknik omurga (SwiftUI)

| Katman | API |
|---|---|
| UI | SwiftUI, NavigationSplitView, iPad pointer + Pencil |
| Kayıt | AVAudioRecorder / AVAudioEngine input tap, 48 kHz |
| Oynatma / mix | AVAudioEngine, her klip için player node |
| Efekt | AVAudioUnitEQ, AVAudioUnitEffect (dynamics), noise gate / DSP |
| İçe aktar | UniformTypeIdentifiers + FileImporter (m4a, wav, aiff, mp3) |
| Dışa aktar | Offline render → AAC 256 kbps veya WAV, -16 LUFS |

## iPad davranışları

- Landscape birincil. Portrait’te kayıt kabini tam ekran, timeline kayar.
- Stage Manager ve Split View: timeline daralınca kütüphane kapanır.
- Mikrofon izni kayıt ekranında, tek cümle açıklama.
- Arka plan kaydı: `audio` background mode, kırmızı status pill.

## V1 kapsamı

Dahil: kayıt, take’ler, içe aktarma, 6 katmana kadar yerleştirme, trim/split/fade, 4 efekt, mixdown, paylaşım.

Hariç: çoklu uzak konuk, video, transkript, AI kesme, App Store yayınlama, abonelik.

## Uygulama

SwiftUI iPad projesi `Booth.xcodeproj`. Xcode’da scheme **Booth**, hedef iPad.

Dahil: kayıt, take’ler, içe aktarma, 6 katmana kadar yerleştirme, trim/split/fade, 4 efekt, mixdown, paylaşım.
