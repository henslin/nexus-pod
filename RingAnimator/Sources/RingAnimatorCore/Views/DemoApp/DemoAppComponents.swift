import SwiftUI

/// Wraps demo tab content in a real, native nav bar — but only on iOS.
///
/// On macOS there's only one toolbar per window: any `.toolbar`/
/// `.navigationTitle` set deep inside a view tree (like these tab screens,
/// nested inside `PhoneMockupView`'s simulated phone) merges straight into
/// the actual app window's own title bar instead of staying scoped to that
/// small mockup — so on macOS this just returns the content as-is, with no
/// nav chrome of its own. On iOS, where each `TabView` tab genuinely gets
/// its own independent nav bar, it's a real `NavigationStack` with the
/// shared toolbar below.
extension View {
    /// `onSettingsTap` is `nil` by default so nothing else calling this
    /// (there's currently nothing else, but future demo screens shouldn't
    /// be forced to wire up Ring settings just to get a nav bar) has to
    /// pass it — when it's `nil` the gear button in the trailing group
    /// below simply isn't shown. `RootView` (the real iOS app) passes a
    /// real closure on all four tabs, since the gear is meant to be
    /// reachable no matter which tab you're on.
    @ViewBuilder
    func demoNavBar(title: String, trailingIcon: String = "plus", onSettingsTap: (() -> Void)? = nil) -> some View {
        #if os(iOS)
        NavigationStack {
            self
                .navigationTitle(title)
                .toolbar { demoToolbarContent(homeName: "Smith Home", trailingIcon: trailingIcon, onSettingsTap: onSettingsTap) }
        }
        #else
        self
        #endif
    }
}

/// Shared native toolbar content for every demo tab screen: a leading
/// profile glyph, a centered "home name" `Menu` (the native equivalent of
/// a tappable dropdown pill), and a trailing icon + "more" group. Built
/// from real `ToolbarItem`/`Menu` — no hand-drawn bar — so it renders with
/// whatever chrome the host platform actually uses. In the Figma source,
/// most screens show a "+" here; Feed shows a search glyph instead — that's
/// the only per-screen difference, passed in as `trailingIcon`.
///
/// The gear button (when `onSettingsTap` is supplied) is appended last in
/// the trailing group — the outermost, rightmost item — so it reads as
/// "the corner" the same way it would in Settings/Music/Maps, sitting
/// alongside rather than on top of the demo app's own decorative controls.
/// It opens the *real* Ring settings sheet (`ControlsView`, wired in
/// `RootView`) — everything else in this toolbar is inert placeholder
/// chrome for the smart-home demo screens.
@ToolbarContentBuilder
func demoToolbarContent(homeName: String, trailingIcon: String = "plus", onSettingsTap: (() -> Void)? = nil) -> some ToolbarContent {
    ToolbarItem(placement: .navigation) {
        Image(systemName: "person.crop.circle")
            .font(.title3)
            .foregroundStyle(.secondary)
    }
    ToolbarItem(placement: .principal) {
        // `Menu` already draws its own disclosure chevron on macOS/iOS —
        // just the title, no manually-added chevron glyph.
        Menu {
            Text("Demo — no other homes configured")
        } label: {
            Text(homeName).font(.headline)
        }
    }
    ToolbarItemGroup(placement: .primaryAction) {
        Button {
            // Demo only — no real action wired up.
        } label: {
            Image(systemName: trailingIcon)
        }
        Menu {
            Text("More options")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        if let onSettingsTap {
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
            }
        }
    }
}

/// A camera feed card — used on the Dashboard (one featured camera) and
/// the Devices tab (the full stacked list). A gradient placeholder stands
/// in for the live feed, since this is representative demo content rather
/// than a real camera stream.
struct DemoCameraCard: View {
    let camera: DemoCamera
    var height: CGFloat = 208
    var showsStatusRow: Bool = true

    var body: some View {
        ZStack {
            placeholder

            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .bottom)

            Text(camera.timestamp)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)

            Text("Go Live")
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.35)))
                .foregroundStyle(.white)

            HStack(alignment: .bottom) {
                Text(camera.name).font(.caption.bold()).foregroundStyle(.white)
                Spacer()
                if showsStatusRow {
                    statusRow
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(10)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DemoLayout.cardCornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        LinearGradient(colors: [.green.opacity(0.35), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            .overlay(
                Image(systemName: camera.systemImage)
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.35))
            )
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.black.opacity(0.35)))

            HStack(spacing: 4) {
                Image(systemName: "battery.100")
                Image(systemName: "wifi")
                Image(systemName: "mic.slash.fill")
            }
            .font(.system(size: 10))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
    }
}
