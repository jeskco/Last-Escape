import AVFoundation

/// Fully synthesised sound: twin-turbo V8, intake roar, turbo whistle, tyres, wind, horn and one-shot effects.
final class GameAudio {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sr: Float = 44100
    private var started = false

    // Parameters written by the game loop
    var rpm: Float = 1000
    var throttle: Float = 0
    var boost: Float = 0
    var slip: Float = 0
    var speed: Float = 0
    var offroad = false
    var active = false
    var horn = false
    var volume: Float = 0.8
    var trafficLevel: Float = 0

    private struct Biquad {
        var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        mutating func set(lowpass f: Float, q: Float, sr: Float) {
            let w = 2 * Float.pi * min(f, sr * 0.45) / sr, al = sin(w) / (2 * q), c = cos(w), a0 = 1 + al
            b0 = (1 - c) / 2 / a0; b1 = (1 - c) / a0; b2 = b0; a1 = -2 * c / a0; a2 = (1 - al) / a0
        }
        mutating func set(bandpass f: Float, q: Float, sr: Float) {
            let w = 2 * Float.pi * min(f, sr * 0.45) / sr, al = sin(w) / (2 * q), c = cos(w), a0 = 1 + al
            b0 = al / a0; b1 = 0; b2 = -al / a0; a1 = -2 * c / a0; a2 = (1 - al) / a0
        }
        @inline(__always) mutating func run(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private struct Burst { var filter = Biquad(); var gain: Float; var decay: Float; var tone: Float; var tonePhase: Float = 0; var toneGain: Float; var toneDecay: Float; var life: Int }

    // Synth state (audio thread only)
    private var ph1: Float = 0, ph2: Float = 0, ph3: Float = 0, phT: Float = 0, phS: Float = 0, phH1: Float = 0, phH2: Float = 0, phO: Float = 0
    private var engLP = Biquad(), roarBP = Biquad(), sqBP = Biquad(), windLP = Biquad(), hornLP = Biquad()
    private var gEng: Float = 0, gRoar: Float = 0, gTurbo: Float = 0, gSq: Float = 0, gWind: Float = 0, gHorn: Float = 0, gOther: Float = 0
    private var sRpm: Float = 1000, sBoost: Float = 0
    private var seed: UInt32 = 22222
    private var bursts: [Burst] = []
    private var queued: [Burst] = []
    private let lock = NSLock()

    @inline(__always) private func noise() -> Float {
        seed = seed &* 1664525 &+ 1013904223
        return Float(seed >> 8) / Float(1 << 23) - 1
    }

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let out = engine.outputNode.outputFormat(forBus: 0)
        sr = Float(out.sampleRate > 0 ? out.sampleRate : 44100)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 1) else { return }
        hornLP.set(lowpass: 2200, q: 0.7, sr: sr)
        let n = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, abl -> OSStatus in
            self.render(Int(frameCount), UnsafeMutableAudioBufferListPointer(abl))
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1
        do { try engine.start() } catch { started = false }
    }

    func stop() { engine.pause() }
    func resume() { if started { try? engine.start() } }

