import SwiftUI
import AppKit

struct SettingsRootView: View {
    @ObservedObject var store = CursorSkinStore.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.up.and.down.circle.fill").font(.system(size: 24, weight: .medium))
                    Text("Scrollapp").font(.system(size: 14, weight: .bold))
                }
                .padding(.bottom, 31).padding(.top, 22)
                navigation("general", icon: "slider.horizontal.3")
                navigation("skins", icon: "cursorarrow.rays")
                Spacer()
            }
            .padding(.horizontal, 14).frame(width: 156)
            .background(Color.white.opacity(0.27))
            Rectangle().fill(Color.black.opacity(0.045)).frame(width: 1)
            Group {
                if store.section == "skins" { SkinLibraryView(store: store) }
                else {
                    ContentView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 563)
        }
        .frame(width: 720, height: 620)
        .foregroundStyle(Style.primaryText)
        .background(Style.background)
    }
    private func navigation(_ id: String, icon: String) -> some View {
        Button { store.section = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 18)
                Text(L10n.t("settings.\(id)")).font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 11).frame(height: 37)
            .background(RoundedRectangle(cornerRadius: 11).fill(store.section == id ? Style.card : .clear))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(store.section == id ? 0.9 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(store.section == id ? 0.045 : 0), radius: 6, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("settings.\(id)")
    }
}

