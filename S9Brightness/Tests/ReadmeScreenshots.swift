import AppKit
import Foundation
import SwiftUI
import Testing
@testable import S9Brightness

/// Renders the README screenshots from the real views with sample data. Skipped unless
/// SCREENSHOTS_DIR is set:
///
///     TEST_RUNNER_SCREENSHOTS_DIR=$PWD/../docs/screenshots xcodebuild test \
///       -project S9Brightness.xcodeproj -scheme S9Brightness -destination 'platform=macOS' \
///       -only-testing:S9BrightnessTests/ReadmeScreenshots
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] != nil))
struct ReadmeScreenshots {
    let dir = URL(filePath: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] ?? "")

    @Test(arguments: [ColorScheme.light, .dark])
    func menu(_ scheme: ColorScheme) throws {
        // 192.0.2.1 is reserved for documentation, so the refresh on appear never gets a reply.
        let client = IPControlClient(config: IPControlConfig(host: "192.0.2.1", name: "ViewFinity S9"), token: "sample")
        let model = BrightnessModel(client: client, presets: Presets())
        model.percent = 64
        let menu = snapshot(MenuView(model: model, updates: UpdateChecker(checking: false)), scheme)
        try write(MenuScene(menu: menu), scheme, "menu")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func setup(_ scheme: ColorScheme) throws {
        let setup = SetupModel(client: IPControlClient(config: nil, token: nil)) { _ in }
        setup.monitors = [DiscoveredMonitor(host: "192.168.1.42", name: "ViewFinity S9", model: "S27C900P",
                                            serial: "sample", ipControl: true)]
        setup.phase = .results
        let content = snapshot(SetupView(setup: setup) { _ in }, scheme)
        try write(SetupScene(content: content), scheme, "setup")
    }

    /// Draws the view through AppKit, since ImageRenderer leaves out AppKit-backed controls.
    private func snapshot(_ view: some View, _ scheme: ColorScheme) -> NSImage {
        // SwiftUI controls only tint with the accent color while their window is active.
        let host = NSHostingView(rootView: view
            .environment(\.controlActiveState, .key)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = KeyWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()

        let size = host.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private func write(_ scene: some View, _ scheme: ColorScheme, _ name: String) throws {
        let renderer = ImageRenderer(content: scene.environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
    }
}

/// Controls draw in their active colors only in the key window.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// The warm backdrop of the website, with the light the app controls.
private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var glow: UnitPoint

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            dark ? Color(red: 0.043, green: 0.039, blue: 0.035) : Color(red: 0.96, green: 0.93, blue: 0.89)
            RadialGradient(colors: [Color(red: 1, green: 0.66, blue: 0.35).opacity(dark ? 0.42 : 0.5), .clear],
                           center: glow, startRadius: 0, endRadius: 420)
        }
    }
}

private extension View {
    func panel(cornerRadius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
    }
}

/// The menu open below its menu bar icon.
private struct MenuScene: View {
    let menu: NSImage

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: "apple.logo").font(.system(size: 15))
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) {
                    Text($0).foregroundStyle(.primary.opacity(0.85))
                }
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "sun.max")
                    .frame(width: 32, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.16)))
                Text("Sun 25 Oct  9:41").monospacedDigit()
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Color.primary.opacity(0.08).frame(height: 0.5) }

            HStack {
                Spacer()
                Image(nsImage: menu).panel(cornerRadius: 14)
            }
            .padding(.top, 8)
            .padding(.trailing, 72)
            .padding(.bottom, 80)
        }
        .frame(width: 680)
        .background(Backdrop(glow: UnitPoint(x: 0.7, y: 0.15)))
    }
}

/// The setup window with its title bar.
private struct SetupScene: View {
    let content: NSImage

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                    Spacer()
                }
                .frame(height: 12)
                Text("Set Up S9 Brightness").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color(nsColor: .windowBackgroundColor))
            Image(nsImage: content)
        }
        .panel(cornerRadius: 12)
        .padding(64)
        .background(Backdrop(glow: UnitPoint(x: 0.5, y: 0.0)))
    }
}
