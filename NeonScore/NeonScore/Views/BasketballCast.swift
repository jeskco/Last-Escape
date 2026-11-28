import SwiftUI

/// Animated full-court replay driven by the play-by-play feed.
/// Player positions other than the shooter are an illustrative formation, not optical tracking.
struct BasketballCast: View {
    let match: Match
    let detail: MatchDetail?

    @State private var idx = 0
    @State private var playing = false
    @State private var speed = 1.0
    @State private var flying = false
    @State private var flash = false
    @State private var follow = true
    @State private var started = false
    // Gliding between formations: 10 players + ball.
    @State private var prevPts: [CGPoint] = []
    @State private var targetPts: [CGPoint] = []
    @State private var changedAt = Date.distantPast
    private let glide = 0.8

    private var plays: [CastPlay] { detail?.cast ?? [] }
    private var current: CastPlay? { plays.indices.contains(idx) ? plays[idx] : nil }

    // Court units: 94 x 50 feet.
    private let courtW = 94.0, courtH = 50.0

    var body: some View {
        VStack(spacing: 12) {
            if plays.isEmpty {
                VStack(spacing: 10) {
                    court(positions: [], ball: CGPoint(x: 47, y: 25))
                    Text("The animated replay starts once the game has play-by-play data.")
                        .font(.footnote).foregroundStyle(Neon.textDim).multilineTextAlignment(.center)
                }
            } else {
                scoreBar
                court(positions: playerPositions(), ball: ballPosition())
                if let p = current {
                    Text(p.text).font(.footnote).foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading).neonCard()
                }
                controls
                MarginChart(plays: plays, index: idx, away: match.away, home: match.home)
                Text("Replay built from play-by-play. Shooter and ball are placed from tracked shot locations; other players show a typical formation, not live tracking.")
                    .font(.caption2).foregroundStyle(Neon.textDim).multilineTextAlignment(.center)
            }
        }
        .onChange(of: plays.count) { _, new in
            guard new > 0 else { return }
            if !started { started = true; idx = new - 1 }
            else if follow && match.state == .live { jump(to: new - 1) }
        }
        .onAppear {
            if !plays.isEmpty && !started { started = true; idx = plays.count - 1 }
            retarget(snap: true)
        }
        .onChange(of: idx) { _, _ in retarget() }
        .onChange(of: flying) { _, _ in retarget() }
        .onChange(of: plays.count) { _, _ in retarget() }
        .task(id: playing) {
            while playing && !Task.isCancelled {
                if idx >= plays.count - 1 { playing = false; break }
                await advance()
            }
        }
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
        let next = playerPositions().map { $0.pos } + [ballPosition()]
        prevPts = old ?? next
        targetPts = next
        changedAt = snap ? .distantPast : now
    }

    // MARK: Playback

    private func advance() async {
        flying = false; flash = false
        idx += 1
        let s = max(speed, 0.5)
        try? await Task.sleep(nanoseconds: UInt64(450_000_000 / s))
        withAnimation(.easeInOut(duration: 0.5 / s)) { flying = true }
        if current?.scoring == true { withAnimation(.easeOut(duration: 0.4)) { flash = true } }
        try? await Task.sleep(nanoseconds: UInt64(900_000_000 / s))
    }

    private func jump(to i: Int) {
        flying = false; flash = false
        withAnimation(.easeInOut(duration: 0.5)) { idx = min(max(i, 0), max(plays.count - 1, 0)) }
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

    private var attackRight: Bool {
        // The away side attacks the right basket, the home side the left one.
        possessionTeam(at: idx) != match.home.id
    }

    private func roster(_ teamId: String) -> [RosterPlayer] {
        let all = (detail?.roster ?? []).filter { $0.teamId == teamId }
        let ordered = all.filter { $0.starter } + all.filter { !$0.starter }
        return Array(ordered.prefix(5))
    }

    private var offenseTeam: Side { attackRight ? match.away : match.home }

    /// 10 circles: first 5 = away, last 5 = home, in court units.
    private func playerPositions() -> [CourtPlayer] {
        let right = attackRight
        let offSlots: [(Double, Double)] = [(64, 25), (75, 9), (75, 41), (84, 14), (81, 31)]
        let defSlots: [(Double, Double)] = [(70, 25), (80, 13), (80, 37), (86.5, 20), (85.5, 30)]
        func place(_ s: (Double, Double), _ k: Int) -> CGPoint {
            let jx = sin(Double(idx) * 1.7 + Double(k)) * 1.4, jy = cos(Double(idx) * 1.3 + Double(k) * 2) * 1.4
            let x = s.0 + jx, y = s.1 + jy
            return CGPoint(x: right ? x : courtW - x, y: y)
        }
        let awayRoster = roster(match.away.id), homeRoster = roster(match.home.id)
        let awayOffense = right
        var out: [CourtPlayer] = []
        for k in 0..<5 {
            let slot = awayOffense ? offSlots[k] : defSlots[k]
            out.append(CourtPlayer(team: .away, jersey: k < awayRoster.count ? awayRoster[k].jersey : "", name: k < awayRoster.count ? awayRoster[k].name : "", pos: place(slot, k)))
        }
        for k in 0..<5 {
            let slot = awayOffense ? defSlots[k] : offSlots[k]
            out.append(CourtPlayer(team: .home, jersey: k < homeRoster.count ? homeRoster[k].jersey : "", name: k < homeRoster.count ? homeRoster[k].name : "", pos: place(slot, k + 5)))
        }
        // Move the shooter to the tracked shot spot.
        if flying, let p = current, p.shooting || p.type.lowercased().contains("free throw"), let spot = shotSpot(p) {
            let offenseIsAway = attackRight
            let range = offenseIsAway ? 0..<5 : 5..<10
            let first = last(name: shooterName(p), in: out, range: range)
            out[first].pos = spot
        }
        return out
    }

    private func last(name: String?, in list: [CourtPlayer], range: Range<Int>) -> Int {
        if let name, let i = range.first(where: { !list[$0].name.isEmpty && name.hasPrefix(list[$0].name) }) { return i }
        return range.lowerBound
    }

    private func shooterName(_ p: CastPlay) -> String? { p.text }

    private func shotSpot(_ p: CastPlay) -> CGPoint? {
        let right = attackRight
        if p.type.lowercased().contains("free throw") { return CGPoint(x: right ? 94 - 5.25 - 15 : 5.25 + 15, y: 25) }
        guard var x = p.x, var y = p.y else { return nil }
        if y > 47 { y = 94 - y; x = 50 - x }
        x = min(max(x, 0), 50); y = min(max(y, 0), 47)
        return CGPoint(x: right ? 94 - y : y, y: right ? x : 50 - x)
    }

    private var basket: CGPoint { CGPoint(x: attackRight ? 94 - 5.25 : 5.25, y: 25) }

    private func ballPosition() -> CGPoint {
        let ps = playerPositions()
        let range = attackRight ? 0..<5 : 5..<10
        let handler = current.map { last(name: $0.text, in: ps, range: range) } ?? range.lowerBound
        if flying, let p = current, p.shooting || p.type.lowercased().contains("free throw") { return basket }
        return ps[handler].pos
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

    /// Continuous movement layered over the formation so the court is never still.
    private func motion(_ k: Int, _ t: Double, offense: Bool) -> CGPoint {
        let slot = Double(k % 5)
        let amp = offense ? 3.4 : 2.6
        let lag = offense ? 0.0 : 0.35   // defenders trail their man
        let tt = t - lag
        return CGPoint(x: sin(tt * (0.7 + slot * 0.13) + slot * 1.9) * amp,
                       y: cos(tt * (0.55 + slot * 0.11) + slot * 2.7) * amp * 0.8)
    }

    private func court(positions: [CourtPlayer], ball: CGPoint) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let sx = w / courtW, sy = h / courtH
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let base = blended(at: timeline.date)
                let moved: [CGPoint] = positions.enumerated().map { i, p in
                    let offense = (i < 5) == attackRight
                    let anchor = base.count > i ? base[i] : p.pos
                    // A defender mirrors the matching offensive player's movement.
                    let m = motion(i, t, offense: offense)
                    return CGPoint(x: anchor.x + m.x, y: anchor.y + m.y)
                }
                let ballBase = base.count > 10 ? base[10] : ball
                let shooting = flying && current.map { $0.shooting || $0.type.lowercased().contains("free throw") } == true
                let ballPoint: CGPoint = {
                    if shooting || moved.count < 10 { return ballBase }
                    // Pass the ball around the offense, dribbling in between.
                    let base = attackRight ? 0 : 5
                    let cycle = t / 1.5
                    let n = Int(floor(cycle))
                    let f = cycle - floor(cycle)
                    let from = moved[base + (n % 5)]
                    let to = moved[base + ((n + 2) % 5)]
                    if f < 0.55 {
                        return CGPoint(x: from.x + 1.2, y: from.y + abs(sin(f * 18)) * -1.6)
                    }
                    let e = (f - 0.55) / 0.45
                    let eased = e * e * (3 - 2 * e)
                    return CGPoint(x: from.x + (to.x - from.x) * eased,
                                   y: from.y + (to.y - from.y) * eased - sin(eased * .pi) * 3)
                }()
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.09, blue: 0.13))
                    courtLines(w: w, h: h)
                    Circle().fill(flash ? Neon.cyan.opacity(0.5) : .clear)
                        .frame(width: 44, height: 44)
                        .position(x: basket.x * sx, y: basket.y * sy)
                        .scaleEffect(flash ? 1.4 : 0.6)
                    ForEach(Array(positions.enumerated()), id: \.offset) { i, p in
                        let color = p.team == .away ? Neon.magenta : Neon.cyan
                        ZStack {
                            Circle().fill(Neon.black).overlay(Circle().stroke(color, lineWidth: 2))
                            Text(p.jersey).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        }
                        .frame(width: 24, height: 24)
                        .shadow(color: color.opacity(0.9), radius: (p.team == .away) == attackRight ? 6 : 2)
                        .position(x: moved[i].x * sx, y: moved[i].y * sy)
                    }
                    Circle().fill(Color.orange).frame(width: 11, height: 11)
                        .shadow(color: .orange, radius: 5)
                        .position(x: ballPoint.x * sx, y: ballPoint.y * sy)
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
                    if idx >= plays.count - 1 { idx = 0 }
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
                    Button { follow = true; playing = false; jump(to: plays.count - 1) } label: {
                        Text("LIVE").font(.caption.weight(.heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(follow ? Neon.black : Neon.magenta)
                            .background(follow ? AnyShapeStyle(Neon.magenta) : AnyShapeStyle(Neon.magenta.opacity(0.15)), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            Slider(value: Binding(get: { Double(idx) }, set: { idx = Int($0); flying = false; flash = false; playing = false; follow = false }),
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
