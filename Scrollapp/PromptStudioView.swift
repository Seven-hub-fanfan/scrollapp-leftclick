import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PromptStudioView: View {
    @ObservedObject private var store = PromptStudioStore.shared
    @State private var showProviders = false
    @State private var showHistory = false
    @State private var showURL = false
    @State private var dropTargeted = false
    @State private var preview: NSImage?
    @State private var pasteMonitor: Any?
    private let tabs = ["cn", "en", "json", "negative"]

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                PageHeading(title: L10n.t("settings.prompt"), subtitle: L10n.t("prompt.intro"))
                Spacer(minLength: 12)
                Button { showHistory = true } label: {
                    Label(L10n.t("prompt.history"), systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(GlassButtonStyle(kind: .quiet)).accessibilityIdentifier("prompt.history")
                Button { showProviders = true } label: {
                    Label(L10n.t("prompt.api"), systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(GlassButtonStyle()).accessibilityIdentifier("prompt.providers")
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 12) {
                    imageCard
                    optionsCard
                }
                .frame(width: 266)
                resultCard
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, Style.outerPadH).padding(.top, 43).padding(.bottom, 18)
        .sheet(isPresented: $showProviders) { PromptProvidersView(store: store) }
        .sheet(isPresented: $showHistory) { PromptHistoryView(store: store) }
        .sheet(isPresented: $showURL) { PromptURLView { store.importURL($0) } }
        .onAppear { installPasteMonitor() }
        .onDisappear {
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            pasteMonitor = nil
        }
        .task(id: store.image?.id) {
            guard let image = store.image else { preview = nil; return }
            // ImageIO already decoded and resized this in the background.
            // Keep the AppKit wrapper on its owning UI actor.
            preview = NSImage(data: image.data)
        }
    }

    private var imageCard: some View {
        VStack(spacing: 0) {
            HStack {
                CardLabel(text: L10n.t("prompt.reference"))
                Spacer()
                if let image = store.image {
                    Text(image.ratio).font(.system(size: 9, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Style.secondaryText)
                }
            }.padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 10)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Style.recess)
                if let preview, store.image != nil {
                    Image(nsImage: preview).resizable().scaledToFit().padding(8)
                        .accessibilityLabel(store.image?.title ?? "")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 31, weight: .ultraLight)).foregroundStyle(Style.secondaryText)
                        Text(L10n.t("prompt.dropTitle")).font(.system(size: 13, weight: .medium))
                        Text(L10n.t("prompt.dropHint")).font(.system(size: 10))
                            .foregroundStyle(Style.secondaryText).multilineTextAlignment(.center).lineSpacing(3)
                    }
                    .padding(12)
                }
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 8).fill(Style.focus.opacity(0.12))
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Style.focus, lineWidth: 1.5)
                }
                if store.importing {
                    RoundedRectangle(cornerRadius: 8).fill(Style.recess.opacity(0.85))
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 164).padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .image, .url], isTargeted: $dropTargeted, perform: store.drop)
            .onPasteCommand(of: [.fileURL, .image, .url], perform: { _ = store.drop($0) })
            .accessibilityIdentifier("prompt.imageDrop")
            .overlay(alignment: .bottomTrailing) {
                if let image = store.image {
                    Button { store.removeImage(image.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Style.primaryText).frame(width: 24, height: 24)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain).padding(20)
                    .help(L10n.t("prompt.removeImage")).disabled(image.id == store.processingID)
                    .accessibilityLabel(L10n.t("prompt.removeImage"))
                }
            }
            HStack(spacing: 3) {
                sourceButton("folder", key: "import", action: store.openFiles)
                sourceButton("doc.on.clipboard", key: "paste", action: store.paste)
                sourceButton("viewfinder", key: "capture", action: store.capture)
                sourceButton("link", key: "imageLink") { showURL = true }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            if store.images.count > 1 {
                HStack(spacing: 6) {
                    ForEach(store.images) { image in
                        Button { store.selectedImageID = image.id } label: {
                            Group {
                                if let thumbnail = store.imageThumbnail(image) {
                                    Image(nsImage: thumbnail).resizable().scaledToFill()
                                } else { Rectangle().fill(Style.control) }
                            }
                            .frame(width: 38, height: 31).clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(store.selectedImageID == image.id ? Style.focus : Style.line, lineWidth: 1))
                            .overlay(alignment: .bottomTrailing) {
                                if store.results[image.id] != nil {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 8))
                                        .foregroundStyle(Style.success).background(.regularMaterial, in: Circle())
                                }
                            }
                        }
                        .buttonStyle(.plain).help(image.title).accessibilityLabel(image.title)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.bottom, 11)
            } else if let image = store.image {
                HStack(spacing: 6) {
                    Text(image.title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(image.dimensions).monospacedDigit().fixedSize()
                }
                .font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                .padding(.horizontal, 13).padding(.bottom, 11)
            }
        }
        .glassSurface()
    }

    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 9,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  NSApp.keyWindow?.attachedSheet == nil else { return event }
            let board = NSPasteboard.general
            let imageOrFile = board.availableType(from: [.png, .tiff, .fileURL]) != nil
            let editing = NSApp.keyWindow?.firstResponder is NSTextView
            let url = board.string(forType: .URL) ?? board.string(forType: .string) ?? ""
            guard imageOrFile || (!editing && URL(string: url)?.host != nil) else { return event }
            Task { @MainActor in store.paste() }
            return nil
        }
    }

    private func sourceButton(_ symbol: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(L10n.t("prompt.\(key)")).font(.system(size: 9)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Style.secondaryText)
        .disabled(store.importing || store.capturing || store.images.count >= PromptStudioStore.maximumImages)
        .help(L10n.t("prompt.\(key)Help")).accessibilityIdentifier("prompt.\(key)")
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("prompt.model")).font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                Spacer()
                if store.profile != nil {
                    Circle().fill(Style.success).frame(width: 4, height: 4).accessibilityHidden(true)
                }
            }
            Menu {
                ForEach(store.profiles) { profile in
                    Button {
                        store.selectedProfileID = profile.id
                    } label: {
                        Text(profile.displayName + " · " + profile.model)
                    }
                }
                if !store.profiles.isEmpty { Divider() }
                Button(L10n.t("prompt.addProvider")) { showProviders = true }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.profile?.displayName ?? L10n.t("prompt.connectFirst"))
                            .font(.system(size: 11.5, weight: .medium))
                        if let profile = store.profile {
                            Text(profile.model).font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .padding(.horizontal, 10).frame(height: 41).background(Style.recess, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .accessibilityIdentifier("prompt.model")
            HStack {
                Text(L10n.t("prompt.template")).font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                Spacer()
                Picker("", selection: $store.template) {
                    ForEach(PromptStudioStore.templates, id: \.self) { id in
                        Text(L10n.t("prompt.template.\(id)")).tag(id)
                    }
                }
                .labelsHidden().frame(width: 132).controlSize(.small)
                .accessibilityLabel(L10n.t("prompt.template")).accessibilityIdentifier("prompt.template")
            }
            TextField(L10n.t("prompt.instructionsHint"), text: $store.instructions, axis: .vertical)
                .lineLimit(2...3).font(.system(size: 10.5)).textFieldStyle(.plain)
                .padding(9).frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
                .background(Style.recess, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(L10n.t("prompt.instructions")).accessibilityIdentifier("prompt.instructions")
                .onChange(of: store.instructions) { value in
                    if value.count > 6000 { store.instructions = String(value.prefix(6000)) }
                }
        }
        .padding(13).glassSurface()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CardLabel(text: L10n.t("prompt.output"))
                Spacer(minLength: 3)
                if store.isAnalyzing {
                    ProgressView().controlSize(.mini)
                    Text(L10n.t("prompt.streaming")).font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                } else if store.result != nil {
                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(Style.success)
                }
            }
            .padding(.horizontal, 17).padding(.top, 15).padding(.bottom, 13)
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    Button { store.outputTab = tab } label: {
                        Text(L10n.t("prompt.tab.\(tab)")).font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 12).frame(height: 28)
                            .foregroundStyle(store.outputTab == tab ? Style.primaryText : Style.secondaryText)
                            .background(store.outputTab == tab ? Style.control : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("prompt.tab.\(tab)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
            Rectangle().fill(Style.line).frame(height: 1)
            ZStack {
                if store.processingID == store.selectedImageID, store.isAnalyzing {
                    if !store.liveText.isEmpty {
                        NativePromptText(text: VisionResult.partial(store.liveText, tab: store.outputTab),
                                         isJSON: store.outputTab == "json", streaming: true)
                    } else {
                        VStack(spacing: 13) {
                            ProgressView().controlSize(.small)
                            Text(L10n.t("prompt.analyzing")).font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                        }
                    }
                } else if let result = store.result {
                    let text = result.content(store.outputTab)
                    if text.isEmpty {
                        Text(L10n.t("prompt.noSection")).font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                    } else {
                        NativePromptText(text: text, isJSON: store.outputTab == "json", streaming: false)
                    }
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "text.alignleft").font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(Style.secondaryText.opacity(0.65))
                        Text(L10n.t("prompt.resultEmpty")).font(.system(size: 12, weight: .medium))
                        Text(L10n.t("prompt.resultHint")).font(.system(size: 10.5))
                            .foregroundStyle(Style.secondaryText).multilineTextAlignment(.center).lineSpacing(4)
                    }.padding(26)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let result = store.result, !result.tags.isEmpty, !store.isAnalyzing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(result.tags.prefix(7).enumerated()), id: \.offset) { _, tag in
                            Text(tag).font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Style.control, in: Capsule())
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            Rectangle().fill(Style.line).frame(height: 1)
            HStack {
                Text(store.result == nil ? L10n.t("prompt.bilingual") :
                    L10n.t("prompt.characterCount", store.result?.content(store.outputTab).count ?? 0))
                    .font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                Spacer()
                Button { store.copyResult() } label: {
                    Label(L10n.t("prompt.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassButtonStyle(height: 29))
                .disabled(store.result?.content(store.outputTab).isEmpty != false || store.isAnalyzing)
                .accessibilityIdentifier("prompt.copy")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).glassSurface()
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if let error = store.error {
                    Text(error).foregroundStyle(Style.error).lineLimit(3)
                        .accessibilityIdentifier("prompt.error")
                } else if let notice = store.notice {
                    Label(notice, systemImage: "checkmark.circle").foregroundStyle(Style.success)
                } else {
                    Text(L10n.t("prompt.localHint")).foregroundStyle(Style.secondaryText)
                }
            }
            .font(.system(size: 10)).frame(maxWidth: .infinity, alignment: .leading)
            if store.error == L10n.t("prompt.error.capturePermission") {
                Button(L10n.t("permission.open")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(GlassButtonStyle(kind: .quiet))
            }
            if store.isAnalyzing {
                Button(L10n.t("prompt.stop"), action: store.cancel)
                    .buttonStyle(GlassButtonStyle()).accessibilityIdentifier("prompt.cancel")
            } else {
                if store.images.count > 1 {
                    Button(L10n.t("prompt.analyzeAll", store.images.count)) { store.analyze(all: true) }
                        .buttonStyle(GlassButtonStyle()).disabled(!store.canAnalyze)
                        .accessibilityIdentifier("prompt.analyzeAll")
                }
                Button {
                    if store.profile == nil { showProviders = true }
                    else { store.analyze() }
                } label: {
                    Label(L10n.t(store.profile == nil ? "prompt.connect" :
                        store.result == nil ? "prompt.analyze" : "prompt.regenerate"), systemImage: "sparkle")
                        .frame(minWidth: 88)
                }
                .buttonStyle(GlassButtonStyle(kind: .primary, height: 37))
                .disabled(store.profile != nil && !store.canAnalyze)
                .accessibilityIdentifier("prompt.analyze")
            }
        }
        .frame(minHeight: 37)
    }
}

private struct NativePromptText: NSViewRepresentable {
    let text: String
    let isJSON: Bool
    let streaming: Bool
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 15, height: 16)
        view.setAccessibilityIdentifier("prompt.outputText")
        view.setAccessibilityLabel(L10n.t("prompt.output"))
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = isJSON ? 4 : 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: isJSON ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) :
                NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: Style.primaryNS, .paragraphStyle: paragraph
        ]
        if view.string != text || context.coordinator.json != isJSON ||
            context.coordinator.appearance != scroll.effectiveAppearance.name {
            let selection = view.selectedRange()
            let wasAtBottom = scroll.documentVisibleRect.maxY >= view.bounds.maxY - 30
            view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            if selection.location + selection.length <= (text as NSString).length { view.setSelectedRange(selection) }
            if streaming && wasAtBottom { view.scrollToEndOfDocument(nil) }
            context.coordinator.json = isJSON; context.coordinator.appearance = scroll.effectiveAppearance.name
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var json = false
        var appearance: NSAppearance.Name?
    }
}

