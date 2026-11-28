import SwiftUI

/// ESPN-GameCast-style live view: the sport's playing surface with circles for the ball, runners and shots.
struct GameCastView: View {
    let match: Match
    let detail: MatchDetail?
    private var shots: [ShotMark] { detail?.shots ?? [] }

    var body: some View {
        VStack(spacing: 14) {
            switch match.sport {
            case .nfl: FootballField(match: match)
            case .mlb: BaseballDiamond(match: match)
            case .nba: BasketballCast(match: match, detail: detail)
            case .nhl: ShotChart(match: match, shots: shots, kind: .hockey)
            case .atp, .wta: TennisCast(match: match)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: Football

private struct FootballField: View {
    let match: Match

    /// Yards from the away team's goal line (left) to the ball, 0...100.
    private var ballYards: Double? {
        guard let s = match.situation else { return nil }
        if let text = s.downDistance, let r = text.range(of: " at ") {
            let parts = text[r.upperBound...].split(separator: " ")
            if parts.count == 2, let n = Double(parts[1]) {
                let team = String(parts[0])
                if team == match.away.short { return n }
                if team == match.home.short { return 100 - n }
            }
        }
        if let y = s.yardLine {
            return s.possessionId == match.home.id ? 100 - Double(y) : Double(y)
        }
        return nil
    }
    private var awayHasBall: Bool { match.situation?.possessionId == match.away.id }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let endZone = w * 0.08
                let play = w - endZone * 2
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.10, blue: 0.12))
                    Rectangle().fill(Neon.magenta.opacity(0.22)).frame(width: endZone).frame(maxHeight: .infinity)
                    Rectangle().fill(Neon.cyan.opacity(0.22)).frame(width: endZone).frame(maxHeight: .infinity).offset(x: w - endZone)
                    ForEach(1..<10, id: \.self) { i in
                        Rectangle().fill(Color.white.opacity(i == 5 ? 0.35 : 0.14)).frame(width: 1.5)
                            .offset(x: endZone + play * CGFloat(i) / 10)
                    }
                    Text(match.away.short).font(.caption.weight(.heavy)).foregroundStyle(Neon.magenta)
                        .rotationEffect(.degrees(-90)).position(x: endZone / 2, y: h / 2)
                    Text(match.home.short).font(.caption.weight(.heavy)).foregroundStyle(Neon.cyan)
                        .rotationEffect(.degrees(90)).position(x: w - endZone / 2, y: h / 2)
                    if let yards = ballYards {
                        let x = endZone + play * CGFloat(yards / 100)
                        if let dist = firstDownDistance {
                            let target = awayHasBall ? yards + dist : yards - dist
                            Rectangle().fill(Color.yellow.opacity(0.9)).frame(width: 3)
                                .offset(x: endZone + play * CGFloat(min(max(target, 0), 100) / 100) - 1.5)
                        }
                        Rectangle().fill(Neon.cyan).frame(width: 3)
                            .offset(x: x - 1.5)
                        PulsingBall(color: awayHasBall ? Neon.magenta : Neon.cyan)
                            .position(x: x, y: h / 2)
                            .animation(.easeInOut(duration: 0.8), value: yards)
                    } else {
                        Text("Ball position not available").font(.footnote).foregroundStyle(Neon.textDim).position(x: w / 2, y: h / 2)
                    }
                }
            }
            .frame(height: 150)

            if let s = match.situation, let text = s.downDistance {
                HStack {
                    Image(systemName: "football.fill").foregroundStyle(Neon.cyan)
                    Text(text).font(.subheadline.weight(.semibold))
                    Spacer()
                    if s.redZone { Text("RED ZONE").font(.caption2.weight(.heavy)).foregroundStyle(Neon.magenta) }
                }
                .neonCard()
            }
            if match.state != .live { Text(match.state == .finished ? "Game over" : "Kickoff \(match.statusText)").foregroundStyle(Neon.textDim).font(.footnote) }
        }
    }

    private var firstDownDistance: Double? {
        guard let t = match.situation?.downDistance, let r = t.range(of: "& ") else { return nil }
        return Double(t[r.upperBound...].prefix { $0.isNumber })
    }
}

