import AVFoundation
import Foundation

// LAME's C functions, linked in from .build/lame/libmp3lame.a (make-lame.sh).
// Declared here instead of through lame.h: these few are all Clipout needs.
@_silgen_name("lame_init") private func lame_init() -> OpaquePointer?
@_silgen_name("lame_close") private func lame_close(_ flags: OpaquePointer?) -> Int32
@_silgen_name("lame_set_in_samplerate") private func lame_set_in_samplerate(_ flags: OpaquePointer?, _ rate: Int32) -> Int32
@_silgen_name("lame_set_num_channels") private func lame_set_num_channels(_ flags: OpaquePointer?, _ channels: Int32) -> Int32
@_silgen_name("lame_set_mode") private func lame_set_mode(_ flags: OpaquePointer?, _ mode: Int32) -> Int32
@_silgen_name("lame_set_brate") private func lame_set_brate(_ flags: OpaquePointer?, _ kbps: Int32) -> Int32
@_silgen_name("lame_set_quality") private func lame_set_quality(_ flags: OpaquePointer?, _ quality: Int32) -> Int32
@_silgen_name("lame_init_params") private func lame_init_params(_ flags: OpaquePointer?) -> Int32
@_silgen_name("lame_encode_buffer_ieee_float")
private func lame_encode_buffer_ieee_float(_ flags: OpaquePointer?, _ left: UnsafePointer<Float>?,
                                           _ right: UnsafePointer<Float>?, _ samples: Int32,
                                           _ out: UnsafeMutablePointer<UInt8>?, _ size: Int32) -> Int32
@_silgen_name("lame_encode_flush")
private func lame_encode_flush(_ flags: OpaquePointer?, _ out: UnsafeMutablePointer<UInt8>?, _ size: Int32) -> Int32

/// MP3 through LAME. AnkiWeb plays only MP3, and macOS can encode AAC but
/// not MP3.
enum MP3Encoder {
    /// 64 kbit/s mono: the system voices deliver 22 kHz mono speech, which
    /// sounds the same as the AAC Clipout wrote before, at the same size.
    static func write(_ buffers: [AVAudioPCMBuffer], to url: URL) -> Bool {
        guard let first = buffers.first else { return false }
        let rate = first.format.sampleRate
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                       channels: 1, interleaved: false) else { return false }
        // The voice may deliver Int16 or several channels: LAME gets float mono.
        var samples: [Float] = []
        for buffer in buffers where buffer.format.sampleRate == rate {
            guard let converted = convert(buffer, to: mono), let data = converted.floatChannelData else { continue }
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
        }
        guard !samples.isEmpty, let flags = lame_init() else { return false }
        defer { _ = lame_close(flags) }
        _ = lame_set_in_samplerate(flags, Int32(rate))
        _ = lame_set_num_channels(flags, 1)
        _ = lame_set_mode(flags, 3)            // MONO
        _ = lame_set_brate(flags, 64)
        _ = lame_set_quality(flags, 2)         // near best; speech is short
        guard lame_init_params(flags) >= 0 else { return false }

        // LAME's own worst case: 1.25 × samples + 7200 bytes.
        var mp3 = [UInt8](repeating: 0, count: samples.count * 5 / 4 + 7200)
        let written = samples.withUnsafeBufferPointer { pcm in
            mp3.withUnsafeMutableBufferPointer { out in
                lame_encode_buffer_ieee_float(flags, pcm.baseAddress, pcm.baseAddress, Int32(samples.count),
                                              out.baseAddress, Int32(out.count))
            }
        }
        guard written >= 0 else { return false }
        var tail = [UInt8](repeating: 0, count: 7200)
        let flushed = tail.withUnsafeMutableBufferPointer { lame_encode_flush(flags, $0.baseAddress, Int32($0.count)) }
        guard flushed >= 0 else { return false }
        let data = Data(mp3[..<Int(written)]) + Data(tail[..<Int(flushed)])
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        guard let check = try? AVAudioFile(forReading: url), check.length > 0 else { return false }
        return true
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else { return nil }
        do {
            try converter.convert(to: out, from: buffer)
        } catch {
            return nil
        }
        return out
    }

    /// Decodes any audio file macOS can read (e.g. an older .m4a card).
    static func buffers(from url: URL) -> [AVAudioPCMBuffer]? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { return nil }
        return [buffer]
    }
}