private struct PromptURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    let onImport: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(L10n.t("prompt.imageLink")).font(.system(size: 20, weight: .semibold))
            Text(L10n.t("prompt.urlHint")).font(.system(size: 11)).foregroundStyle(Style.secondaryText).lineSpacing(4)
            TextField("https://…", text: $value).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("prompt.urlField")
                .onSubmit { submit() }
            HStack {
                Spacer()
                Button(L10n.t("action.cancel")) { dismiss() }.buttonStyle(GlassButtonStyle())
                Button(L10n.t("prompt.import")) { submit() }
                    .buttonStyle(GlassButtonStyle(kind: .primary)).disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("prompt.urlImport")
            }
        }
        .padding(26).frame(width: 450).foregroundStyle(Style.primaryText).background(GlassBackground())
    }
    private func submit() {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onImport(value); dismiss()
    }
}

struct PromptProvidersView: View {
    @ObservedObject var store: PromptStudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VisionProfile
    @State private var key = ""
    @State private var reveal = false
    @State private var reading = false
    @State private var saving = false
    @State private var probing = false
    @State private var status: String?
    @State private var failure: String?
    @State private var probeTask: Task<Void, Never>?
    init(store: PromptStudioStore) {
        self.store = store
        _draft = State(initialValue: store.profile ?? VisionProfile.presets[0].freshCopy())
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("prompt.apiTitle")).font(.system(size: 21, weight: .semibold))
                    Text(L10n.t("prompt.apiIntro")).font(.system(size: 10.5)).foregroundStyle(Style.secondaryText)
                }
                Spacer()
                Button { probeTask?.cancel(); dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).accessibilityLabel(L10n.t("prompt.close"))
            }.padding(24)
            Rectangle().fill(Style.line).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("prompt.savedProviders")).font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(store.profiles) { profile in
                                Button { select(profile) } label: {
                                    HStack {
                                        Text(profile.displayName).lineLimit(1)
                                        Spacer(minLength: 3)
                                        if draft.id == profile.id { Image(systemName: "checkmark").font(.system(size: 9)) }
                                    }
                                    .font(.system(size: 11, weight: .medium)).padding(10)
                                    .background(draft.id == profile.id ? Style.control : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if store.profiles.isEmpty {
                                Text(L10n.t("prompt.noProviders")).font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                            }
                        }
                    }
                    Menu {
                        ForEach(VisionProfile.presets, id: \.preset) { preset in
                            Button(preset.displayName) { select(preset.freshCopy()) }
                        }
                    } label: {
                        Label(L10n.t("prompt.addProvider"), systemImage: "plus")
                            .font(.system(size: 10.5)).frame(height: 30)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .accessibilityIdentifier("prompt.addProvider")
                }
                .padding(16).frame(width: 168).frame(maxHeight: .infinity).background(Style.rail)
                .disabled(saving || probing)
                Rectangle().fill(Style.line).frame(width: 1)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("prompt.configuration")).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Menu {
                            ForEach(VisionProfile.presets, id: \.preset) { preset in
                                Button(preset.displayName) {
                                    // A preset creates another account without overwriting a saved one.
                                    select(preset.freshCopy())
                                }
                            }
                        } label: {
                            Text(L10n.t("prompt.choosePreset")).font(.system(size: 10))
                        }.menuStyle(.borderlessButton).fixedSize().disabled(saving || probing)
                            .accessibilityIdentifier("prompt.preset")
                    }
                    field("name", value: $draft.name)
                    field("endpoint", value: $draft.baseURL)
                    field("modelID", value: $draft.model)
                    HStack(spacing: 10) {
                        Text(L10n.t("prompt.protocol")).font(.system(size: 10)).foregroundStyle(Style.secondaryText).frame(width: 69, alignment: .leading)
                        Picker("", selection: $draft.format) {
                            ForEach(VisionWireFormat.allCases, id: \.rawValue) { format in
                                Text(format.label).tag(format)
                            }
                        }.labelsHidden().controlSize(.small)
                            .accessibilityLabel(L10n.t("prompt.protocol")).accessibilityIdentifier("prompt.protocol")
                    }
                    HStack(spacing: 10) {
                        Text("API Key").font(.system(size: 10)).foregroundStyle(Style.secondaryText).frame(width: 69, alignment: .leading)
                        Group {
                            if reveal { TextField(L10n.t("prompt.keyHint"), text: $key) }
                            else { SecureField(L10n.t("prompt.keyHint"), text: $key) }
                        }
                        .textFieldStyle(.roundedBorder).font(.system(size: 11)).accessibilityIdentifier("prompt.key")
                        Button { reveal.toggle() } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye").font(.system(size: 11))
                        }.buttonStyle(.plain).accessibilityLabel(L10n.t("prompt.revealKey"))
                    }
                    Toggle(L10n.t("prompt.requireKey"), isOn: $draft.requiresKey)
                        .font(.system(size: 10)).toggleStyle(.checkbox).disabled(draft.format != .openAI)
                        .onChange(of: draft.format) { format in if format != .openAI { draft.requiresKey = true } }
                    Text(L10n.t(draft.preset == "volcengine" ? "prompt.arkHint" : "prompt.endpointHint"))
                        .font(.system(size: 9.5)).foregroundStyle(Style.secondaryText).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let failure {
                        Text(failure).font(.system(size: 10)).foregroundStyle(Style.error).lineLimit(3)
                            .accessibilityIdentifier("prompt.profileError")
                    } else if let status {
                        Label(status, systemImage: "checkmark.circle").font(.system(size: 10)).foregroundStyle(Style.success)
                    }
                }
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).disabled(saving || reading)
            }
            Rectangle().fill(Style.line).frame(height: 1)
            HStack(spacing: 10) {
                if store.profiles.contains(where: { $0.id == draft.id }) {
                    Button { delete() } label: { Image(systemName: "trash") }
                        .buttonStyle(GlassButtonStyle(kind: .destructive)).disabled(saving || probing)
                        .accessibilityLabel(L10n.t("prompt.deleteProvider"))
                }
                Text(L10n.t("prompt.keychainHint")).font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                Spacer(minLength: 6)
                Button(L10n.t(probing ? "prompt.testing" : "prompt.test")) { test() }
                    .buttonStyle(GlassButtonStyle()).disabled(probing || saving || reading)
                    .accessibilityIdentifier("prompt.test")
                Button(L10n.t(saving ? "prompt.saving" : "prompt.save")) { save() }
                    .buttonStyle(GlassButtonStyle(kind: .primary)).disabled(saving || probing || reading)
                    .accessibilityIdentifier("prompt.save")
            }
            .padding(.horizontal, 20).padding(.vertical, 15)
        }
        .frame(width: 682, height: 532).foregroundStyle(Style.primaryText).background(GlassBackground())
        .task(id: draft.id) {
            let id = draft.id; reading = true; key = ""; status = nil; failure = nil; reveal = false
            do {
                let stored = try await store.apiKey(id)
                if !Task.isCancelled, draft.id == id { key = stored }
            } catch {
                if !Task.isCancelled, draft.id == id { failure = error.localizedDescription }
            }
            if draft.id == id { reading = false }
        }
        .onDisappear { probeTask?.cancel() }
    }
    private func field(_ key: String, value: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(L10n.t("prompt.\(key)")).font(.system(size: 10)).foregroundStyle(Style.secondaryText).frame(width: 69, alignment: .leading)
            TextField("", text: value).textFieldStyle(.roundedBorder).font(.system(size: 11))
                .accessibilityLabel(L10n.t("prompt.\(key)")).accessibilityIdentifier("prompt.\(key)")
        }
    }
    private func select(_ value: VisionProfile) { draft = value; status = nil; failure = nil }
    private func save() {
        saving = true; failure = nil; status = nil
        Task {
            do { try await store.saveProfile(draft, key: key); status = L10n.t("prompt.profileSaved") }
            catch { failure = error.localizedDescription }
            saving = false
        }
    }
    private func test() {
        probing = true; failure = nil; status = nil
        let profile = draft, secret = key
        probeTask = Task {
            do { try await store.probe(profile, key: secret); status = L10n.t("prompt.testOK") }
            catch { if !Task.isCancelled { failure = error.localizedDescription } }
            probing = false; probeTask = nil
        }
    }
    private func delete() {
        let id = draft.id
        StyledDialog.present(title: L10n.t("prompt.deleteProvider"),
            message: L10n.t("prompt.deleteProviderConfirm"), primaryTitle: L10n.t("prompt.delete"),
            secondaryTitle: L10n.t("action.cancel")) { confirmed in
            guard confirmed else { return }
            Task {
                do {
                    try await store.deleteProfile(id)
                    select(store.profiles.first ?? VisionProfile.presets[0].freshCopy())
                } catch { failure = error.localizedDescription }
            }
        }
    }
}