private struct PulsingBall: View {
    var color: Color
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.28)).frame(width: pulse ? 34 : 20, height: pulse ? 34 : 20)
            Circle().fill(color).frame(width: 14, height: 14).shadow(color: color, radius: 8)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: Baseball

private struct BaseballDiamond: View {
    let match: Match
    var body: some View {
        let s = match.situation ?? Situation()
        VStack(spacing: 14) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let home = CGPoint(x: w / 2, y: h - 24)
                let first = CGPoint(x: w / 2 + h * 0.46, y: h * 0.52)
                let second = CGPoint(x: w / 2, y: 22)
                let third = CGPoint(x: w / 2 - h * 0.46, y: h * 0.52)
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.10, blue: 0.12))
                    Path { p in p.move(to: home); p.addLine(to: first); p.addLine(to: second); p.addLine(to: third); p.closeSubpath() }
                        .stroke(Neon.cyan.opacity(0.7), lineWidth: 2)
                    base(first, on: s.onFirst); base(second, on: s.onSecond); base(third, on: s.onThird)
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 2).frame(width: 14, height: 14).position(x: w / 2, y: h * 0.58)
                    Circle().fill(Color.white).frame(width: 12, height: 12).position(home)
                }
            }
            .frame(height: 210)

            HStack(spacing: 22) {
                counter("B", s.balls, of: 4, color: Neon.cyan)
                counter("S", s.strikes, of: 3, color: Neon.magenta)
                counter("O", s.outs, of: 3, color: Neon.magenta)
            }
            .neonCard()
            if let b = s.batter { Label("At bat: \(b)", systemImage: "figure.baseball").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).neonCard() }
            if let p = s.pitcher { Label("Pitching: \(p)", systemImage: "baseball.fill").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).neonCard() }
            if match.situation == nil { Text("Live situation appears when the game starts.").font(.footnote).foregroundStyle(Neon.textDim) }
        }
    }

    private func base(_ p: CGPoint, on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? Neon.magenta : Color.white.opacity(0.18))
            .frame(width: 22, height: 22).rotationEffect(.degrees(45))
            .shadow(color: on ? Neon.magenta : .clear, radius: 8)
            .position(p)
            .animation(.easeInOut(duration: 0.4), value: on)
    }

    private func counter(_ label: String, _ value: Int?, of total: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption.weight(.heavy)).foregroundStyle(Neon.textDim)
            ForEach(0..<(total == 4 ? 3 : total - 0), id: \.self) { i in
                Circle().fill(i < (value ?? 0) ? color : Color.white.opacity(0.14)).frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: Basketball / hockey shot charts

private struct ShotChart: View {
    enum Kind { case basketball, hockey }
    let match: Match
    let shots: [ShotMark]
    let kind: Kind

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.10, blue: 0.12))
                    surface(w: w, h: h)
                    ForEach(Array(shots.enumerated()), id: \.element.id) { i, s in
                        let p = point(s, w: w, h: h)
                        let isLatest = i == shots.count - 1
                        Circle()
                            .fill(s.made ? Neon.cyan : Color.clear)
                            .overlay(Circle().stroke(s.made ? Neon.cyan : Neon.magenta, lineWidth: 2))
                            .frame(width: isLatest ? 16 : 10, height: isLatest ? 16 : 10)
                            .shadow(color: (s.made ? Neon.cyan : Neon.magenta).opacity(0.8), radius: isLatest ? 8 : 3)
                            .position(p)
                            .transition(.scale)
                    }
                }
                .animation(.spring(response: 0.5), value: shots.count)
            }
            .frame(height: kind == .basketball ? 300 : 210)

            HStack(spacing: 18) {
                legend(Neon.cyan, filled: true, "Made")
                legend(Neon.magenta, filled: false, "Missed")
                Text("\(shots.count) shots").font(.caption).foregroundStyle(Neon.textDim)
            }
            if shots.isEmpty {
                Text("Shot locations appear here once the game has plays with tracking data.")
                    .font(.footnote).foregroundStyle(Neon.textDim).multilineTextAlignment(.center)
            }
        }
    }

    private func legend(_ c: Color, filled: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(filled ? c : .clear).overlay(Circle().stroke(c, lineWidth: 2)).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(Neon.textDim)
        }
    }

    private func point(_ s: ShotMark, w: CGFloat, h: CGFloat) -> CGPoint {
        switch kind {
        case .basketball:
            // ESPN court coordinates: x 0...50 across, y 0...94 along the floor. Fold both halves onto one half court.
            var x = s.x, y = s.y
            if y > 47 { y = 94 - y; x = 50 - x }
            return CGPoint(x: w * CGFloat(min(max(x, 0), 50) / 50), y: 22 + (h - 30) * CGFloat(min(max(y, 0), 47) / 47))
        case .hockey:
            // Rink coordinates are centred: x -100...100, y -42.5...42.5.
            return CGPoint(x: w / 2 + w / 2 * CGFloat(min(max(s.x, -100), 100) / 100),
                           y: h / 2 + h / 2 * CGFloat(min(max(s.y, -42.5), 42.5) / 42.5))
        }
    }

    @ViewBuilder private func surface(w: CGFloat, h: CGFloat) -> some View {
        switch kind {
        case .basketball:
            ZStack {
                Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 2).frame(width: w * 0.36, height: (h - 30) * 0.4).position(x: w / 2, y: 22 + (h - 30) * 0.2)
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 2).frame(width: w * 0.24).position(x: w / 2, y: 22 + (h - 30) * 0.4)
                Path { p in p.addArc(center: CGPoint(x: w / 2, y: 30), radius: w * 0.46, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false) }
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                Circle().stroke(Neon.magenta, lineWidth: 2).frame(width: 16).position(x: w / 2, y: 22)
            }
        case .hockey:
            ZStack {
                RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.3), lineWidth: 2).padding(6)
                Rectangle().fill(Neon.magenta.opacity(0.5)).frame(width: 2).position(x: w / 2, y: h / 2).frame(height: h)
                Rectangle().fill(Neon.cyan.opacity(0.4)).frame(width: 2, height: h - 24).position(x: w * 0.27, y: h / 2)
                Rectangle().fill(Neon.cyan.opacity(0.4)).frame(width: 2, height: h - 24).position(x: w * 0.73, y: h / 2)
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 2).frame(width: h * 0.4).position(x: w / 2, y: h / 2)
            }
        }
    }
}

// MARK: Tennis

private struct TennisCast: View {
    let match: Match
    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.10, blue: 0.12))
                    Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 2).padding(.vertical, 18).padding(.horizontal, 30)
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: 2).frame(height: h - 36)
                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1.5).padding(.horizontal, 30).position(x: w / 2, y: h * 0.35)
                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1.5).padding(.horizontal, 30).position(x: w / 2, y: h * 0.65)
                    PlayerDot(color: Neon.magenta, label: match.away.short).position(x: w * 0.16, y: h / 2)
                    PlayerDot(color: Neon.cyan, label: match.home.short).position(x: w * 0.84, y: h / 2)
                }
            }
            .frame(height: 190)
            Text("Live ball tracking isn't published for tennis, so this shows the court and current score only.")
                .font(.footnote).foregroundStyle(Neon.textDim).multilineTextAlignment(.center)
        }
    }
}

private struct PlayerDot: View {
    let color: Color
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Circle().fill(color).frame(width: 18, height: 18).shadow(color: color, radius: 8)
            Text(label).font(.caption2.weight(.bold)).lineLimit(1)
        }
    }
}