    private func render(_ frames: Int, _ buffers: UnsafeMutableAudioBufferListPointer) {
        lock.lock(); if !queued.isEmpty { bursts.append(contentsOf: queued); queued.removeAll() }; lock.unlock()
        if bursts.count > 10 { bursts.removeFirst(bursts.count - 10) }
        let act: Float = active ? 1 : 0
        let thr = throttle
        // Per-buffer parameter smoothing
        let k: Float = 0.25
        sRpm += (rpm - sRpm) * 0.5
        sBoost += (boost - sBoost) * 0.2
        let f = max(30, sRpm / 30)
        engLP.set(lowpass: 260 + thr * 2600 + sRpm * 0.22, q: 3, sr: sr)
        roarBP.set(bandpass: f * 3, q: 1.2, sr: sr)
        sqBP.set(bandpass: 1150, q: 9, sr: sr)
        windLP.set(lowpass: offroad ? 260 : 380 + speed * 6, q: 0.7, sr: sr)
        gEng += ((0.12 + thr * 0.16) * act - gEng) * k
        gRoar += (thr * 0.06 * (0.4 + sRpm / 7750) * act - gRoar) * k
        gTurbo += (sBoost * 0.018 * act - gTurbo) * k
        gSq += (min(0.22, max(0, slip - 0.18) * 0.5) * act - gSq) * k
        gWind += ((min(0.2, (speed / 90) * (speed / 90) * 0.2) + (offroad && speed > 3 ? 0.08 : 0)) * act - gWind) * 0.1
        gHorn += ((horn ? 0.5 : 0) - gHorn) * 0.5
        gOther += (trafficLevel * 0.04 * act - gOther) * 0.1
        let d1 = f / sr, d2 = f * 0.5 / sr, d3 = f * 2 / sr
        let dT = (1800 + sBoost * 4200) / sr, dS = 880 / sr, dH1: Float = 415 / sr, dH2: Float = 494 / sr, dO: Float = 95 / sr
        let vol = volume
        for buf in buffers {
            guard let out = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frames {
                ph1 += d1; if ph1 >= 1 { ph1 -= 1 }
                ph2 += d2; if ph2 >= 1 { ph2 -= 1 }
                ph3 += d3; if ph3 >= 1 { ph3 -= 1 }
                let raw = (2 * ph1 - 1) * 0.5 + (ph2 < 0.5 ? 0.35 : -0.35) + (2 * ph3 - 1) * 0.12
                var s = engLP.run(tanh(raw * 2.4)) * gEng
                let nz = noise()
                s += roarBP.run(nz) * gRoar * 3
                phT += dT; if phT >= 1 { phT -= 1 }
                s += sin(phT * 2 * .pi) * gTurbo
                phS += dS; if phS >= 1 { phS -= 1 }
                let tri = 1 - 4 * abs(phS - 0.5)
                s += sqBP.run(nz * 0.8 + tri * 0.25) * gSq * 4
                s += windLP.run(nz) * gWind
                phO += dO; if phO >= 1 { phO -= 1 }
                s += (2 * phO - 1) * gOther
                if gHorn > 0.001 {
                    phH1 += dH1; if phH1 >= 1 { phH1 -= 1 }
                    phH2 += dH2; if phH2 >= 1 { phH2 -= 1 }
                    s += hornLP.run(((phH1 < 0.5 ? 0.12 : -0.12) + (phH2 < 0.5 ? 0.12 : -0.12))) * gHorn
                }
                var j = 0
                while j < bursts.count {
                    var b = bursts[j]
                    s += b.filter.run(noise()) * b.gain
                    b.gain *= b.decay
                    if b.tone > 0 { b.tonePhase += b.tone / sr; if b.tonePhase >= 1 { b.tonePhase -= 1 }; s += sin(b.tonePhase * 2 * .pi) * b.toneGain; b.toneGain *= b.toneDecay; b.tone *= 0.99997 }
                    b.life -= 1
                    bursts[j] = b
                    j += 1
                }
                out[i] = tanh(s * 1.4) * vol
            }
        }
        bursts.removeAll { $0.life <= 0 }
    }

    private func burst(freq: Float, q: Float, dur: Float, gain: Float, lowpass: Bool = false, tone: Float = 0) {
        guard started else { return }
        var f = Biquad()
        if lowpass { f.set(lowpass: freq, q: q, sr: sr) } else { f.set(bandpass: freq, q: q, sr: sr) }
        let n = Int(dur * sr)
        let decay = pow(0.001, 1 / Float(max(n, 1)))
        let b = Burst(filter: f, gain: gain * (lowpass ? 1 : 3), decay: decay, tone: tone, toneGain: tone > 0 ? gain * 0.6 : 0, toneDecay: decay, life: n)
        lock.lock(); queued.append(b); lock.unlock()
    }

    func blowoff() { burst(freq: 3200, q: 0.9, dur: 0.45, gain: 0.22) }
    func backfire() { burst(freq: 380, q: 0.7, dur: 0.12, gain: 0.55, lowpass: true, tone: 90) }
    func shiftClick() { burst(freq: 900, q: 2, dur: 0.06, gain: 0.25) }
    func crash(_ p: Float) {
        burst(freq: 260, q: 0.5, dur: 0.5 + p * 0.4, gain: 0.35 + p * 0.5, lowpass: true, tone: 70)
        burst(freq: 4200, q: 0.8, dur: 0.25, gain: 0.15 * p)
        burst(freq: 6500, q: 1.5, dur: 0.6, gain: 0.08 * p)
    }
    func scrape(_ p: Float) { burst(freq: 2600, q: 3, dur: 0.12, gain: 0.08 * p) }
    func thud(_ p: Float) { burst(freq: 180, q: 0.6, dur: 0.25, gain: 0.3 * p, lowpass: true, tone: 55) }
    func splash() { burst(freq: 1200, q: 0.4, dur: 1.1, gain: 0.5, lowpass: true) }
    func chime() { burst(freq: 1320, q: 30, dur: 0.5, gain: 0.25) }
}