private struct PromptHistoryView: View {
    @ObservedObject var store: PromptStudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var favorites = false
    private var visible: [PromptHistoryEntry] {
        store.history.filter {
            (!favorites || $0.favorite) && (search.isEmpty ||
                ($0.title + $0.result.chinese + $0.result.english + $0.provider)
                    .localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L10n.t("prompt.history")).font(.system(size: 21, weight: .semibold))
                Text("\(store.history.count)").font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel(L10n.t("prompt.close"))
            }
            HStack(spacing: 12) {
                TextField(L10n.t("prompt.search"), text: $search).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("prompt.historySearch")
                Toggle(L10n.t("prompt.favorites"), isOn: $favorites).toggleStyle(.checkbox)
                    .font(.system(size: 11)).fixedSize()
                Button(L10n.t("prompt.export")) { store.export(visible) }
                    .buttonStyle(GlassButtonStyle()).disabled(visible.isEmpty)
            }
            if visible.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Style.secondaryText)
                    Text(L10n.t("prompt.historyEmpty")).font(.system(size: 12)).foregroundStyle(Style.secondaryText)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(visible) { entry in
                            PromptHistoryRow(entry: entry, store: store) {
                                store.restore(entry); dismiss()
                            }
                        }
                    }
                }
            }
            Text(L10n.t("prompt.historyHint")).font(.system(size: 9.5)).foregroundStyle(Style.secondaryText)
        }
        .padding(24).frame(width: 700, height: 560).foregroundStyle(Style.primaryText).background(GlassBackground())
    }
}