private struct SkinLibraryView: View {
    @ObservedObject var store: CursorSkinStore
    @AppStorage("cursorFavorites") private var favoriteIDs = ""
    @State private var filter = "all"
    private let filters = ["all", "favorites"]
    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }
    private var visibleThemes: [CursorTheme] {
        CursorCatalog.themes.filter {
            filter == "all" || favorites.contains($0.id)
        }
    }
    private var gridHeight: CGFloat {
        let rows = max(1, (visibleThemes.count + 1) / 2)
        return min(248, CGFloat(rows * 117 + (rows - 1) * 12 + 2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("settings.skins")).font(.system(size: 24, weight: .bold))
                }
                Spacer()
                Image(systemName: "cursorarrow").font(.system(size: 20, weight: .medium))
                    .frame(width: 43, height: 43).background(Style.card, in: RoundedRectangle(cornerRadius: 14))
                    .raised(radius: 14, darkBlur: 5, lightBlur: 4, offset: 2)
            }
            .padding(.bottom, 3)
            HStack(spacing: 4) {
                ForEach(filters, id: \.self) { id in
                    Button { filter = id } label: {
                        HStack(spacing: 4) {
                            if id == "favorites" { Image(systemName: "heart.fill").font(.system(size: 8)) }
                            Text(L10n.t("skins.filter.\(id)")).font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 12).frame(height: 27)
                        .foregroundStyle(filter == id ? Color.white : Style.secondaryText)
                        .background(filter == id ? Style.accent : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(L10n.t("skins.count", visibleThemes.count)).font(.system(size: 10)).foregroundStyle(Style.secondaryText)
            }
            ZStack(alignment: .top) {
                if visibleThemes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart").font(.system(size: 25)).foregroundStyle(Style.secondaryText)
                        Text(L10n.t("skins.emptyFavorites")).font(.system(size: 12)).foregroundStyle(Style.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(visibleThemes) { theme in
                                themeCard(theme)
                            }
                        }
                        .padding(1)
                    }
                }
            }
            .frame(height: gridHeight, alignment: .top)
            preview
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
        .onAppear {
            let available = Set(CursorCatalog.themes.map(\.id))
            favoriteIDs = favorites.intersection(available).sorted().joined(separator: ",")
        }
    }

    private func themeCard(_ theme: CursorTheme) -> some View {
        let selected = store.selectedID == theme.id
        return ZStack(alignment: .topTrailing) {
            Button { store.selectedID = theme.id } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 21) {
                        ForEach([CursorRole.arrow, .text, .link], id: \.self) { role in
                            Image(nsImage: CursorCatalog.thumbnail(theme, role: role))
                                .interpolation(theme.id == "mint" ? .none : .high)
                                .resizable().scaledToFit().frame(width: 32, height: 32)
                                .shadow(color: .black.opacity(0.11), radius: 2, y: 2)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 61)
                    .background(theme.color.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: 6) {
                        Text(theme.name).font(.system(size: 12, weight: .bold))
                        if store.activeID == theme.id {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color(red: 0.27, green: 0.49, blue: 0.35))
                        }
                        Spacer()
                        Text(theme.id == "system" ? L10n.t("skins.native") : "1× / 2×")
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(Style.secondaryText)
                    }
                    .padding(.top, 10)
                    Text(theme.subtitle).font(.system(size: 9)).foregroundStyle(Style.secondaryText).padding(.top, 3).lineLimit(1)
                }
                .padding(9)
                .frame(height: 117)
                .background(Style.card, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Style.accent.opacity(0.8) : .white.opacity(0.8), lineWidth: selected ? 1.5 : 1))
                .shadow(color: .black.opacity(0.04), radius: 5, y: 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme.name)
            .accessibilityValue(selected ? L10n.t("skins.selected") : "")
            .accessibilityIdentifier("skin.\(theme.id)")
            Button {
                var value = favorites
                if value.contains(theme.id) { value.remove(theme.id) } else { value.insert(theme.id) }
                favoriteIDs = value.sorted().joined(separator: ",")
            } label: {
                Image(systemName: favorites.contains(theme.id) ? "heart.fill" : "heart")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(favorites.contains(theme.id) ? Color(red: 0.69, green: 0.32, blue: 0.37) : Style.secondaryText)
                    .frame(width: 25, height: 25).background(.white.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain).padding(13)
            .accessibilityLabel(L10n.t(favorites.contains(theme.id) ? "skins.unfavorite" : "skins.favorite", theme.name))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("skins.preview")).font(.system(size: 11, weight: .bold))
                Spacer()
                Text(store.selectedTheme.name).font(.system(size: 10)).foregroundStyle(Style.secondaryText)
            }
            HStack(spacing: 5) {
                ForEach([CursorRole.arrow, .text, .link, .grab, .crosshair, .horizontal, .unavailable], id: \.self) { role in
                    VStack(spacing: 5) {
                        CursorHoverPreview(theme: store.selectedTheme, role: role)
                            .frame(height: 38)
                        Text(role.label).font(.system(size: 8)).foregroundStyle(Style.secondaryText).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.75), lineWidth: 1))
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(L10n.t("skins.reset")) { store.reset() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                    .disabled(store.isBusy || !store.isReady || !store.isThemed)
                Button {
                    if store.isReady { store.apply(store.selectedID) } else { store.start() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isBusy { ProgressView().controlSize(.mini).tint(.white) }
                        Text(L10n.t(store.isBusy ? "skins.applying" : !store.isReady ? "skins.retry" :
                            store.selectedID == store.activeID ? "skins.applied" : "skins.apply"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(minWidth: 70).padding(.horizontal, 12).frame(height: 32)
                    .foregroundStyle(.white).background(Style.glossyBlack, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy || (store.isReady && store.selectedID == store.activeID))
                .accessibilityIdentifier("skin.apply")
            }
            if let error = store.errorKey {
                Text(L10n.t("skins.error.\(error)")).font(.system(size: 9)).foregroundStyle(Color(red: 0.68, green: 0.26, blue: 0.22))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// Hover samples exercise an actual NSCursor without changing the global theme.
// cursor rects are updated by AppKit; no tracking timers or NSCursor push leaks.
private struct CursorHoverPreview: NSViewRepresentable {
    let theme: CursorTheme
    let role: CursorRole
    func makeNSView(context: Context) -> SampleView { SampleView() }
    func updateNSView(_ view: SampleView, context: Context) {
        view.image = CursorCatalog.image(theme, role: role)
        view.cursor = CursorCatalog.cursor(theme, role: role, scale: CursorSkinStore.shared.cursorScale,
            markerDiameter: CursorSkinStore.shared.markerDiameter)
        view.window?.invalidateCursorRects(for: view)
        view.needsDisplay = true
        view.setAccessibilityLabel(role.label)
    }
    final class SampleView: NSView {
        var image: NSImage?
        var cursor: NSCursor?
        override var isFlipped: Bool { true }
        override func resetCursorRects() {
            if let cursor { addCursorRect(bounds, cursor: cursor) }
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            image?.draw(in: NSRect(x: (bounds.width - 28) / 2, y: (bounds.height - 28) / 2, width: 28, height: 28),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
