import SwiftUI

// Ocean-style scene that renders members as floating islands.
struct OceanIslandsView: View {
    let members: [MemberData]
    let currentUserID: String

    private let membersPerScene = 5
    private let sceneHeight: CGFloat = 420

    private var scenes: [[MemberData]] {
        guard !members.isEmpty else { return [] }
        return stride(from: 0, to: members.count, by: membersPerScene).map { startIndex in
            let endIndex = min(startIndex + membersPerScene, members.count)
            return Array(members[startIndex..<endIndex])
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ForEach(Array(scenes.enumerated()), id: \.offset) { _, sceneMembers in
                IslandScenePage(members: sceneMembers, currentUserID: currentUserID)
                    .frame(height: sceneHeight)
            }
        }
    }
}

private struct IslandScenePage: View {
    let members: [MemberData]
    let currentUserID: String

    private var anchors: [CGPoint] {
        switch members.count {
        case 1:
            return [CGPoint(x: 0.50, y: 0.58)]
        case 2:
            return [
                CGPoint(x: 0.30, y: 0.42),
                CGPoint(x: 0.72, y: 0.64)
            ]
        case 3:
            return [
                CGPoint(x: 0.28, y: 0.36),
                CGPoint(x: 0.72, y: 0.52),
                CGPoint(x: 0.50, y: 0.74)
            ]
        case 4:
            return [
                CGPoint(x: 0.24, y: 0.30),
                CGPoint(x: 0.70, y: 0.38),
                CGPoint(x: 0.30, y: 0.68),
                CGPoint(x: 0.74, y: 0.76)
            ]
        default:
            return [
                CGPoint(x: 0.22, y: 0.24),
                CGPoint(x: 0.68, y: 0.32),
                CGPoint(x: 0.48, y: 0.52),
                CGPoint(x: 0.26, y: 0.78),
                CGPoint(x: 0.76, y: 0.74)
            ]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OceanBackdropView()

                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    let anchor = anchors[min(index, anchors.count - 1)]
                    IslandAvatarView(
                        member: member,
                        isCurrentUser: member.userID == currentUserID
                    )
                    .position(
                        x: proxy.size.width * anchor.x,
                        y: proxy.size.height * anchor.y
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
    }
}

private struct OceanBackdropView: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    Image("OceanBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    WaveBand(
                        phase: t * 18,
                        baseline: proxy.size.height * 0.20,
                        wavelength: 170,
                        amplitude: 9,
                        lineWidth: 6,
                        opacity: 0.16
                    )

                    WaveBand(
                        phase: t * -13,
                        baseline: proxy.size.height * 0.48,
                        wavelength: 210,
                        amplitude: 10,
                        lineWidth: 7,
                        opacity: 0.13
                    )

                    WaveBand(
                        phase: t * 8,
                        baseline: proxy.size.height * 0.76,
                        wavelength: 240,
                        amplitude: 8,
                        lineWidth: 6,
                        opacity: 0.11
                    )
                }
            }
        }
    }
}

private struct WaveBand: View {
    let phase: Double
    let baseline: CGFloat
    let wavelength: CGFloat
    let amplitude: CGFloat
    let lineWidth: CGFloat
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            let offset = CGFloat(phase.truncatingRemainder(dividingBy: Double(wavelength)))
            context.translateBy(x: -offset, y: 0)
            let path = wavePath(in: size)
            context.stroke(
                path,
                with: .color(.white.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }

    private func wavePath(in size: CGSize) -> Path {
        var path = Path()
        var x: CGFloat = -wavelength

        path.move(to: CGPoint(x: x, y: baseline))

        while x <= size.width + wavelength {
            path.addQuadCurve(
                to: CGPoint(x: x + (wavelength / 2), y: baseline),
                control: CGPoint(x: x + (wavelength / 4), y: baseline - amplitude)
            )
            path.addQuadCurve(
                to: CGPoint(x: x + wavelength, y: baseline),
                control: CGPoint(x: x + (wavelength * 3 / 4), y: baseline + amplitude)
            )
            x += wavelength
        }

        return path
    }
}

private struct IslandAvatarView: View {
    let member: MemberData
    let isCurrentUser: Bool

    private var phase: Double {
        let hashed = StableIDHasher.hash(member.userID) % 628
        return Double(hashed) / 100.0
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let bob = CGFloat(sin(timeline.date.timeIntervalSinceReferenceDate * 0.8 + phase) * 4.0)

            VStack(spacing: 5) {
                Text(MinuteLabelFormatter.format(member.minutesUsed))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.26), in: Capsule())

                ZStack {
                    IslandBase(isCurrentUser: isCurrentUser)

                    Image(AnimalAvatarCatalog.imageName(for: member.userID))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 68, height: 68)
                        .padding(.bottom, 8)
                }
                .frame(width: 132, height: 102)

                Text(isCurrentUser ? "You" : member.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .frame(maxWidth: 128)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
            .offset(y: bob)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
            .animation(.easeInOut(duration: 0.2), value: bob)
        }
    }
}

private struct IslandBase: View {
    let isCurrentUser: Bool

    var body: some View {
        ZStack {
            Image("IslandBase")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 102)

            if isCurrentUser {
                Ellipse()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 110, height: 38)
                    .offset(y: 20)
            }
        }
    }
}

private enum AnimalAvatarCatalog {
    private static let imageNames = [
        "AnimalBear",
        "AnimalPig",
        "AnimalParrot",
        "AnimalDog",
        "AnimalCat",
        "AnimalPanda",
        "AnimalFox",
        "AnimalFrog",
        "AnimalKoala",
        "AnimalMonkey"
    ]

    static func imageName(for userID: String) -> String {
        guard !imageNames.isEmpty else { return "AnimalBear" }
        let index = StableIDHasher.hash(userID) % imageNames.count
        return imageNames[index]
    }
}

private enum MinuteLabelFormatter {
    static func format(_ minutes: Int) -> String {
        let clampedMinutes = max(0, minutes)
        let hours = clampedMinutes / 60
        let remainder = clampedMinutes % 60

        if hours > 0 {
            return "\(hours)h \(remainder)min"
        }
        return "\(remainder)min"
    }
}

private enum StableIDHasher {
    // Stable across launches; avoids Swift's randomized hashValue.
    static func hash(_ value: String) -> Int {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash)
    }
}