private struct PromptHistoryRow: View {
    let entry: PromptHistoryEntry
    @ObservedObject var store: PromptStudioStore
    let open: () -> Void
    @State private var thumbnail: NSImage?
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
                    .frame(width: 70, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9)).foregroundStyle(Style.secondaryText)
                }
                Text(entry.result.content("cn")).font(.system(size: 10)).lineLimit(2).lineSpacing(3)
                    .foregroundStyle(Style.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.provider + " · " + entry.model).font(.system(size: 9))
                    .foregroundStyle(Style.secondaryText).lineLimit(1)
            }
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button { store.toggleFavorite(entry) } label: {
                        Image(systemName: entry.favorite ? "star.fill" : "star")
                            .foregroundStyle(entry.favorite ? Style.focus : Style.secondaryText)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.t("prompt.favorites"))
                    Button {
                        StyledDialog.present(title: L10n.t("prompt.deleteHistory"),
                            message: L10n.t("prompt.deleteHistoryConfirm"), primaryTitle: L10n.t("prompt.delete"),
                            secondaryTitle: L10n.t("action.cancel")) { confirmed in
                                if confirmed { store.removeHistory(entry) }
                            }
                    } label: { Image(systemName: "trash").foregroundStyle(Style.error) }
                        .buttonStyle(.plain).accessibilityLabel(L10n.t("prompt.deleteHistory"))
                }.font(.system(size: 11))
                Button(action: open) { Image(systemName: "arrow.up.right").frame(width: 35) }
                    .buttonStyle(GlassButtonStyle(height: 27)).disabled(store.isAnalyzing || store.importing)
                    .accessibilityLabel(L10n.t("prompt.reopen"))
            }
        }
        .padding(12).glassSurface(radius: 9)
        .task(id: entry.id) { thumbnail = await store.historyThumbnail(entry.id) }
    }
}
