import SwiftUI
import RingAnimatorCore

/// Root screen: the ring lives in its natural habitat — a real, native,
/// completely unmodified `TabView`. That matters: standard `TabView` is
/// what gives tap-to-switch, swipe-between-tabs, and the interactive
/// Liquid Glass transition (the bar's selection indicator tracking your
/// finger mid-swipe, only committing on release) for free on iOS 26/27 —
/// none of that is code we write, it's system behavior that only shows up
/// if nothing custom gets in its way. A floating glass ring button sits
/// just above the tab bar; tapping it opens every tunable parameter in a
/// standard Liquid Glass sheet.
struct RootView: View {
    @StateObject private var config = RingConfig()
    @State private var showingSettings = false
    @State private var selectedTab: DemoTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(DemoTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label {
                            Text(tab.rawValue)
                        } icon: {
                            // Custom assets, not SF Symbols, so there's no
                            // automatic outline→filled variant — swap the
                            // image ourselves based on our own selection
                            // state, which stays in sync with the system's
                            // own tab-switch animation (tap or swipe).
                            (tab == selectedTab ? tab.filledImage : tab.outlineImage)
                                .renderingMode(.template)
                        }
                    }
                    .tag(tab)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                ringButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                ControlsView(config: config)
                    .navigationTitle("Ring Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // Deployment target is iOS 27, so the real Glass API is always
    // available here — no #available branching or fallback material needed.
    private var ringButton: some View {
        ringButtonLabel
            .glassEffect(config.glass, in: Circle())
    }

    private var ringButtonLabel: some View {
        Button {
            showingSettings = true
        } label: {
            RingView(config: config, diameter: 30)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabContent(for tab: DemoTab) -> some View {
        switch tab {
        case .dashboard: DashboardTabView()
        case .feed: FeedTabView()
        case .devices: DevicesTabView()
        case .routines: RoutinesTabView()
        }
    }
}
