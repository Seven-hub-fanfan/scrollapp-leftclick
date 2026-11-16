import SwiftUI
import AppKit

struct SettingsRootView: View {
    @ObservedObject var store = CursorSkinStore.shared
    var body: some View {
        SettingsShell(store: store) {
            if store.section == "skins" { SkinLibraryView(store: store) }
            else if store.section == "permissions" { PermissionSettingsView() }
            else if store.section == "shortcuts" { ShortcutSettingsView() }
            else if store.section == "prompt" { PromptStudioView() }
            else { ContentView() }
        }
    }
}

struct SettingsShell<Content: View>: View {
    @ObservedObject var store: CursorSkinStore
    @AppStorage("interfaceAppearance") private var appearance = AppAppearance.dark.rawValue
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                AppIconTile().padding(.top, 43).padding(.bottom, 20)
                navigation("general", icon: "slider.horizontal.3")
                navigation("skins", icon: "cursorarrow.rays")
                navigation("shortcuts", icon: "command")
                navigation("prompt", icon: "photo")
                navigation("permissions", icon: "lock.shield")
                Spacer()
                Menu {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { mode in
                        Button {
                            appearance = mode.rawValue
                        } label: {
                            Label(L10n.t("appearance.\(mode.rawValue)"),
                                  systemImage: appearance == mode.rawValue ? "checkmark" : mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: (AppAppearance(rawValue: appearance) ?? .dark).icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Style.secondaryText)
                        .frame(width: 40, height: 40)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L10n.t("appearance.title"))
                .accessibilityLabel(L10n.t("appearance.title"))
                .accessibilityValue(L10n.t("appearance.\(appearance)"))
                .accessibilityIdentifier("settings.appearance")
                .padding(.bottom, 20)
            }
            .frame(width: Style.sidebarWidth).background(Style.rail)
            Rectangle().fill(Style.line).frame(width: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Style.windowWidth, height: Style.windowHeight)
        .foregroundStyle(Style.primaryText)
        .background(GlassBackground())
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .dark).colorScheme)
        .onChange(of: appearance) { _ in AppAppearance.updateWindows() }
    }
    private func navigation(_ id: String, icon: String) -> some View {
        let selected = store.section == id
        return Button { store.section = id } label: {
            Image(systemName: icon).font(.system(size: 17, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Style.primaryText : Style.secondaryText)
            .frame(width: 44, height: 44)
            .background(selected ? Style.control : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Style.line : .clear, lineWidth: 1))
            .overlay(alignment: .leading) {
                Capsule().fill(selected ? Style.focus : .clear).frame(width: 2, height: 16).offset(x: -9)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(L10n.t("settings.\(id)"))
        .accessibilityLabel(L10n.t("settings.\(id)"))
        .accessibilityValue(selected ? L10n.t("skins.selected") : "")
        .accessibilityIdentifier("settings.\(id)")
    }
}

private struct SkinLibraryView: View {
    @ObservedObject var store: CursorSkinStore
    @ObservedObject private var assets = SkinAssetStore.shared
    @AppStorage("cursorFavorites") private var favoriteIDs = ""
    @State private var filter = "all"
    @State private var detailID: String?
    private let filters = ["all", "favorites"]
    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }
    private var visibleThemes: [CursorTheme] {
        CursorCatalog.themes.filter { filter == "all" || favorites.contains($0.id) }
    }
    var body: some View {
        Group {
            if let detailID {
                SkinDetailView(theme: CursorCatalog.theme(detailID), store: store) {
                    self.detailID = nil
                }
            } else {
                library
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: L10n.t("settings.skins"), subtitle: L10n.t("skins.libraryIntro"))
                .padding(.bottom, 6)
            HStack(spacing: 4) {
                ForEach(filters, id: \.self) { id in
                    Button { filter = id } label: {
                        HStack(spacing: 4) {
                            if id == "favorites" { Image(systemName: "heart.fill").font(.system(size: 8)) }
                            Text(L10n.t("skins.filter.\(id)")).font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 12).frame(height: 29)
                        .foregroundStyle(filter == id ? Style.primaryText : Style.secondaryText)
                        .background(filter == id ? Style.control : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skins.filter.\(id)")
                }
                Spacer()
                Label(L10n.t("skins.featured.sort"), systemImage: "arrow.down")
                    .font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                    .help(L10n.t("skins.featured.snapshot", FeaturedSkin.snapshotDate))
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
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(visibleThemes) { theme in
                                themeCard(theme)
                            }
                        }
                        .padding(1)
                    }
                    .accessibilityIdentifier("skins.library.scroll")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            preview
            SkinActionFooter(store: store, themeID: store.selectedID)
        }
        .padding(.horizontal, Style.outerPadH).padding(.top, 48).padding(.bottom, 20)
        .onAppear {
            let available = Set(CursorCatalog.themes.map(\.id))
            favoriteIDs = favorites.intersection(available).sorted().joined(separator: ",")
        }
    }

    private func themeCard(_ theme: CursorTheme) -> some View {
        let selected = store.selectedID == theme.id
        return ZStack(alignment: .topTrailing) {
            Button {
                store.selectedID = theme.id
                detailID = theme.id
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 21) {
                        if let featured = theme.featured, !assets.isInstalled(theme.id) {
                            FeaturedRankMark(skin: featured)
                        } else if theme.id == "system" && store.needsRecovery {
                            Image(systemName: "cursorarrow").font(.system(size: 25))
                        } else {
                            ForEach([CursorRole.arrow, .text, .link], id: \.self) { role in
                                Image(nsImage: CursorCatalog.thumbnail(theme, role: role))
                                    .interpolation(theme.isPixelated ? .none : .high)
                                    .resizable().scaledToFit().frame(width: 32, height: 32)
                                    .shadow(color: .black.opacity(0.11), radius: 2, y: 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 83)
                    .background(Style.recess, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).fill(theme.color.opacity(0.14)).allowsHitTesting(false))
                    HStack(spacing: 6) {
                        Text(theme.name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                        if store.activeID == theme.id && !store.needsRecovery {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Style.success)
                        }
                        Spacer()
                        Text(L10n.t(theme.id == "system" ? "skins.native" :
                            theme.isBundled ? "skins.bundled" :
                            assets.isInstalled(theme.id) ? "skins.download.installed" : "skins.download.optional"))
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Style.secondaryText)
                    }
                    .padding(.top, 10)
                    HStack(spacing: 4) {
                        Text(theme.subtitle).lineLimit(1)
                        Spacer(minLength: 0)
                        if let featured = theme.featured {
                            Label(featured.sourceAddedText, systemImage: "flame")
                                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        }
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 10)).foregroundStyle(Style.secondaryText).padding(.top, 4)
                }
                .padding(9)
                .frame(height: 146)
                .background(Style.card, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Style.focus.opacity(0.7) : Style.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme.name)
                .accessibilityValue(theme.featured.map { L10n.t("skins.featured.popularity", $0.sourceAddedText) } ??
                    (selected ? L10n.t("skins.selected") : ""))
            .accessibilityHint(L10n.t("skins.detail.openHint"))
            .accessibilityIdentifier("skin.\(theme.id)")
            Button {
                var value = favorites
                if value.contains(theme.id) { value.remove(theme.id) } else { value.insert(theme.id) }
                favoriteIDs = value.sorted().joined(separator: ",")
            } label: {
                Image(systemName: favorites.contains(theme.id) ? "heart.fill" : "heart")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(favorites.contains(theme.id) ? Style.primaryText : Style.secondaryText)
                    .frame(width: 25, height: 25).background(Style.card, in: Circle())
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
            if store.selectedTheme.featured != nil && !assets.isInstalled(store.selectedID) {
                Label(L10n.t("skins.download.preview"), systemImage: "arrow.down.circle")
                    .font(.system(size: 11)).foregroundStyle(Style.secondaryText)
            } else {
              HStack(spacing: 5) {
                ForEach([CursorRole.arrow, .text, .link, .grab, .crosshair, .horizontal, .unavailable], id: \.self) { role in
                    VStack(spacing: 5) {
                        if store.needsRecovery && store.selectedID == "system" {
                            Image(systemName: "cursorarrow").frame(height: 38)
                        } else {
                            CursorHoverPreview(theme: store.selectedTheme, role: role)
                                .frame(height: 38)
                        }
                        Text(role.label).font(.system(size: 8)).foregroundStyle(Style.secondaryText).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
              }
            }
        }
        .padding(14)
        .glassSurface()
    }
}

struct SkinDetailView: View {
    let theme: CursorTheme
    @ObservedObject var store: CursorSkinStore
    @ObservedObject private var assets = SkinAssetStore.shared
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text(L10n.t("settings.skins")).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.vertical, 7).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("skin.detail.back")
                Spacer()
                Button {
                    var favorites = Set((UserDefaults.standard.string(forKey: "cursorFavorites") ?? "")
                        .split(separator: ",").map(String.init))
                    if favorites.contains(theme.id) { favorites.remove(theme.id) }
                    else { favorites.insert(theme.id) }
                    favoriteIDs = favorites.sorted().joined(separator: ",")
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isFavorite ? Style.primaryText : Style.secondaryText)
                        .frame(width: 30, height: 30).background(Style.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(isFavorite ? "skins.unfavorite" : "skins.favorite", theme.name))
                .accessibilityIdentifier("skin.detail.favorite")
            }
            .padding(.horizontal, Style.outerPadH).padding(.trailing, Style.scrollerGutter)
            .padding(.top, 42).padding(.bottom, 12)

            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 20) {
                        introduction.id("skin.detail.top")
                        if theme.featured != nil && !assets.isInstalled(theme.id) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(L10n.t("skins.download.get"), systemImage: "arrow.down.circle")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(L10n.t("skins.remote.downloadInstructions"))
                                    .font(.system(size: 12)).foregroundStyle(Style.secondaryText).lineSpacing(5)
                            }
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
                        } else {
                          HStack(alignment: .firstTextBaseline) {
                            Text(L10n.t("skins.detail.allTypes")).font(.system(size: 15, weight: .bold))
                            Spacer()
                            Text(L10n.t("skins.detail.typeCount", CursorRole.allCases.count))
                                .font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                        }
                        .padding(.bottom, -8)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(CursorRole.allCases, id: \.self) { role in
                                roleCard(role)
                            }
                        }
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "hourglass").font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L10n.t("skins.detail.waitTitle")).font(.system(size: 11, weight: .semibold))
                                Text(L10n.t("skins.detail.waitDescription"))
                                    .font(.system(size: 10)).foregroundStyle(Style.secondaryText).lineSpacing(3)
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface()
                        }
                    }
                    .padding(.horizontal, Style.outerPadH).padding(.top, 5).padding(.bottom, 20)
                }
                .scrollIndicators(.visible)
                .id("skin.detail.\(theme.id)")
                .accessibilityIdentifier("skin.detail.scroll")
                .onAppear {
                    // Reset after the first layout; the library and detail
                    // must never inherit each other's native scroll offset.
                    DispatchQueue.main.async { reader.scrollTo("skin.detail.top", anchor: .top) }
                }
            }

            SkinActionFooter(store: store, themeID: theme.id)
                .padding(.horizontal, Style.outerPadH).padding(.trailing, Style.scrollerGutter)
                .padding(.top, 12).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onBack)
    }

    @AppStorage("cursorFavorites") private var favoriteIDs = ""
    private var isFavorite: Bool { favoriteIDs.split(separator: ",").contains(Substring(theme.id)) }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 17) {
            Group {
                if let featured = theme.featured, !assets.isInstalled(theme.id) {
                    FeaturedRankMark(skin: featured)
                } else if !store.isReady && theme.id == "system" {
                    Image(systemName: "cursorarrow").font(.system(size: 35))
                } else {
                    Image(nsImage: CursorCatalog.image(theme, role: .arrow))
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 3)
                }
            }
            .frame(width: 126, height: 126)
            .background(Style.recess, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).fill(theme.color.opacity(0.12)).allowsHitTesting(false))
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(theme.name).font(.system(size: 24, weight: .bold))
                    if store.activeID == theme.id && !store.needsRecovery {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                            .foregroundStyle(Style.success)
                    }
                }
                Text(theme.introduction).font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(L10n.t(theme.id == "system" ? "skins.detail.nativeTheme" : "skins.detail.staticTheme"))
                    Text(L10n.t(assets.isInstalled(theme.id) ? "skins.detail.hover" :
                        "skins.download.preview"))
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(Style.secondaryText)
                if let featured = theme.featured {
                    Label(L10n.t("skins.featured.popularity", featured.sourceAddedText), systemImage: "flame")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Style.primaryText)
                    Text(L10n.t("skins.featured.snapshot", FeaturedSkin.snapshotDate))
                        .font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func roleCard(_ role: CursorRole) -> some View {
        let native = CursorCatalog.usesSystemCursor(theme, role: role)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if native && !store.isReady {
                    Image(systemName: "cursorarrow").font(.system(size: 23))
                } else {
                    CursorHoverPreview(theme: theme, role: role, previewSize: 54)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 73)
            .background(Style.recess, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).fill(theme.color.opacity(native ? 0.06 : 0.10)).allowsHitTesting(false))
            Text(role.detailLabel).font(.system(size: 11, weight: .semibold)).padding(.top, 9)
            Text(role.description).font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                .lineSpacing(2).frame(maxWidth: .infinity, minHeight: 27, alignment: .topLeading)
                .padding(.top, 4)
            if native {
                Text(L10n.t("skins.detail.systemType")).font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Style.secondaryText).padding(.top, 5)
            } else if theme.featured != nil && ![.arrow, .link].contains(role) {
                Text(L10n.t("skins.detail.supplemented")).font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Style.secondaryText).padding(.top, 5)
            }
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .glassSurface(radius: 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("skin.type.\(role.rawValue)")
    }
}

