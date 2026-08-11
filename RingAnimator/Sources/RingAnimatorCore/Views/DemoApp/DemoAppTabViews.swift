import SwiftUI

/// The four demo-app screens the ring pod floats above. Generic,
/// representative "smart home" content — not a pixel match of any specific
/// reference design — built from plain `VStack`/`ScrollView` so it stays
/// simple and easy to adjust. The nav bar above each screen (`.demoNavBar`)
/// is real native chrome (see `DemoAppComponents.swift`).

public struct DashboardTabView: View {
    /// Opens the Ring settings sheet — see `demoNavBar`'s doc comment.
    /// `nil` keeps this view usable without wiring anything up (matches
    /// `demoNavBar`'s own default).
    public var onSettingsTap: (() -> Void)?

    public init(onSettingsTap: (() -> Void)? = nil) {
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                modesRow
                if let featured = DemoData.cameras.first {
                    DemoCameraCard(camera: featured, height: 220)
                }
                deviceGrid
            }
            .padding(DemoLayout.pageMargin)
        }
        .background(DemoColors.pageBackground)
        .demoNavBar(title: "Dashboard", onSettingsTap: onSettingsTap)
    }

    private var modesRow: some View {
        HStack(spacing: 0) {
            ForEach(DemoData.modes) { mode in
                VStack(spacing: 8) {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 20))
                        .foregroundStyle(mode.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(mode.isActive ? DemoColors.accent : DemoColors.mutedFill))
                    Text(mode.name)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: DemoLayout.cardCornerRadius, style: .continuous).fill(DemoColors.cardBackground))
    }

    private var deviceGrid: some View {
        HStack(spacing: 10) {
            ForEach(DemoData.deviceTiles) { tile in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: tile.systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(tile.name).font(.system(size: 13, weight: .semibold))
                    Text(tile.status).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 92)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DemoLayout.cardCornerRadius, style: .continuous).fill(DemoColors.cardBackground))
            }
        }
    }
}

public struct FeedTabView: View {
    public var onSettingsTap: (() -> Void)?

    public init(onSettingsTap: (() -> Void)? = nil) {
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DemoLayout.rowSpacing) {
                ForEach(DemoData.events) { event in
                    FeedRow(event: event)
                }
            }
            .padding(DemoLayout.pageMargin)
        }
        .background(DemoColors.pageBackground)
        .demoNavBar(title: "Feed", trailingIcon: "magnifyingglass", onSettingsTap: onSettingsTap)
    }
}

private struct FeedRow: View {
    let event: DemoEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(DemoColors.mutedFill))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 15, weight: .semibold))
                if !event.subtitle.isEmpty {
                    Text(event.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if event.hasThumbnail {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DemoColors.mutedFill)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }

            Text(event.timestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DemoLayout.cardCornerRadius, style: .continuous).fill(DemoColors.cardBackground))
    }
}

public struct DevicesTabView: View {
    public var onSettingsTap: (() -> Void)?

    public init(onSettingsTap: (() -> Void)? = nil) {
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(DemoData.cameras.enumerated()), id: \.element.id) { index, camera in
                    DemoCameraCard(camera: camera, height: index == 0 ? 220 : 150)
                }
            }
            .padding(DemoLayout.pageMargin)
        }
        .background(DemoColors.pageBackground)
        .demoNavBar(title: "Devices", onSettingsTap: onSettingsTap)
    }
}

public struct RoutinesTabView: View {
    public var onSettingsTap: (() -> Void)?

    public init(onSettingsTap: (() -> Void)? = nil) {
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(DemoData.modes) { mode in
                    ModeCard(mode: mode)
                }
            }
            .padding(DemoLayout.pageMargin)
        }
        .background(DemoColors.pageBackground)
        .demoNavBar(title: "Routines", onSettingsTap: onSettingsTap)
    }
}

private struct ModeCard: View {
    let mode: DemoMode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(mode.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 36, height: 36)
                .background(Circle().fill(mode.isActive ? DemoColors.accent : DemoColors.mutedFill))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(mode.name).font(.system(size: 16, weight: .semibold))
                    if mode.isActive {
                        Text("Active").font(.caption.bold()).foregroundStyle(.blue)
                    }
                }
                Text(mode.deviceCount).font(.caption).foregroundStyle(.secondary)
                Text(mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DemoLayout.cardCornerRadius, style: .continuous).fill(DemoColors.cardBackground))
    }
}
