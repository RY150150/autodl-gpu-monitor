import AppKit
import Foundation

private enum ProductTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                calibratedRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1
            )
        }
    }

    static let background = adaptive(0xFAFBFA, 0x191C1B)
    static let control = adaptive(0xFFFFFF, 0x232725)
    static let text = adaptive(0x202B26, 0xECF1ED)
    static let secondary = adaptive(0x78817C, 0xA2ADA6)
    static let line = adaptive(0xDEE4DF, 0x363E38)
    static let accent = adaptive(0x237858, 0x6FC9A1)
    static let button = adaptive(0x237858, 0x2D8863)
    static let logBackground = adaptive(0xF1F4F2, 0x141715)
}

private final class ProductSurface: NSView {
    private let fill: NSColor
    private let border: NSColor?
    private let radius: CGFloat

    init(fill: NSColor, border: NSColor? = nil, radius: CGFloat = 6) {
        self.fill = fill
        self.border = border
        self.radius = radius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = border == nil ? 0 : 0.5
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: radius, yRadius: radius
        )
        fill.setFill()
        path.fill()
        if let border {
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class ProductPopup: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6
        )
        ProductTheme.control.setFill()
        path.fill()
        (focused ? ProductTheme.accent : ProductTheme.line).setStroke()
        path.lineWidth = 1
        path.stroke()
        let color = isEnabled ? ProductTheme.text : ProductTheme.secondary
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: titleOfSelectedItem ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color, .paragraphStyle: paragraph
        ])
        text.draw(in: NSRect(
            x: 12, y: (bounds.height - text.size().height) / 2,
            width: bounds.width - 42, height: text.size().height
        ))
        let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        color.set()
        if let chevron, let tinted = chevron.copy() as? NSImage {
            tinted.lockFocus()
            color.setFill()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: bounds.width - 25, y: (bounds.height - 10) / 2, width: 12, height: 10))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class ProductButton: NSButton {
    var primary = false
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func draw(_ dirtyRect: NSRect) {
        let fill = primary ? ProductTheme.button : ProductTheme.control
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6
        )
        (isHighlighted ? fill.blended(withFraction: 0.12, of: .black)! : fill).setFill()
        path.fill()
        if !primary {
            ProductTheme.line.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let color: NSColor = !isEnabled ? ProductTheme.secondary.withAlphaComponent(0.55) :
            (primary ? .white : ProductTheme.text)
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color
        ])
        let totalWidth = text.size().width + 22
        let startX = (bounds.width - totalWidth) / 2
        let glyph = NSImage(
            systemSymbolName: primary ? "play.fill" : "stop.fill", accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        if let glyph, let tinted = glyph.copy() as? NSImage {
            tinted.lockFocus()
            color.setFill()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: startX, y: (bounds.height - 11) / 2, width: 11, height: 11))
        }
        text.draw(at: NSPoint(x: startX + 22, y: (bounds.height - text.size().height) / 2))
        if window?.firstResponder === self {
            ProductTheme.accent.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4)
            ring.lineWidth = 1
            ring.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let statusIndicator = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "已停止")
    private let priceField = NSTextField(string: "3.00")
    private let billingPopup = ProductPopup()
    private let regionPopup = ProductPopup()
    private let gpuPopup = ProductPopup()
    private let gpuCountPopup = ProductPopup()
    private let imageTypePopup = ProductPopup()
    private let imageNameField = NSTextField(string: "")
    private let priceUnitLabel = NSTextField(labelWithString: "元/小时")
    private let autoRentToggle = NSButton(checkboxWithTitle: "发现后自动租赁一台，成功提交后停止", target: nil, action: nil)
    private let startButton = ProductButton(title: "开始监控", target: nil, action: nil)
    private let stopButton = ProductButton(title: "停止", target: nil, action: nil)
    private let logView = NSTextView()
    private let historyView = NSTextView()
    private let logTabs = NSSegmentedControl()
    private let liveLogScroll = NSScrollView()
    private let historyScroll = NSScrollView()
    private var outputBuffer = Data()
    private var rentalReceipts: [String: RentalReceipt] = [:]
    private var orderResult: String?
    private var activeOrderId: String?
    private var process: Process?
    private var outputPipe: Pipe?
    private var launchTask: Process?
    private var launchTimer: DispatchWorkItem?
    private var hasSubmittedOrder = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 786),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AutoDL 算力监控"
        window.center()
        window.minSize = NSSize(width: 820, height: 770)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ProductTheme.background

        autoRentToggle.state = .on
        autoRentToggle.title = "发现可用主机后自动租赁一台"
        autoRentToggle.font = .systemFont(ofSize: 12, weight: .medium)
        autoRentToggle.contentTintColor = ProductTheme.accent

        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(startMonitoring)
        startButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "开始")
        startButton.imagePosition = .imageLeading
        startButton.primary = true
        startButton.toolTip = "开始监控"
        startButton.widthAnchor.constraint(equalToConstant: 142).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: 38).isActive = true

        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stopMonitoring)
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "停止")
        stopButton.imagePosition = .imageLeading
        stopButton.toolTip = "停止监控"
        stopButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        stopButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        stopButton.isEnabled = false

        priceField.alignment = .right
        priceField.placeholderString = "3.00"
        priceField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        priceUnitLabel.font = .systemFont(ofSize: 12)
        priceUnitLabel.textColor = ProductTheme.secondary

        billingPopup.addItems(withTitles: ["按量计费", "包日", "包周", "包月"])
        regionPopup.addItems(withTitles: ["西北B区", "北京B区", "重庆A区", "内蒙B区", "北京A区", "佛山区", "V100专区", "A800专区", "摩尔线程专区"])
        gpuPopup.addItems(withTitles: [
            "vGPU-32GB", "RTX 5090", "RTX PRO 6000", "RTX 6000D",
            "PRO 6000 Max-Q", "vGPU-48GB", "RTX 5090 D", "RTX PRO 5000",
            "H800", "RTX 4090D", "RTX 4090", "RTX 3090", "RTX 3080 Ti",
            "RTX 3080x2", "RTX A4000", "RTX 3060", "GTX 1080 Ti", "CPU",
            "CPU-close-HT", "vGPU-48GB-350W"
        ])
        gpuCountPopup.addItems(withTitles: ["1", "2", "3", "4", "5", "6", "7", "8", "10", "12"])
        imageTypePopup.addItems(withTitles: ["基础镜像", "社区镜像", "我的镜像"])
        regionPopup.selectItem(withTitle: "内蒙B区")
        gpuPopup.selectItem(withTitle: "RTX 4090")
        imageTypePopup.selectItem(withTitle: "我的镜像")
        imageTypePopup.target = self
        imageTypePopup.action = #selector(imageTypeChanged)
        billingPopup.target = self
        billingPopup.action = #selector(billingChanged)
        [billingPopup, regionPopup, gpuPopup, gpuCountPopup, imageTypePopup].forEach {
            $0.controlSize = .regular
            $0.font = .systemFont(ofSize: 13, weight: .medium)
            $0.focusRingType = .none
            $0.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        imageNameField.font = .systemFont(ofSize: 13)
        imageNameField.placeholderString = "请输入所选镜像的准确名称"

        let brand = ProductSurface(fill: ProductTheme.accent, radius: 8)
        let brandIcon = symbol("cpu", size: 23, color: .white)
        brand.addSubview(brandIcon)
        NSLayoutConstraint.activate([
            brand.widthAnchor.constraint(equalToConstant: 44),
            brand.heightAnchor.constraint(equalToConstant: 44),
            brandIcon.centerXAnchor.constraint(equalTo: brand.centerXAnchor),
            brandIcon.centerYAnchor.constraint(equalTo: brand.centerYAnchor)
        ])
        let heading = label("AutoDL", size: 24, weight: .bold)
        let titleStack = column([
            heading,
            label("算力监控", size: 12, color: ProductTheme.secondary)
        ], spacing: 4)

        statusIndicator.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "状态")
        statusIndicator.contentTintColor = .systemGray
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusIndicator.widthAnchor.constraint(equalToConstant: 7),
            statusIndicator.heightAnchor.constraint(equalToConstant: 7)
        ])
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let statusStack = row([statusIndicator, statusLabel], spacing: 7)
        let header = row([brand, titleStack, NSView(), statusStack], spacing: 14)
        header.heightAnchor.constraint(equalToConstant: 74).isActive = true

        let resources = column([
            equalColumns(
                field("地区", control: regionPopup),
                field("GPU 型号", control: gpuPopup)
            ),
            equalColumns(
                field("计费方式", control: billingPopup),
                field("GPU 数量", control: gpuCountPopup)
            )
        ], spacing: 16)
        let images = equalColumns(
            field("镜像类型", control: imageTypePopup),
            field("镜像名称", control: textSurface(imageNameField))
        )
        let priceControl = row([textSurface(priceField), priceUnitLabel], spacing: 10)
        priceControl.views[0].widthAnchor.constraint(equalToConstant: 118).isActive = true
        let automation = column([
            label("自动操作", size: 11, color: ProductTheme.secondary),
            autoRentToggle
        ], spacing: 12)
        let policy = equalColumns(field("最高价格", control: priceControl), automation)

        let facts = row([
            symbol("clock", size: 12, color: ProductTheme.secondary),
            label("轮询周期  5 秒", size: 12, color: ProductTheme.secondary),
            label("·", size: 12, color: ProductTheme.secondary),
            label("订单上限  1 台", size: 12, color: ProductTheme.secondary)
        ], spacing: 8)
        let actions = row([facts, NSView(), stopButton, startButton], spacing: 10)
        actions.heightAnchor.constraint(equalToConstant: 64).isActive = true

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textColor = ProductTheme.secondary
        logView.drawsBackground = false
        logView.textContainerInset = NSSize(width: 16, height: 14)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.minSize = NSSize(width: 0, height: 120)
        logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logView.textContainer?.widthTracksTextView = true
        logView.string = "应用已就绪。开始后会每 5 秒检查一次库存。\n"
        logView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: ProductTheme.secondary
        ]

        let scrollView = liveLogScroll
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        logView.frame = NSRect(x: 0, y: 0, width: 800, height: 140)
        scrollView.documentView = logView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        logTabs.segmentCount = 2
        logTabs.setLabel("运行日志", forSegment: 0)
        logTabs.setLabel("租用日志", forSegment: 1)
        logTabs.setWidth(86, forSegment: 0)
        logTabs.setWidth(86, forSegment: 1)
        logTabs.selectedSegment = 0
        logTabs.segmentStyle = .rounded
        logTabs.font = .systemFont(ofSize: 12, weight: .medium)
        logTabs.target = self
        logTabs.action = #selector(changeLogTab)

        let folderButton = NSButton(
            image: NSImage(systemSymbolName: "folder", accessibilityDescription: "打开租用日志文件夹")!,
            target: self, action: #selector(openReceiptFolder)
        )
        folderButton.isBordered = false
        folderButton.contentTintColor = ProductTheme.secondary
        folderButton.toolTip = "打开租用日志文件夹"
        folderButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        folderButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let logHeader = row([logTabs, NSView(), folderButton], spacing: 8)
        let logSurface = ProductSurface(fill: ProductTheme.logBackground, border: ProductTheme.line)
        logSurface.addSubview(scrollView)

        historyView.isEditable = false
        historyView.drawsBackground = false
        historyView.isVerticallyResizable = true
        historyView.isHorizontallyResizable = false
        historyView.autoresizingMask = [.width]
        historyView.textContainer?.widthTracksTextView = true
        historyView.textContainerInset = NSSize(width: 16, height: 14)
        historyView.frame = NSRect(x: 0, y: 0, width: 800, height: 140)
        historyScroll.hasVerticalScroller = true
        historyScroll.autohidesScrollers = true
        historyScroll.borderType = .noBorder
        historyScroll.drawsBackground = false
        historyScroll.documentView = historyView
        historyScroll.isHidden = true
        historyScroll.translatesAutoresizingMaskIntoConstraints = false
        logSurface.addSubview(historyScroll)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: logSurface.leadingAnchor, constant: 1),
            scrollView.trailingAnchor.constraint(equalTo: logSurface.trailingAnchor, constant: -1),
            scrollView.topAnchor.constraint(equalTo: logSurface.topAnchor, constant: 1),
            scrollView.bottomAnchor.constraint(equalTo: logSurface.bottomAnchor, constant: -1),
            logSurface.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            historyScroll.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            historyScroll.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            historyScroll.topAnchor.constraint(equalTo: scrollView.topAnchor),
            historyScroll.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
        refreshRentalHistory()
        logSurface.setContentHuggingPriority(.defaultLow, for: .vertical)
        let logStack = column([logHeader, logSurface], spacing: 12)
        let stack = column([
            header,
            separator(),
            section("算力资源", number: "01", symbolName: "square.3.layers.3d", body: resources),
            separator(),
            section("运行镜像", number: "02", symbolName: "shippingbox", body: images),
            separator(),
            section("租赁策略", number: "03", symbolName: "slider.horizontal.3", body: policy),
            separator(),
            actions,
            logStack
        ], spacing: 0)
        stack.setCustomSpacing(20, after: actions)

        let content = ProductSurface(fill: ProductTheme.background, radius: 0)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])
        window.contentView = content
        window.initialFirstResponder = nil
        window.makeFirstResponder(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func label(
        _ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
        color: NSColor = ProductTheme.text
    ) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = color
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }

    private func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
        view.contentTintColor = color
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size + 2).isActive = true
        view.heightAnchor.constraint(equalToConstant: size + 2).isActive = true
        return view
    }

    private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func equalColumns(_ left: NSView, _ right: NSView) -> NSView {
        let stack = row([left, right], spacing: 22)
        stack.alignment = .top
        left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        return stack
    }

    private func field(_ title: String, control: NSView) -> NSView {
        let view = column([
            label(title, size: 11, weight: .medium, color: ProductTheme.secondary), control
        ], spacing: 8)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    private func textSurface(_ field: NSTextField) -> NSView {
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = ProductTheme.text
        field.focusRingType = .exterior
        field.translatesAutoresizingMaskIntoConstraints = false
        let surface = ProductSurface(fill: ProductTheme.control, border: ProductTheme.line)
        surface.addSubview(field)
        NSLayoutConstraint.activate([
            surface.heightAnchor.constraint(equalToConstant: 36),
            field.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 20)
        ])
        return surface
    }

    private func section(_ title: String, number: String, symbolName: String, body: NSView) -> NSView {
        let titleRow = row([
            symbol(symbolName, size: 14, color: ProductTheme.accent),
            label(title, size: 13, weight: .semibold)
        ], spacing: 8)
        let sectionTitle = column([
            label(number, size: 10, weight: .medium, color: ProductTheme.secondary),
            titleRow
        ], spacing: 10)
        sectionTitle.widthAnchor.constraint(equalToConstant: 128).isActive = true
        let contents = row([sectionTitle, body], spacing: 22)
        contents.alignment = .top
        let container = NSView()
        container.addSubview(contents)
        NSLayoutConstraint.activate([
            contents.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contents.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contents.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            contents.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
            body.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -150)
        ])
        container.setContentHuggingPriority(.required, for: .vertical)
        return container
    }

    private func separator() -> NSView {
        let view = ProductSurface(fill: ProductTheme.line, radius: 0)
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    @objc private func startMonitoring() {
        guard process == nil else { return }
        guard let price = Double(priceField.stringValue), price > 0 else {
            showAlert("价格无效", "请输入大于 0 的价格上限。")
            return
        }
        let imageName = imageNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imageName.isEmpty else {
            showAlert("镜像名称为空", "请输入要使用的镜像名称。")
            return
        }

        hasSubmittedOrder = false
        orderResult = nil
        activeOrderId = nil
        outputBuffer.removeAll()
        setRunning(true, status: "正在启动专用 Chrome…")
        appendLog("启动专用 Chrome 配置并连接 AutoDL…")

        let launch = Process()
        launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = [
            "-na", "Google Chrome", "--args",
            "--remote-debugging-port=9222",
            "--user-data-dir=\(NSHomeDirectory())/Library/Application Support/AutoDLMonitor/chrome-profile"
        ]
        do {
            try launch.run()
            launchTask = launch
            let work = DispatchWorkItem { [weak self] in
                self?.launchTask = nil
                self?.launchTimer = nil
                self?.launchWatcher(price: price, imageName: imageName)
            }
            launchTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        } catch {
            setRunning(false, status: "Chrome 启动失败")
            appendLog("无法启动 Chrome：\(error.localizedDescription)")
        }
    }

    private func launchWatcher(price: Double, imageName: String) {
        guard process == nil else { return }
        let watcher = Process()
        var scriptArguments = [
            "--max-hourly-price", String(price),
            "--interval", "5",
            "--billing-mode", billingPopup.titleOfSelectedItem ?? "按量计费",
            "--region", regionPopup.titleOfSelectedItem ?? "内蒙B区",
            "--gpu-model", gpuPopup.titleOfSelectedItem ?? "RTX 4090",
            "--gpu-count", gpuCountPopup.titleOfSelectedItem ?? "1",
            "--image-type", imageTypePopup.titleOfSelectedItem ?? "我的镜像",
            "--image-name", imageName,
            "--receipt-log", RentalHistory.fileURL.path
        ]
        if !autoRentToggle.state.hasFlag(.on) {
            scriptArguments.append("--monitor-only")
        }
        if let bundledWatcher = Bundle.main.url(forResource: "autodl_watch", withExtension: nil) {
            watcher.executableURL = bundledWatcher
            watcher.arguments = scriptArguments
        } else {
            let scriptURL = Bundle.main.resourceURL!.appendingPathComponent("autodl_watch.py")
            watcher.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            watcher.arguments = ["python3", scriptURL.path] + scriptArguments
        }
        watcher.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]) { _, preferred in preferred }

        let pipe = Pipe()
        watcher.standardOutput = pipe
        watcher.standardError = pipe
        outputPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consumeOutputData(data) }
        }
        watcher.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                guard let self else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.outputPipe = nil
                if !self.outputBuffer.isEmpty {
                    self.consumeOutput(String(decoding: self.outputBuffer, as: UTF8.self))
                    self.outputBuffer.removeAll()
                }
                self.refreshRentalHistory()
                if let id = self.activeOrderId, let receipt = self.rentalReceipts[id] {
                    self.orderResult = receipt.statusTitle + "，监控已停止"
                }
                if self.hasSubmittedOrder {
                    self.setRunning(false, status: self.orderResult ?? "订单已提交，结果待确认；监控已停止")
                } else {
                    self.setRunning(false, status: task.terminationStatus == 0 ? "已停止" : "运行结束（检查日志）")
                }
                self.appendLog("监控进程已结束。")
            }
        }

        do {
            try watcher.run()
            process = watcher
            setRunning(true, status: "正在监控，5 秒检查一次")
            appendLog("监控已启动；配置：\(billingPopup.titleOfSelectedItem ?? "") · \(regionPopup.titleOfSelectedItem ?? "") · \(gpuPopup.titleOfSelectedItem ?? "") × \(gpuCountPopup.titleOfSelectedItem ?? "") · \(imageTypePopup.titleOfSelectedItem ?? "")/\(imageName)；自动租赁：\(autoRentToggle.state.hasFlag(.on) ? "开启" : "关闭")；价格上限：\(String(format: "%.2f", price)) \(priceUnitLabel.stringValue)。")
        } catch {
            setRunning(false, status: "启动失败")
            appendLog("无法启动监控脚本：\(error.localizedDescription)")
        }
    }

    @objc private func billingChanged() {
        let units = ["按量计费": "元/小时", "包日": "元/天", "包周": "元/周", "包月": "元/月"]
        priceUnitLabel.stringValue = units[billingPopup.titleOfSelectedItem ?? "按量计费"] ?? "元"
    }

    @objc private func imageTypeChanged() {
        imageNameField.placeholderString = "请输入所选镜像的准确名称"
    }

    @objc private func stopMonitoring() {
        launchTimer?.cancel()
        launchTimer = nil
        launchTask?.terminate()
        launchTask = nil
        if let process, process.isRunning {
            process.terminate()
            appendLog("已请求停止监控。")
        } else {
            setRunning(false, status: "已停止")
        }
    }

    private func consumeOutput(_ text: String) {
        let prefix = "AUTODL_RECEIPT "
        if text.hasPrefix(prefix),
           let data = String(text.dropFirst(prefix.count)).data(using: .utf8),
           let receipt = RentalHistory.decode(data) {
            hasSubmittedOrder = true
            activeOrderId = receipt.orderId
            rentalReceipts[receipt.orderId] = receipt
            renderRentalHistory()
            orderResult = receipt.statusTitle + "，监控已停止"
            setRunning(process != nil, status: receipt.status == "submitted" ?
                "订单已提交，正在确认租用结果…" : orderResult!)
            if receipt.status == "confirmed" {
                logTabs.selectedSegment = 1
                changeLogTab()
            }
            return
        }
        appendLog(text)
        if text.contains("已点击“创建并开机”提交租赁") {
            hasSubmittedOrder = true
            setRunning(true, status: "订单已提交，正在确认租用结果…")
        }
    }

    private func consumeOutputData(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = String(decoding: outputBuffer[..<newline], as: UTF8.self)
            outputBuffer.removeSubrange(...newline)
            consumeOutput(line)
        }
    }

    @objc private func changeLogTab() {
        liveLogScroll.isHidden = logTabs.selectedSegment == 1
        historyScroll.isHidden = logTabs.selectedSegment == 0
        if logTabs.selectedSegment == 1 { refreshRentalHistory() }
    }

    @objc private func openReceiptFolder() {
        let folder = RentalHistory.fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            showAlert("无法打开日志文件夹", error.localizedDescription)
        }
    }

    private func refreshRentalHistory() {
        do {
            for receipt in try RentalHistory.read() {
                if let existing = rentalReceipts[receipt.orderId], existing.timestamp > receipt.timestamp { continue }
                rentalReceipts[receipt.orderId] = receipt
            }
        } catch {
            appendLog("无法读取租用日志：\(error.localizedDescription)")
        }
        renderRentalHistory()
    }

    private func renderRentalHistory() {
        let content = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let normal: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: ProductTheme.secondary,
            .paragraphStyle: paragraph
        ]
        for receipt in rentalReceipts.values.sorted(by: { $0.timestamp > $1.timestamp }) {
            let color: NSColor = receipt.status == "confirmed" ? ProductTheme.accent :
                (receipt.status == "failed" ? .systemRed : .systemOrange)
            content.append(NSAttributedString(
                string: "\(receipt.statusTitle)    \(receipt.displayTime)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                             .foregroundColor: color, .paragraphStyle: paragraph]
            ))
            let price = String(format: "%.2f", receipt.configPrice)
            content.append(NSAttributedString(
                string: "\(receipt.region) · \(receipt.hostLabel) · \(receipt.gpuModel) × \(receipt.gpuCount) · \(price) \(receipt.priceUnit)\n" +
                    "\(receipt.imageType) / \(receipt.imageName) · 实例 \(receipt.instanceId ?? "未确认")\n\n",
                attributes: normal
            ))
        }
        if rentalReceipts.isEmpty {
            content.append(NSAttributedString(string: "暂无租用记录。", attributes: normal))
        }
        historyView.textStorage?.setAttributedString(content)
    }

    private func setRunning(_ running: Bool, status: String) {
        statusLabel.stringValue = status
        statusLabel.textColor = running ? .systemGreen : .secondaryLabelColor
        statusIndicator.contentTintColor = running ? .systemGreen : .systemGray
        startButton.isEnabled = !running
        stopButton.isEnabled = running
        priceField.isEnabled = !running
        autoRentToggle.isEnabled = !running
        [
            billingPopup, regionPopup, gpuPopup, gpuCountPopup,
            imageTypePopup, imageNameField
        ].forEach { $0.isEnabled = !running }
    }

    private func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        logView.textStorage?.append(NSAttributedString(string: text.hasSuffix("\n") ? text : text + "\n"))
        logView.scrollToEndOfDocument(nil)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

@main
enum AutoDLMonitorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

private extension NSControl.StateValue {
    func hasFlag(_ value: NSControl.StateValue) -> Bool {
        self == value
    }
}
