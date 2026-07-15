import Foundation

/// Encodes 16 kHz mono Float32 samples into a 16-bit PCM WAV `Data` blob for
/// upload to cloud STT (Groq's `/audio/transcriptions`). A WAV at the model's
/// native rate avoids a server-side transcode and keeps latency low.
public enum WAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }

        // RIFF header
        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        // fmt chunk (PCM)
        ascii("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bitsPerSample))
        // data chunk
        ascii("data"); u32(UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let scaled = Int16(clamped * Float(Int16.max))
            u16(UInt16(bitPattern: scaled))
        }
        return data
    }
}
