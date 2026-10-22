import Accelerate

/// Real FFT magnitudes (bins 0...n/2) using vDSP. Scale is irrelevant to callers (all ratios / log-flux).
final class RealFFT {
    let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var re: [Float]
    private var im: [Float]

    init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        n = size
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        re = [Float](repeating: 0, count: size / 2)
        im = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `frame` must have `n` samples (already windowed). Writes n/2+1 magnitudes into `out`.
    func magnitudes(_ frame: UnsafePointer<Float>, into out: inout [Float]) {
        if out.count != n / 2 + 1 { out = [Float](repeating: 0, count: n / 2 + 1) }
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cplx in
                    vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(n / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // zrip packs DC in realp[0] and Nyquist in imagp[0]; output is 2x the DFT.
                let dc = abs(rp[0]) * 0.5
                let ny = abs(ip[0]) * 0.5
                out.withUnsafeMutableBufferPointer { op in
                    for k in 1..<(n / 2) {
                        let a = rp[k], b = ip[k]
                        op[k] = (a * a + b * b).squareRoot() * 0.5
                    }
                    op[0] = dc
                    op[n / 2] = ny
                }
            }
        }
    }

    static func hann(_ size: Int) -> [Float] {
        // Matches the desktop: 0.5 * (1 - cos(2πi / (N - 1))).
        (0..<size).map { i in Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(size - 1)))) }
    }
}