private struct SkinActionFooter: View {
    @ObservedObject var store: CursorSkinStore
    @ObservedObject private var assets = SkinAssetStore.shared
    @State private var confirmDeletion = false
    let themeID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle().fill(Style.line).frame(height: 1).padding(.bottom, 7)
            HStack(spacing: 8) {
                if let package = SkinPackage.find(themeID) {
                    if package.isBundled {
                        Label(L10n.t("skins.bundled"), systemImage: "checkmark.circle")
                        Text(L10n.t("skins.bundled.offline")).foregroundStyle(Style.secondaryText)
                        Spacer(minLength: 0)
                    } else if let progress = assets.progress[themeID] {
                        ProgressView(value: progress).frame(width: 92)
                        Text("\(Int(progress * 100))%").monospacedDigit()
                        Spacer(minLength: 0)
                        Button(L10n.t("skins.download.cancel")) { assets.cancel(themeID) }
                            .accessibilityIdentifier("skin.download.cancel")
                    } else if assets.isInstalled(themeID) {
                        Label(L10n.t("skins.download.installed"), systemImage: "checkmark.circle")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(assets.diskBytes(themeID) ?? package.byteCount), countStyle: .file))
                            .foregroundStyle(Style.secondaryText)
                        Spacer(minLength: 0)
                    } else {
                        Label(ByteCountFormatter.string(fromByteCount: Int64(package.byteCount), countStyle: .file),
                              systemImage: "arrow.down.circle")
                        Text(L10n.t("skins.download.local")).foregroundStyle(Style.secondaryText)
                        Spacer(minLength: 0)
                        Button(L10n.t("skins.download.get")) { assets.download(themeID) }
                            .accessibilityIdentifier("skin.download")
                    }
                } else {
                    Text(L10n.t("skins.native")).foregroundStyle(Style.secondaryText)
                    Spacer(minLength: 0)
                }
                if !store.needsRecovery && store.errorKey == nil {
                    Button(L10n.t("skins.exportDiagnostics")) { store.exportDiagnostics() }
                        .buttonStyle(.plain).font(.system(size: 9))
                        .foregroundStyle(Style.secondaryText)
                        .accessibilityIdentifier("skin.diagnostics")
                }
            }
            .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
            HStack(spacing: 10) {
                if themeID != "system" && SkinPackage.find(themeID)?.isBundled != true
                    && assets.isInstalled(themeID) && assets.progress[themeID] == nil {
                    Button { confirmDeletion = true } label: {
                        Label(L10n.t("skins.download.delete"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(kind: .destructive, height: 44))
                    .disabled(store.isBusy || store.needsRecovery)
                    .accessibilityIdentifier("skin.delete")
                }
                Button { store.reset() } label: {
                    Label(L10n.t("skins.reset"), systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(GlassButtonStyle(height: 44))
                    .disabled(store.isBusy || !store.isReady || !store.hasCustomCursor)
                    .accessibilityIdentifier("skin.reset")
                if assets.isInstalled(themeID) || !store.isReady {
                  Button {
                    if store.isReady { store.apply(themeID) } else { store.retry() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isBusy { ProgressView().controlSize(.mini).tint(Style.actionText) }
                        Text(L10n.t(store.isBusy ? "skins.applying" : !store.isReady ? "skins.retry" :
                            themeID == store.activeID ? "skins.applied" : "skins.apply"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(kind: .primary, height: 44))
                .disabled(store.isBusy || (store.isReady && themeID == store.activeID))
                .accessibilityIdentifier("skin.apply")
                }
            }
            if store.missingDownload && !assets.isInstalled(themeID) {
                Text(L10n.t("skins.download.upgrade"))
                    .font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = assets.errors[themeID] {
                Text(L10n.t("skins.download.error.\(error)")).font(.system(size: 9))
                    .foregroundStyle(Style.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = store.errorKey {
                Text(L10n.t("skins.error.\(error)")).font(.system(size: 9)).foregroundStyle(Style.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.needsRecovery {
                HStack {
                    Button(L10n.t("skins.nativeReset")) { store.useSystemCursor() }
                        .accessibilityIdentifier("skin.nativeReset")
                    Spacer()
                    Button(L10n.t("skins.exportDiagnostics")) { store.exportDiagnostics() }
                        .accessibilityIdentifier("skin.diagnostics")
                }
                .font(.system(size: 10, weight: .semibold)).buttonStyle(.plain)
                .disabled(store.isBusy)
            } else if store.errorKey != nil {
                Button(L10n.t("skins.exportDiagnostics")) { store.exportDiagnostics() }
                    .font(.system(size: 10)).buttonStyle(.plain)
                    .accessibilityIdentifier("skin.diagnostics")
            }
            if store.diagnosticError {
                Text(L10n.t("skins.diagnosticFailed")).font(.system(size: 9)).foregroundStyle(.red)
            }
        }
        .alert(L10n.t("skins.download.deleteTitle"), isPresented: $confirmDeletion) {
            Button(L10n.t("skins.download.cancel"), role: .cancel) {}
            Button(L10n.t("skins.download.delete"), role: .destructive) { store.removeSkin(themeID) }
        } message: {
            Text(L10n.t("skins.download.deleteMessage"))
        }
    }
}

private struct FeaturedRankMark: View {
    let skin: FeaturedSkin
    private var rank: Int { (FeaturedSkin.ranked.firstIndex { $0.id == skin.id } ?? 0) + 1 }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("#").font(.system(size: 16, weight: .light)).foregroundStyle(Style.secondaryText)
            Text(String(format: "%02d", rank)).font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit().foregroundStyle(Style.primaryText.opacity(0.8))
        }
        .accessibilityLabel(L10n.t("skins.featured.rank", rank))
    }
}

// Hover samples exercise an actual NSCursor without changing the global theme.
// cursor rects are updated by AppKit; no tracking timers or NSCursor push leaks.
private struct CursorHoverPreview: NSViewRepresentable {
    @ObservedObject private var assets = SkinAssetStore.shared
    let theme: CursorTheme
    let role: CursorRole
    var previewSize: CGFloat = 28
    func makeNSView(context: Context) -> SampleView { SampleView() }
    func updateNSView(_ view: SampleView, context: Context) {
        view.image = CursorCatalog.image(theme, role: role)
        view.previewSize = previewSize
        view.cursor = assets.isInstalled(theme.id)
            ? CursorCatalog.cursor(theme, role: role, scale: CursorSkinStore.shared.cursorScale,
                                   markerDiameter: CursorSkinStore.shared.markerDiameter)
            : CursorCatalog.systemCursor(.arrow)
        view.window?.invalidateCursorRects(for: view)
        view.needsDisplay = true
        view.setAccessibilityLabel(role.label)
        view.setAccessibilityIdentifier("skin.preview.\(theme.id).\(role.rawValue)")
    }
    final class SampleView: NSView {
        var image: NSImage?
        var cursor: NSCursor?
        var previewSize: CGFloat = 28
        override var isFlipped: Bool { true }
        override func resetCursorRects() {
            if let cursor { addCursorRect(bounds, cursor: cursor) }
        }
        override func draw(_ dirtyRect: NSRect) {
            if previewSize == 28 {
                Style.native(.white.withAlphaComponent(0.045), .black.withAlphaComponent(0.025)).setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            }
            guard let image else { return }
            let factor = min(previewSize / max(image.size.width, 1), previewSize / max(image.size.height, 1))
            let width = image.size.width * factor, height = image.size.height * factor
            image.draw(in: NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                                 width: width, height: height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
