import SwiftUI
import AppKit

/// Rotation state for the ring, held in a reference type so the
/// scroll-wheel monitor always sees current values.
@MainActor
final class RingMotion: ObservableObject {
    @Published var rotation: Double = 0          // degrees, clockwise
    var count: Int = 8
    var hovering = false
    var lastDragAngle: Double?
    var lastDragEnd = Date.distantPast

    /// True while dragging or just after, so a drag that ends over an
    /// icon doesn't also launch it.
    var recentlyDragged: Bool {
        lastDragAngle != nil || Date().timeIntervalSince(lastDragEnd) < 0.25
    }

    var step: Double { 360 / Double(max(count, 1)) }

    func snap() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            rotation = (rotation / step).rounded() * step
        }
    }

    func nudge(by slots: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            rotation = ((rotation / step).rounded() + Double(slots)) * step
        }
    }
}

struct RingView: View {
    let items: [RingItem]
    var onOpen: (RingItem) -> Void
    var onCentre: () -> Void

    @StateObject private var motion = RingMotion()
    @State private var scrollMonitor: Any?

    private let radius: CGFloat = 128
    private let iconSize: CGFloat = 62

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Circle()
                    .stroke(Theme.ringLine, lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(centre)

                Circle()
                    .stroke(Theme.ringInner, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 172, height: 172)
                    .rotationEffect(.degrees(motion.rotation * -0.5))
                    .position(centre)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let slot = 360 / Double(max(items.count, 1))
                    let angle = Double(index) * slot + motion.rotation
                    let radians = angle * .pi / 180
                    RingButton(item: item, size: iconSize) {
                        if !motion.recentlyDragged { onOpen(item) }
                    }
                        .position(
                            x: centre.x + radius * CGFloat(sin(radians)),
                            y: centre.y - radius * CGFloat(cos(radians))
                        )
                }

                CentreButton(action: onCentre)
                    .position(centre)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let current = angle(of: value.location, around: centre)
                        if let last = motion.lastDragAngle {
                            var delta = current - last
                            if delta > 180 { delta -= 360 }
                            if delta < -180 { delta += 360 }
                            motion.rotation += delta
                        }
                        motion.lastDragAngle = current
                    }
                    .onEnded { _ in
                        motion.lastDragAngle = nil
                        motion.lastDragEnd = Date()
                        motion.snap()
                    }
            )
        }
        .onHover { motion.hovering = $0 }
        .onAppear {
            motion.count = items.count
            installScrollMonitor()
        }
        .onDisappear { removeScrollMonitor() }
        .onChange(of: items.count) { _, newCount in
            motion.count = newCount
            motion.snap()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App ring")
    }

    /// Angle of a point clockwise from 12 o'clock, in degrees.
    private func angle(of point: CGPoint, around centre: CGPoint) -> Double {
        let dx = Double(point.x - centre.x)
        let dy = Double(point.y - centre.y)
        return atan2(dx, -dy) * 180 / .pi
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        let motion = self.motion
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard motion.hovering else { return event }
            let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? event.scrollingDeltaY : -event.scrollingDeltaX
            if event.hasPreciseScrollingDeltas {
                // Trackpad / Magic Mouse: follow the fingers, then settle on a slot.
                motion.rotation += Double(delta) * 0.6
                if event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled {
                    motion.snap()
                }
            } else if delta != 0 {
                // Notched mouse wheel: one app per click.
                motion.nudge(by: delta > 0 ? 1 : -1)
            }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}

struct RingButton: View {
    let item: RingItem
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RingIcon(item: item)
                .frame(width: size * 0.58, height: size * 0.58)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? Theme.chipHover : Theme.chip))
                .overlay(Circle().stroke(hovering ? Theme.accent.opacity(0.7) : Theme.chipLine, lineWidth: 1))
                .contentShape(Circle())
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.name)
        .accessibilityLabel(item.name)
    }
}

/// Orbit app glyph, or a favicon for website shortcuts.
struct RingIcon: View {
    let item: RingItem

    var body: some View {
        switch item.kind {
        case .app:
            if let app = item.app {
                OrbitAppGlyph(kind: app)
            } else {
                Image(systemName: "questionmark.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Theme.secondary)
            }
        case .web:
            WebIcon(url: item.url)
        }
    }
}

struct WebIcon: View {
    let url: URL?

    private var faviconURL: URL? {
        guard let host = url?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Theme.text)
            }
        }
    }
}

struct CentreButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.background)
                .frame(width: 92, height: 92)
                .background(Circle().fill(Theme.accent))
                .contentShape(Circle())
                .scaleEffect(hovering ? 1.05 : 1)
                .shadow(color: Theme.accent.opacity(hovering ? 0.35 : 0), radius: 18)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .onHover { hovering = $0 }
        .help("All apps and search (⌘K)")
        .accessibilityLabel("Search everything")
    }
}
