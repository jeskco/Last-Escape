import SwiftUI

/// Animated full-court replay driven by the play-by-play feed.
/// Each play runs as a short sequence (passes, shooter cut, shot, result). Positions other than the shooter
/// are an illustrative formation, not optical tracking.
struct BasketballCast: View {
    let match: Match
    let detail: MatchDetail?

    @State private var idx = 0
    @State private var playing = false
    @State private var speed = 1.0
    @State private var follow = true
    @State private var started = false
    @State private var playStart = Date()
    // Gliding between formations: 10 players.
    @State private var prevPts: [CGPoint] = []
    @State private var targetPts: [CGPoint] = []
    @State private var changedAt = Date.distantPast
    private let glide = 0.9

    private var plays: [CastPlay] { detail?.cast ?? [] }
    private var current: CastPlay? { plays.indices.contains(idx) ? plays[idx] : nil }

    // Court units: 94 x 50 feet.
    private let courtW = 94.0, courtH = 50.0

    var body: some View {
        VStack(spacing: 12) {
            if plays.isEmpty {
                VStack(spacing: 10) {
                    court(positions: [])
                    Text("The animated replay starts once the game has play-by-play data.")
                        .font(.footnote).foregroundStyle(Neon.textDim).multilineTextAlignment(.center)
                }
            } else {
                scoreBar
                court(positions: playerPositions())
                if let p = current {
                    Text(p.text).font(.footnote).foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading).neonCard()
                }
                controls
                MarginChart(plays: plays, index: idx, away: match.away, home: match.home)
                Text("Replay built from play-by-play. The shooter and ball are placed from the shot data; other players show a typical formation, not live tracking.")
                    .font(.caption2).foregroundStyle(Neon.textDim).multilineTextAlignment(.center)
            }
        }
        .onChange(of: plays.count) { _, new in
            guard new > 0 else { return }
            if !started { startReplay() }
        }
        .onAppear { if !plays.isEmpty && !started { startReplay() } }
        .onChange(of: idx) { _, _ in retarget() }
        .task(id: playing) {
            while playing && !Task.isCancelled {
                if idx >= plays.count - 1 {
                    // Live game: wait for the next play. Finished game: stop.
                    if match.state == .live { try? await Task.sleep(nanoseconds: 1_000_000_000); continue }
                    playing = false; break
                }
                await advance()
            }
        }
    }

    private func startReplay() {
        started = true
        idx = max(0, plays.count - 8)      // begin a few plays before the latest one and play forward
        playStart = Date()
        retarget(snap: true)
        playing = true
    }

    // MARK: Gliding

    private func blended(at date: Date) -> [CGPoint] {
        guard targetPts.count == prevPts.count, !targetPts.isEmpty else { return targetPts }
        let x = min(max(date.timeIntervalSince(changedAt) / (glide / max(speed, 0.5)), 0), 1)
        let e = 1 - pow(1 - x, 3)
        return zip(prevPts, targetPts).map { CGPoint(x: $0.x + ($1.x - $0.x) * e, y: $0.y + ($1.y - $0.y) * e) }
    }

    private func retarget(snap: Bool = false) {
        guard !plays.isEmpty else { return }
        let now = Date()
        let old = snap || targetPts.isEmpty ? nil : blended(at: now)
        let next = playerPositions().map { $0.pos }
        prevPts = old ?? next
        targetPts = next
        changedAt = snap ? .distantPast : now
    }

    // MARK: Playback

    private func isShot(_ p: CastPlay?) -> Bool {
        guard let p else { return false }
        return p.shooting || p.type.lowercased().contains("free throw")
    }

    private func duration(for p: CastPlay?) -> Double { isShot(p) ? 3.6 : 1.8 }

    private func advance() async {
        let s = max(speed, 0.5)
        idx += 1
        playStart = Date()
        try? await Task.sleep(nanoseconds: UInt64(duration(for: current) / s * 1_000_000_000))
    }

    private func jump(to i: Int) {
        idx = min(max(i, 0), max(plays.count - 1, 0))
        playStart = Date()
    }

    // MARK: Geometry

    private func possessionTeam(at index: Int) -> String? {
        var i = index
        while i >= 0 {
            let p = plays[i]
            let t = p.type.lowercased()
            if t.contains("turnover"), let team = p.teamId { return team == match.home.id ? match.away.id : match.home.id }
            if p.shooting || t.contains("rebound") || t.contains("free throw"), let team = p.teamId { return team }
            i -= 1
        }
        return nil
    }

    /// The away side attacks the right basket, the home side the left one.
    private var attackRight: Bool { possessionTeam(at: idx) != match.home.id }

    private func roster(_ teamId: String) -> [RosterPlayer] {
        let all = (detail?.roster ?? []).filter { $0.teamId == teamId }
        let ordered = all.filter { $0.starter } + all.filter { !$0.starter }
        return Array(ordered.prefix(5))
    }

    private func slots(right: Bool) -> (off: [CGPoint], def: [CGPoint]) {
        let off: [(Double, Double)] = [(63, 25), (74, 8), (74, 42), (83, 13), (82, 33)]
        let def: [(Double, Double)] = [(68, 25), (79, 12), (79, 38), (86, 19), (85, 31)]
        func f(_ s: (Double, Double)) -> CGPoint { CGPoint(x: right ? s.0 : courtW - s.0, y: s.1) }
        return (off.map(f), def.map(f))
    }

    /// 10 circles: first 5 = away, last 5 = home.
    private func playerPositions() -> [CourtPlayer] {
        let right = attackRight
        let sl = slots(right: right)
        let awayRoster = roster(match.away.id), homeRoster = roster(match.home.id)
        var out: [CourtPlayer] = []
        for k in 0..<5 {
            out.append(CourtPlayer(team: .away, jersey: k < awayRoster.count ? awayRoster[k].jersey : "",
                                   name: k < awayRoster.count ? awayRoster[k].name : "",
                                   pos: right ? sl.off[k] : sl.def[k]))
        }
        for k in 0..<5 {
            out.append(CourtPlayer(team: .home, jersey: k < homeRoster.count ? homeRoster[k].jersey : "",
                                   name: k < homeRoster.count ? homeRoster[k].name : "",
                                   pos: right ? sl.def[k] : sl.off[k]))
        }
        return out
    }

    /// Which of the five offensive players took this shot (matched on the name at the start of the play text).
    private func shooterSlot(_ p: CastPlay?) -> Int {
        guard let p else { return 4 }
        let team = roster(attackRight ? match.away.id : match.home.id)
        if let i = team.firstIndex(where: { !$0.name.isEmpty && p.text.hasPrefix($0.name) }) { return i }
        return 4
    }

    private func shotSpot(_ p: CastPlay) -> CGPoint {
        let right = attackRight
        if p.type.lowercased().contains("free throw") { return CGPoint(x: right ? 94 - 5.25 - 15 : 5.25 + 15, y: 25) }
        guard var x = p.x, var y = p.y else { return CGPoint(x: right ? 70 : 24, y: 25) }
        if y > 47 { y = 94 - y; x = 50 - x }
        x = min(max(x, 0), 50); y = min(max(y, 0), 47)
        return CGPoint(x: right ? 94 - y : y, y: right ? x : 50 - x)
    }

    private var basket: CGPoint { CGPoint(x: attackRight ? 94 - 5.25 : 5.25, y: 25) }

    private func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    /// Light off-ball movement so nobody ever stands completely still.
    private func sway(_ k: Int, _ t: Double, offense: Bool) -> CGPoint {
        let slot = Double(k % 5)
        let amp = offense ? 1.7 : 1.3
        let tt = t - (offense ? 0 : 0.4)
        return CGPoint(x: sin(tt * (0.8 + slot * 0.12) + slot * 1.9) * amp,
                       y: cos(tt * (0.6 + slot * 0.1) + slot * 2.7) * amp * 0.8)
    }

    private struct Frame { var players: [CGPoint]; var ball: CGPoint; var ballScale: CGFloat; var flash: Bool }

    private func frame(at date: Date, positions: [CourtPlayer]) -> Frame {
        let t = date.timeIntervalSinceReferenceDate
        let base = blended(at: date)
        var pts: [CGPoint] = positions.enumerated().map { i, p in
            let a = base.count > i ? base[i] : p.pos
            let m = sway(i, t, offense: (i < 5) == attackRight)
            return CGPoint(x: a.x + m.x, y: a.y + m.y)
        }
        guard pts.count == 10, let play = current else { return Frame(players: pts, ball: CGPoint(x: 47, y: 25), ballScale: 1, flash: false) }

        let s = date.timeIntervalSince(playStart) * max(speed, 0.5)
        let offBase = attackRight ? 0 : 5
        let shooting = isShot(play)
        let shooter = shooterSlot(play)
        let chainA = (shooter + 2) % 5, chainB = (shooter + 4) % 5
        func off(_ k: Int) -> CGPoint { pts[offBase + k] }

        var ball = off(chainA)
        var scale: CGFloat = 1
        var flash = false

        if shooting {
            let spot = shotSpot(play)
            // The shooter cuts to the shot location before shooting.
            let cut = ease((s - 0.9) / 0.9)
            let from = pts[offBase + shooter]
            pts[offBase + shooter] = CGPoint(x: from.x + (spot.x - from.x) * cut, y: from.y + (spot.y - from.y) * cut)
            let shooterPos = pts[offBase + shooter]
            let freeThrow = play.type.lowercased().contains("free throw")

            if freeThrow || s < 0.5 && false {
                ball = shooterPos
            } else if s < 0.5 {
                ball = dribble(off(chainA), s)
            } else if s < 1.0 {
                ball = lerp(off(chainA), off(chainB), ease((s - 0.5) / 0.4))
            } else if s < 1.6 {
                ball = lerp(off(chainB), shooterPos, ease((s - 1.0) / 0.4))
            } else if s < 2.0 {
                ball = dribble(shooterPos, s)
            }
            if freeThrow { ball = dribble(shooterPos, s) }
            if s >= 2.0 {
                let p = min((s - 2.0) / 0.7, 1)
                let hoop = basket
                ball = CGPoint(x: shooterPos.x + (hoop.x - shooterPos.x) * p,
                               y: shooterPos.y + (hoop.y - shooterPos.y) * p - sin(p * .pi) * 6)
                scale = 1 + CGFloat(sin(p * .pi)) * 0.7
                if p >= 1 {
                    if play.scoring {
                        flash = true
                        let drop = min((s - 2.7) / 0.4, 1)
                        ball = CGPoint(x: hoop.x, y: hoop.y + drop * 1.6)
                    } else {
                        // Rim out and bounce away toward where the rebound will be.
                        let q = min((s - 2.7) / 0.6, 1)
                        let out = CGPoint(x: hoop.x + (attackRight ? -6 : 6), y: hoop.y + (shooterPos.y > 25 ? 5 : -5))
                        ball = CGPoint(x: hoop.x + (out.x - hoop.x) * q, y: hoop.y + (out.y - hoop.y) * q - sin(q * .pi) * 2.5)
                    }
                }
            }
        } else {
            // Non-shot plays: hold the ball, make one pass.
            if s < 0.7 { ball = dribble(off(chainA), s) }
            else if s < 1.2 { ball = lerp(off(chainA), off(chainB), ease((s - 0.7) / 0.5)) }
            else { ball = dribble(off(chainB), s) }
        }
        return Frame(players: pts, ball: ball, ballScale: scale, flash: flash)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func dribble(_ p: CGPoint, _ s: Double) -> CGPoint {
        CGPoint(x: p.x + 1.3, y: p.y - abs(sin(s * 7)) * 1.2)
    }

    // MARK: UI

    private var scoreBar: some View {
        HStack {
            Text(match.away.short).font(.caption.weight(.heavy)).foregroundStyle(Neon.magenta)
            Text("\(current?.away ?? 0)").font(.title2.weight(.heavy).monospacedDigit())
            Spacer()
            VStack(spacing: 2) {
                Text("Q\(current?.period ?? 1)").font(.caption.weight(.bold)).foregroundStyle(Neon.cyan)
                Text(current?.clock ?? "").font(.headline.monospacedDigit())
            }
            Spacer()
            Text("\(current?.home ?? 0)").font(.title2.weight(.heavy).monospacedDigit())
            Text(match.home.short).font(.caption.weight(.heavy)).foregroundStyle(Neon.cyan)
        }
        .neonCard(highlight: match.state == .live)
    }

    private func court(positions: [CourtPlayer]) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let sx = w / courtW, sy = h / courtH
            TimelineView(.animation) { timeline in
                let f = frame(at: timeline.date, positions: positions)
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.09, blue: 0.13))
                    courtLines(w: w, h: h)
                    Circle().fill(f.flash ? Neon.cyan.opacity(0.55) : .clear)
                        .frame(width: 46, height: 46)
                        .position(x: basket.x * sx, y: basket.y * sy)
                    ForEach(Array(positions.enumerated()), id: \.offset) { i, p in
                        let color = p.team == .away ? Neon.magenta : Neon.cyan
                        ZStack {
                            Circle().fill(Neon.black).overlay(Circle().stroke(color, lineWidth: 2))
                            Text(p.jersey).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        }
                        .frame(width: 24, height: 24)
                        .shadow(color: color.opacity(0.9), radius: (p.team == .away) == attackRight ? 6 : 2)
                        .position(x: f.players[i].x * sx, y: f.players[i].y * sy)
                    }
                    if !positions.isEmpty {
                        Circle().fill(Color.orange).frame(width: 11, height: 11)
                            .scaleEffect(f.ballScale)
                            .shadow(color: .orange, radius: 5)
                            .position(x: f.ball.x * sx, y: f.ball.y * sy)
                    }
                }
            }
        }
        .aspectRatio(courtW / courtH, contentMode: .fit)
    }

    private func courtLines(w: CGFloat, h: CGFloat) -> some View {
        let line = Color.white.opacity(0.28)
        return ZStack {
            Rectangle().fill(line).frame(width: 1.5).position(x: w / 2, y: h / 2).frame(height: h)
            Circle().stroke(line, lineWidth: 1.5).frame(width: h * 0.24).position(x: w / 2, y: h / 2)
            ForEach([false, true], id: \.self) { right in
                let bx = right ? w * (1 - 5.25 / 94) : w * 5.25 / 94
                let laneX = right ? w * (1 - 19.0 / 94 / 2 * 1.0) : w * 19.0 / 94 / 2
                Rectangle().stroke(line, lineWidth: 1.5)
                    .frame(width: w * 19 / 94, height: h * 16 / 50)
                    .position(x: laneX, y: h / 2)
                Circle().stroke(line, lineWidth: 1.5).frame(width: h * 12 / 50).position(x: right ? w * (1 - 19.0 / 94) : w * 19.0 / 94, y: h / 2)
                Path { p in
                    let r = h * 23.75 / 50
                    p.addArc(center: CGPoint(x: bx, y: h / 2), radius: r,
                             startAngle: .degrees(right ? 112 : -68), endAngle: .degrees(right ? 248 : 68), clockwise: false)
                }.stroke(line, lineWidth: 1.5)
                Circle().stroke(Neon.magenta.opacity(0.9), lineWidth: 2).frame(width: 10).position(x: bx, y: h / 2)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button { jump(to: idx - 1); playing = false; follow = false } label: { Image(systemName: "backward.frame.fill") }
                Button {
                    if idx >= plays.count - 1 { jump(to: max(0, plays.count - 8)) }
                    playing.toggle(); follow = false
                } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34)).foregroundStyle(Neon.cyan)
                }
                Button { jump(to: idx + 1); playing = false; follow = false } label: { Image(systemName: "forward.frame.fill") }
                Spacer()
                Button { speed = speed >= 4 ? 1 : speed * 2 } label: {
                    Text("\(Int(speed))x").font(.caption.weight(.heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Neon.surfaceHigh, in: Capsule())
                }
                if match.state == .live {
                    Button { follow = true; jump(to: plays.count - 1); playing = true } label: {
                        Text("LIVE").font(.caption.weight(.heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(follow ? Neon.black : Neon.magenta)
                            .background(follow ? AnyShapeStyle(Neon.magenta) : AnyShapeStyle(Neon.magenta.opacity(0.15)), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            Slider(value: Binding(get: { Double(idx) }, set: { idx = Int($0); playStart = Date(); playing = false; follow = false }),
                   in: 0...Double(max(plays.count - 1, 1)))
                .tint(Neon.cyan)
        }
        .neonCard()
    }
}

private struct CourtPlayer {
    enum Team { case away, home }
    var team: Team
    var jersey: String
    var name: String
    var pos: CGPoint
}

private struct MarginChart: View {
    let plays: [CastPlay]
    let index: Int
    let away: Side
    let home: Side

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Score margin")
            Canvas { ctx, size in
                guard plays.count > 1 else { return }
                let margins = plays.map { Double($0.home - $0.away) }
                let m = max(margins.map { abs($0) }.max() ?? 1, 4)
                let mid = size.height / 2
                func pt(_ i: Int) -> CGPoint {
                    CGPoint(x: size.width * CGFloat(i) / CGFloat(plays.count - 1), y: mid - CGFloat(margins[i] / m) * (size.height / 2 - 4))
                }
                var up = Path(), down = Path()
                up.move(to: CGPoint(x: 0, y: mid)); down.move(to: CGPoint(x: 0, y: mid))
                for i in plays.indices {
                    let p = pt(i)
                    up.addLine(to: CGPoint(x: p.x, y: min(p.y, mid)))
                    down.addLine(to: CGPoint(x: p.x, y: max(p.y, mid)))
                }
                up.addLine(to: CGPoint(x: size.width, y: mid)); up.closeSubpath()
                down.addLine(to: CGPoint(x: size.width, y: mid)); down.closeSubpath()
                ctx.fill(up, with: .color(Neon.cyan.opacity(0.45)))
                ctx.fill(down, with: .color(Neon.magenta.opacity(0.45)))
                var zero = Path(); zero.move(to: CGPoint(x: 0, y: mid)); zero.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(zero, with: .color(.white.opacity(0.3)), lineWidth: 1)
                let x = pt(min(max(index, 0), plays.count - 1)).x
                var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 0)); cursor.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(cursor, with: .color(.white), lineWidth: 1.5)
            }
            .frame(height: 90)
            HStack {
                Text("\(away.short) lead").font(.caption2).foregroundStyle(Neon.magenta)
                Spacer()
                Text("\(home.short) lead").font(.caption2).foregroundStyle(Neon.cyan)
            }
        }
        .neonCard()
    }
}
