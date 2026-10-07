import AppKit
import ApplicationServices
import AVFoundation
import Darwin

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        let heightDelta = drawingRect.height - textHeight
        if heightDelta > 0 {
            drawingRect.origin.y += heightDelta / 2
            drawingRect.size.height = textHeight
        }
        return drawingRect
    }
}

private final class DraggableEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class NonIntrinsicImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private final class VoiceOrbView: NSView {
    enum Mode { case recording, processing, success, settled }
    enum Mark { case voice, processing, success, cancelled, warning, access }

    private var mode: Mode = .recording
    private var mark: Mark = .voice
    private var accentColor = NSColor.systemRed
    private var targetLevel: CGFloat = 0.16
    private var displayedLevel: CGFloat = 0.16
    private var phase: CGFloat = 0
    private var timer: Timer?
    private var motionReduced = false
    private var responseIntensity: CGFloat = 1

    override var isOpaque: Bool { false }

    func start(mode: Mode, color: NSColor, mark: Mark) {
        self.mode = mode
        self.mark = mark
        accentColor = color
        phase = 0
        switch mode {
        case .processing: targetLevel = 0.48
        case .success: targetLevel = 0.54
        default: targetLevel = 0.16
        }
        timer?.invalidate()
        timer = nil
        if !motionReduced {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
                self?.tick()
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        } else {
            displayedLevel = targetLevel
        }
        needsDisplay = true
    }

    func setLevel(_ rawLevel: Float) {
        guard mode == .recording else { return }
        let normalized = CGFloat(max(0, min(1, rawLevel)))
        targetLevel = min(1, 0.08 + normalized * responseIntensity)
        if motionReduced {
            displayedLevel = targetLevel
            needsDisplay = true
        }
    }

    func configureMotion(reduced: Bool, responseIntensity: CGFloat = 1) {
        motionReduced = reduced
        self.responseIntensity = max(0.25, min(1.35, responseIntensity))
        start(mode: mode, color: accentColor, mark: mark)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        switch mode {
        case .processing:
            phase += 0.075
            targetLevel = 0.44 + (sin(phase * 1.8) + 1) * 0.10
        case .success:
            phase += 0.065
            targetLevel = 0.22 + max(0, 1 - phase / 1.45) * 0.34
            if phase >= 1.45 {
                displayedLevel = 0.22
                stop()
            }
        case .settled:
            phase += 0.035
            targetLevel = 0.2 + (sin(phase * 1.4) + 1) * 0.025
        case .recording:
            phase += 0.045
        }
        displayedLevel += (targetLevel - displayedLevel) * 0.15
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let breathing = mode == .success ? 0 : (sin(phase * 1.8) + 1) / 2
        let drawingScale = max(0.5, min(bounds.width, bounds.height) / 64)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.translateBy(x: center.x, y: center.y)
        context?.scaleBy(x: drawingScale, y: drawingScale)
        context?.translateBy(x: -center.x, y: -center.y)
        defer { context?.restoreGState() }

        let haloRadius = 27 + breathing * 1.8 + displayedLevel * 2
        accentColor.withAlphaComponent(0.08 + displayedLevel * 0.05).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - haloRadius,
            y: center.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        )).fill()

        let ringRadius = 22 + breathing * 1.2
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))
        ring.lineWidth = 1
        accentColor.withAlphaComponent(0.2).setStroke()
        ring.stroke()

        if mode == .processing {
            let orbitRadius: CGFloat = 28
            let orbit = NSBezierPath(ovalIn: NSRect(
                x: center.x - orbitRadius,
                y: center.y - orbitRadius,
                width: orbitRadius * 2,
                height: orbitRadius * 2
            ))
            orbit.lineWidth = 0.8
            accentColor.withAlphaComponent(0.16).setStroke()
            orbit.stroke()
            for index in 0..<3 {
                let angle = phase * 2.4 + CGFloat(index) * (2 * .pi / 3)
                let radius: CGFloat = index == 0 ? 2.2 : 1.4
                let beadCenter = NSPoint(
                    x: center.x + cos(angle) * orbitRadius,
                    y: center.y + sin(angle) * orbitRadius
                )
                accentColor.withAlphaComponent(index == 0 ? 0.9 : 0.45).setFill()
                NSBezierPath(ovalIn: NSRect(
                    x: beadCenter.x - radius,
                    y: beadCenter.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )).fill()
            }
        }

        if mode == .success {
            let progress = min(1, phase / 1.45)
            let pulseRadius = 22 + progress * 8
            let pulse = NSBezierPath(ovalIn: NSRect(
                x: center.x - pulseRadius,
                y: center.y - pulseRadius,
                width: pulseRadius * 2,
                height: pulseRadius * 2
            ))
            pulse.lineWidth = 1.4
            accentColor.withAlphaComponent(max(0, 0.34 * (1 - progress))).setStroke()
            pulse.stroke()
        }

        let blob = NSBezierPath()
        let pointCount = 48
        for index in 0..<pointCount {
            let angle = CGFloat(index) / CGFloat(pointCount) * 2 * .pi
            let texture = sin(angle * 3 + phase * 2.1) * 1.2
                + sin(angle * 5 - phase * 1.4) * 0.7
            let textureAmount: CGFloat
            switch mode {
            case .recording: textureAmount = displayedLevel
            case .processing: textureAmount = 0.22
            case .success: textureAmount = 0
            case .settled: textureAmount = 0.12
            }
            let radius = 15 + displayedLevel * 5.8 + texture * textureAmount
            let point = NSPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            index == 0 ? blob.move(to: point) : blob.line(to: point)
        }
        blob.close()
        let gradient = NSGradient(colors: [
            accentColor.withAlphaComponent(0.98),
            accentColor.blended(withFraction: 0.32, of: .white) ?? accentColor
        ])
        gradient?.draw(in: blob, angle: 78)
        drawMark(at: center)
    }

    private func drawMark(at center: NSPoint) {
        NSColor.white.withAlphaComponent(0.96).setStroke()
        NSColor.white.withAlphaComponent(0.96).setFill()
        switch mark {
        case .voice:
            let heights: [CGFloat] = [7, 15, 10]
            for (index, height) in heights.enumerated() {
                let rect = NSRect(
                    x: center.x - 6 + CGFloat(index) * 5,
                    y: center.y - height / 2,
                    width: 2.4,
                    height: height
                )
                NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
            }
        case .processing:
            let sparkle = NSBezierPath()
            sparkle.move(to: NSPoint(x: center.x, y: center.y - 7))
            sparkle.line(to: NSPoint(x: center.x, y: center.y + 7))
            sparkle.move(to: NSPoint(x: center.x - 7, y: center.y))
            sparkle.line(to: NSPoint(x: center.x + 7, y: center.y))
            sparkle.lineWidth = 1.8
            sparkle.lineCapStyle = .round
            sparkle.stroke()
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)).fill()
        case .success:
            let check = NSBezierPath()
            check.move(to: NSPoint(x: center.x - 7, y: center.y))
            check.line(to: NSPoint(x: center.x - 2, y: center.y - 5))
            check.line(to: NSPoint(x: center.x + 8, y: center.y + 6))
            check.lineWidth = 2.4
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        case .cancelled:
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: center.x - 5, y: center.y - 5))
            cross.line(to: NSPoint(x: center.x + 5, y: center.y + 5))
            cross.move(to: NSPoint(x: center.x + 5, y: center.y - 5))
            cross.line(to: NSPoint(x: center.x - 5, y: center.y + 5))
            cross.lineWidth = 2.2
            cross.lineCapStyle = .round
            cross.stroke()
        case .warning:
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: center.x, y: center.y - 6))
            mark.line(to: NSPoint(x: center.x, y: center.y + 3))
            mark.lineWidth = 2.3
            mark.lineCapStyle = .round
            mark.stroke()
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.4, y: center.y + 6, width: 2.8, height: 2.8)).fill()
        case .access:
            let command = NSBezierPath()
            command.appendRoundedRect(NSRect(x: center.x - 7, y: center.y - 7, width: 5, height: 5), xRadius: 2.5, yRadius: 2.5)
            command.appendRoundedRect(NSRect(x: center.x + 2, y: center.y - 7, width: 5, height: 5), xRadius: 2.5, yRadius: 2.5)
            command.appendRoundedRect(NSRect(x: center.x - 7, y: center.y + 2, width: 5, height: 5), xRadius: 2.5, yRadius: 2.5)
            command.appendRoundedRect(NSRect(x: center.x + 2, y: center.y + 2, width: 5, height: 5), xRadius: 2.5, yRadius: 2.5)
            command.fill()
        }
    }
}

private final class OrbThemeBackgroundView: NSView {
    var accentColor = NSColor.systemRed { didSet { needsDisplay = true } }
    var isCosmos = false { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isCosmos else { return }

        let center = NSPoint(
            x: bounds.midX - bounds.width * 0.12,
            y: bounds.midY + bounds.height * 0.16
        )
        let base = NSGradient(colorsAndLocations:
            (NSColor(srgbRed: 1.00, green: 0.985, blue: 0.95, alpha: 1), 0),
            (NSColor(srgbRed: 0.985, green: 0.91, blue: 0.88, alpha: 1), 0.56),
            (NSColor(srgbRed: 0.90, green: 0.88, blue: 0.98, alpha: 1), 1)
        )
        base?.draw(
            fromCenter: center,
            radius: 0,
            toCenter: NSPoint(x: bounds.midX, y: bounds.midY),
            radius: bounds.width * 0.72,
            options: []
        )

        let glow = NSGradient(colorsAndLocations:
            (accentColor.withAlphaComponent(0.16), 0),
            (accentColor.withAlphaComponent(0), 1)
        )
        glow?.draw(
            fromCenter: NSPoint(x: bounds.midX, y: bounds.midY + bounds.height * 0.06),
            radius: 0,
            toCenter: NSPoint(x: bounds.midX, y: bounds.midY),
            radius: bounds.width * 0.48,
            options: []
        )
    }
}

private final class OrbChromeView: NSView {
    var accentColor = NSColor.systemRed { didSet { needsDisplay = true } }
    var isCosmos = false { didSet { needsDisplay = true } }
    var increasedContrast = false { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2

        let outer = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.2, dy: 1.2))
        outer.lineWidth = increasedContrast ? 2 : 1.35
        (isCosmos
            ? NSColor.white.withAlphaComponent(increasedContrast ? 0.72 : 0.42)
            : NSColor.white.withAlphaComponent(increasedContrast ? 0.98 : 0.82)).setStroke()
        outer.stroke()

        let inner = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5))
        inner.lineWidth = 0.9
        accentColor.withAlphaComponent(increasedContrast ? 0.24 : 0.12).setStroke()
        inner.stroke()

        let highlight = NSBezierPath()
        highlight.appendArc(
            withCenter: center,
            radius: radius - 3,
            startAngle: 28,
            endAngle: 144
        )
        highlight.lineWidth = 1.8
        highlight.lineCapStyle = .round
        NSColor.white.withAlphaComponent(isCosmos ? 0.30 : 0.76).setStroke()
        highlight.stroke()

        let lowerShade = NSBezierPath()
        lowerShade.appendArc(
            withCenter: center,
            radius: radius - 3,
            startAngle: 206,
            endAngle: 330
        )
        lowerShade.lineWidth = 1.2
        lowerShade.lineCapStyle = .round
        (isCosmos
            ? NSColor.black.withAlphaComponent(0.44)
            : accentColor.withAlphaComponent(0.10)).setStroke()
        lowerShade.stroke()

        let glintCenter = NSPoint(
            x: bounds.minX + radius * 0.54,
            y: bounds.maxY - radius * 0.34
        )
        NSColor.white.withAlphaComponent(isCosmos ? 0.56 : 0.88).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: glintCenter.x - 1.5,
            y: glintCenter.y - 1.5,
            width: 3,
            height: 3
        )).fill()
    }
}

private enum OrbPreviewState: Int {
    case recording
    case processing
    case success
    case error
}

private enum OrbPreviewTheme: Int {
    case standard
    case cosmos
    case mascot
}

private enum OrbPreviewMaterial: Int {
    case milky
    case clear
    case matte
}

private enum OrbPreviewShape: Int {
    case circle
    case capsule
}

private final class OrbPreviewStage: NSView {
    private let shadowHalo = NSView()
    private let plate = NSView()
    private let themeBackground = OrbThemeBackgroundView()
    private let themeImage = NonIntrinsicImageView()
    private let material = NSVisualEffectView()
    private let veil = NSView()
    private let chrome = OrbChromeView()
    private let orb = VoiceOrbView()
    private let captionPill = NSView()
    private let caption = NSTextField(labelWithString: "00:12")
    private let messageShadowHalo = NSView()
    private let messageShell = NSVisualEffectView()
    private let messageTint = NSView()
    private let messageOrb = VoiceOrbView()
    private let messageTitle = NSTextField(labelWithString: "Не получилось")
    private let messageDetail = NSTextField(labelWithString: "Проверьте доступ к микрофону")
    private let messageBadge = NSTextField(labelWithString: "Доступ")
    private let contextTitle = NSTextField(labelWithString: "Так орбита выглядит поверх рабочего стола")

    private var previewState: OrbPreviewState = .recording
    private var previewTheme: OrbPreviewTheme = .standard
    private var previewMaterial: OrbPreviewMaterial = .milky
    private var previewShape: OrbPreviewShape = .circle
    private var diameter: CGFloat = 176
    private var colors: [OrbPreviewState: NSColor] = [
        .recording: NSColor(srgbRed: 0.98, green: 0.36, blue: 0.31, alpha: 1),
        .processing: NSColor(srgbRed: 0.52, green: 0.43, blue: 0.96, alpha: 1),
        .success: NSColor(srgbRed: 0.20, green: 0.68, blue: 0.48, alpha: 1),
        .error: NSColor(srgbRed: 0.94, green: 0.55, blue: 0.16, alpha: 1)
    ]
    private var motionReduced = false
    private var responseIntensity: CGFloat = 0.9
    private var darkBackdrop = true
    private var increasedContrast = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.backgroundColor = NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1).cgColor

        shadowHalo.wantsLayer = true
        shadowHalo.layer?.shadowRadius = 18
        shadowHalo.layer?.shadowOffset = NSSize(width: 0, height: -6)
        shadowHalo.layer?.shadowOpacity = 0.30

        plate.wantsLayer = true
        plate.layer?.masksToBounds = true
        plate.layer?.borderWidth = 1

        themeImage.imageScaling = .scaleAxesIndependently
        themeImage.wantsLayer = true

        material.blendingMode = .withinWindow
        material.state = .active

        veil.wantsLayer = true
        orb.wantsLayer = true

        captionPill.wantsLayer = true
        captionPill.layer?.borderWidth = 0.7

        caption.cell = VerticallyCenteredTextFieldCell(textCell: caption.stringValue)
        caption.alignment = .center
        caption.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

        messageShell.material = .popover
        messageShell.blendingMode = .withinWindow
        messageShell.state = .active
        messageShell.wantsLayer = true
        messageShell.layer?.cornerRadius = 42
        messageShell.layer?.masksToBounds = true
        messageShell.layer?.borderWidth = 1
        messageShell.isHidden = true

        messageShadowHalo.wantsLayer = true
        messageShadowHalo.layer?.cornerRadius = 42
        messageShadowHalo.layer?.shadowRadius = 18
        messageShadowHalo.layer?.shadowOffset = NSSize(width: 0, height: -5)
        messageShadowHalo.layer?.shadowOpacity = 0.28
        messageShadowHalo.isHidden = true

        messageTint.wantsLayer = true

        messageTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        messageTitle.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        messageDetail.font = .systemFont(ofSize: 11.5, weight: .medium)
        messageDetail.textColor = NSColor(calibratedWhite: 0.22, alpha: 0.68)

        messageBadge.cell = VerticallyCenteredTextFieldCell(textCell: messageBadge.stringValue)
        messageBadge.alignment = .center
        messageBadge.font = .systemFont(ofSize: 9, weight: .semibold)
        messageBadge.wantsLayer = true
        messageBadge.layer?.cornerRadius = 9
        messageBadge.layer?.masksToBounds = true

        contextTitle.alignment = .center
        contextTitle.font = .systemFont(ofSize: 12, weight: .medium)
        contextTitle.textColor = NSColor.white.withAlphaComponent(0.58)

        addSubview(shadowHalo)
        addSubview(plate)
        plate.addSubview(themeBackground)
        plate.addSubview(themeImage)
        plate.addSubview(material)
        plate.addSubview(veil)
        plate.addSubview(chrome)
        plate.addSubview(orb)
        plate.addSubview(captionPill)
        captionPill.addSubview(caption)
        addSubview(messageShadowHalo)
        addSubview(messageShell)
        messageShell.addSubview(messageTint)
        messageShell.addSubview(messageOrb)
        messageShell.addSubview(messageTitle)
        messageShell.addSubview(messageDetail)
        messageShell.addSubview(messageBadge)
        addSubview(contextTitle)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Интерактивный образец орбиты")
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let origin = NSPoint(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2 + 10
        )
        shadowHalo.frame = NSRect(origin: origin, size: NSSize(width: diameter, height: diameter))
        shadowHalo.layer?.cornerRadius = diameter / 2
        plate.frame = NSRect(origin: origin, size: NSSize(width: diameter, height: diameter))
        plate.layer?.cornerRadius = diameter / 2
        themeBackground.frame = plate.bounds
        themeImage.frame = plate.bounds
        material.frame = plate.bounds
        veil.frame = plate.bounds
        chrome.frame = plate.bounds
        orb.frame = plate.bounds.insetBy(dx: diameter * 0.19, dy: diameter * 0.19)
        orb.frame.origin.y += diameter * 0.065
        let pillWidth: CGFloat
        switch previewState {
        case .recording: pillWidth = diameter * 0.35
        case .processing: pillWidth = diameter * 0.44
        case .success: pillWidth = diameter * 0.40
        case .error: pillWidth = diameter * 0.40
        }
        captionPill.frame = NSRect(
            x: (diameter - pillWidth) / 2,
            y: diameter * 0.072,
            width: pillWidth,
            height: 24
        )
        captionPill.layer?.cornerRadius = 12
        let captionFontSize = max(10, diameter * 0.073)
        caption.font = previewState == .recording
            ? .monospacedDigitSystemFont(ofSize: captionFontSize, weight: .semibold)
            : .systemFont(ofSize: captionFontSize, weight: .semibold)
        caption.frame = captionPill.bounds.insetBy(dx: 5, dy: 0)

        let messageSize = NSSize(width: min(346, bounds.width - 44), height: 84)
        messageShell.frame = NSRect(
            x: bounds.midX - messageSize.width / 2,
            y: bounds.midY - messageSize.height / 2 + 10,
            width: messageSize.width,
            height: messageSize.height
        )
        messageShadowHalo.frame = messageShell.frame
        messageShadowHalo.layer?.cornerRadius = messageSize.height / 2
        messageTint.frame = messageShell.bounds
        messageOrb.frame = NSRect(x: 10, y: 10, width: 64, height: 64)
        messageTitle.frame = NSRect(x: 82, y: 43, width: 154, height: 20)
        messageDetail.frame = NSRect(x: 82, y: 23, width: messageSize.width - 100, height: 17)
        messageBadge.frame = NSRect(x: messageSize.width - 76, y: 53, width: 62, height: 18)
        contextTitle.frame = NSRect(x: 20, y: 22, width: bounds.width - 40, height: 18)
    }

    func setState(_ state: OrbPreviewState) {
        previewState = state
        refreshState()
    }

    func setShape(_ shape: OrbPreviewShape) {
        previewShape = shape
        refreshState()
    }

    func setTheme(_ theme: OrbPreviewTheme) {
        previewTheme = theme
        refreshAppearance()
    }

    func setMaterial(_ style: OrbPreviewMaterial) {
        previewMaterial = style
        refreshAppearance()
    }

    func setDarkBackdrop(_ isDark: Bool) {
        darkBackdrop = isDark
        layer?.backgroundColor = (isDark
            ? NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1)).cgColor
        contextTitle.textColor = isDark
            ? NSColor.white.withAlphaComponent(0.58)
            : NSColor.black.withAlphaComponent(0.48)
        shadowHalo.layer?.shadowColor = (isDark ? NSColor.black : NSColor.gray).cgColor
        messageShadowHalo.layer?.shadowColor = (isDark ? NSColor.black : NSColor.gray).cgColor
    }

    func setIncreasedContrast(_ enabled: Bool) {
        increasedContrast = enabled
        chrome.increasedContrast = enabled
        refreshAppearance()
    }

    func setDiameter(_ value: CGFloat) {
        diameter = max(140, min(205, value))
        needsLayout = true
    }

    func setMotionReduced(_ reduced: Bool) {
        motionReduced = reduced
        refreshState()
    }

    func setResponseIntensity(_ value: CGFloat) {
        responseIntensity = value
        orb.configureMotion(reduced: motionReduced, responseIntensity: value)
    }

    func setColor(_ color: NSColor, for state: OrbPreviewState) {
        colors[state] = color
        if state == previewState { refreshState() }
    }

    func color(for state: OrbPreviewState) -> NSColor {
        colors[state] ?? .systemRed
    }

    func simulateAudioLevel(_ level: Float) {
        orb.setLevel(level)
        messageOrb.setLevel(level)
    }

    private func refreshAppearance() {
        let isCosmos = previewTheme == .cosmos
        let isMascot = previewTheme == .mascot
        themeBackground.isCosmos = isCosmos
        chrome.isCosmos = isCosmos
        themeImage.isHidden = previewTheme == .standard
        if isCosmos {
            themeImage.image = loadThemeImage(named: "cosmos-orb-512")
            plate.layer?.backgroundColor = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.12, alpha: 1).cgColor
            plate.layer?.borderColor = NSColor.white.withAlphaComponent(increasedContrast ? 0.70 : 0.38).cgColor
            caption.textColor = NSColor.white.withAlphaComponent(increasedContrast ? 1 : 0.90)
            shadowHalo.layer?.backgroundColor = NSColor(srgbRed: 0.04, green: 0.03, blue: 0.12, alpha: 0.84).cgColor
        } else if isMascot {
            themeImage.image = loadThemeImage(named: "mascot-orb-512")
            plate.layer?.backgroundColor = NSColor(srgbRed: 0.94, green: 0.88, blue: 0.96, alpha: 1).cgColor
            plate.layer?.borderColor = NSColor.white.withAlphaComponent(0.96).cgColor
            caption.textColor = NSColor(calibratedWhite: 0.12, alpha: increasedContrast ? 0.96 : 0.80)
            shadowHalo.layer?.backgroundColor = NSColor(srgbRed: 0.95, green: 0.84, blue: 0.94, alpha: 0.88).cgColor
        } else {
            themeImage.image = nil
            plate.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1).cgColor
            plate.layer?.borderColor = NSColor.white.withAlphaComponent(0.94).cgColor
            caption.textColor = NSColor(calibratedWhite: 0.12, alpha: increasedContrast ? 0.94 : 0.76)
            shadowHalo.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.86).cgColor
        }

        switch previewMaterial {
        case .milky:
            material.isHidden = false
            material.material = .popover
            material.alphaValue = isCosmos ? 0.28 : (isMascot ? 0.14 : 0.62)
            veil.layer?.backgroundColor = (isCosmos
                ? NSColor.black.withAlphaComponent(increasedContrast ? 0.34 : 0.20)
                : NSColor.white.withAlphaComponent(increasedContrast ? 0.42 : (isMascot ? 0.08 : 0.24))).cgColor
        case .clear:
            material.isHidden = false
            material.material = .sidebar
            material.alphaValue = isCosmos ? 0.10 : (isMascot ? 0.05 : 0.20)
            veil.layer?.backgroundColor = (isCosmos
                ? NSColor.black.withAlphaComponent(increasedContrast ? 0.26 : 0.12)
                : NSColor.white.withAlphaComponent(increasedContrast ? 0.28 : 0.10)).cgColor
        case .matte:
            material.isHidden = true
            veil.layer?.backgroundColor = (isCosmos
                ? NSColor(srgbRed: 0.05, green: 0.04, blue: 0.16, alpha: 0.50)
                : NSColor(srgbRed: 1, green: 0.96, blue: 0.90, alpha: 0.72)).cgColor
        }
        messageShadowHalo.layer?.backgroundColor = NSColor(
            srgbRed: 0.98,
            green: 0.89,
            blue: 0.75,
            alpha: 0.80
        ).cgColor
        messageShell.layer?.borderColor = NSColor.white.withAlphaComponent(
            increasedContrast ? 0.96 : 0.74
        ).cgColor
        messageDetail.textColor = NSColor(calibratedWhite: 0.18, alpha: increasedContrast ? 0.86 : 0.68)
        refreshState()
    }

    private func refreshState() {
        let accent = color(for: previewState)
        themeBackground.accentColor = accent
        chrome.accentColor = accent
        captionPill.layer?.backgroundColor = (previewTheme == .cosmos
            ? NSColor.black.withAlphaComponent(increasedContrast ? 0.54 : 0.32)
            : NSColor.white.withAlphaComponent(increasedContrast ? 0.86 : 0.58)).cgColor
        captionPill.layer?.borderColor = (previewTheme == .cosmos
            ? NSColor.white.withAlphaComponent(increasedContrast ? 0.46 : 0.20)
            : accent.withAlphaComponent(increasedContrast ? 0.24 : 0.12)).cgColor
        messageBadge.textColor = accent
        messageBadge.layer?.backgroundColor = accent.withAlphaComponent(increasedContrast ? 0.20 : 0.12).cgColor
        orb.configureMotion(reduced: motionReduced, responseIntensity: responseIntensity)
        let showsMessage = previewState == .error || previewShape == .capsule
        plate.isHidden = showsMessage
        shadowHalo.isHidden = showsMessage
        messageShadowHalo.isHidden = !showsMessage
        messageShell.isHidden = !showsMessage
        switch previewState {
        case .recording:
            caption.stringValue = "00:12"
            orb.start(mode: .recording, color: accent, mark: .voice)
            orb.setLevel(0.62)
            if showsMessage {
                configureMessage(
                    title: "Слушаю",
                    detail: "⌘ завершить  ·  Esc отменить",
                    badge: "Запись",
                    color: accent,
                    mark: .voice
                )
                messageOrb.setLevel(0.62)
            }
        case .processing:
            caption.stringValue = "Пишу…"
            orb.start(mode: .processing, color: accent, mark: .processing)
            if showsMessage {
                configureMessage(
                    title: "Пишу…",
                    detail: "Превращаю речь в текст",
                    badge: "Текст",
                    color: accent,
                    mark: .processing
                )
            }
        case .success:
            caption.stringValue = "Готово"
            orb.start(mode: .success, color: accent, mark: .success)
            if showsMessage {
                configureMessage(
                    title: "Готово",
                    detail: "Текст готов к вставке",
                    badge: "Готово",
                    color: accent,
                    mark: .success
                )
            }
        case .error:
            configureMessage(
                title: "Не получилось",
                detail: "Проверьте доступ к микрофону",
                badge: "Доступ",
                color: accent,
                mark: .warning
            )
        }
        contextTitle.stringValue = "Так выбранная форма выглядит поверх рабочего стола"
        needsLayout = true
        setAccessibilityValue(accessibilitySummary())
    }

    private func accessibilitySummary() -> String {
        let state: String
        switch previewState {
        case .recording: state = "Запись"
        case .processing: state = "Пишу текст"
        case .success: state = "Готово"
        case .error: state = "Ошибка, требуется доступ к микрофону"
        }
        let theme: String
        switch previewTheme {
        case .standard: theme = "стандартная тема"
        case .cosmos: theme = "тема Космос"
        case .mascot: theme = "тема Маскот"
        }
        let usesCapsule = previewState == .error || previewShape == .capsule
        let shape = usesCapsule ? "капсула" : "орбита"
        return "\(state), \(shape), \(theme)"
    }

    private func configureMessage(
        title: String,
        detail: String,
        badge: String,
        color: NSColor,
        mark: VoiceOrbView.Mark
    ) {
        messageTitle.stringValue = title
        messageDetail.stringValue = detail
        messageBadge.stringValue = badge
        messageBadge.textColor = color
        messageBadge.layer?.backgroundColor = color.withAlphaComponent(
            increasedContrast ? 0.20 : 0.12
        ).cgColor
        messageTint.layer?.backgroundColor = (mark == .warning
            ? NSColor(srgbRed: 1, green: 0.94, blue: 0.84, alpha: increasedContrast ? 0.70 : 0.48)
            : NSColor(srgbRed: 1, green: 0.91, blue: 0.88, alpha: increasedContrast ? 0.70 : 0.46)).cgColor
        messageOrb.configureMotion(reduced: motionReduced, responseIntensity: responseIntensity)
        let mode: VoiceOrbView.Mode
        switch mark {
        case .voice: mode = .recording
        case .processing: mode = .processing
        case .success: mode = .success
        case .cancelled, .warning, .access: mode = .settled
        }
        messageOrb.start(mode: mode, color: color, mark: mark)
    }

    private func loadThemeImage(named name: String) -> NSImage? {
        if let bundled = Bundle.main.image(forResource: NSImage.Name(name)) { return bundled }
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/Themes/\(name).png").path
        return NSImage(contentsOfFile: path)
    }
}

private final class OrbDesignPreviewWindowController: NSWindowController, NSWindowDelegate {
    private let persistsChanges: Bool
    private let onSettingsChanged: (() -> Void)?
    private let stage = OrbPreviewStage()
    private let stateControl = NSSegmentedControl(
        labels: ["Слушаю", "Пишу…", "Готово", "Ошибка"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let shapeControl = NSSegmentedControl(
        labels: ["Орбита", "Капсула"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let themeControl = NSSegmentedControl(
        labels: ["Стандартная", "Космос", "Маскот"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let materialControl = NSSegmentedControl(
        labels: ["Молочное", "Чистое", "Матовое"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let backdropControl = NSSegmentedControl(
        labels: ["Тёмный", "Светлый"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let sizeSlider = NSSlider(value: 0.55, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let intensitySlider = NSSlider(value: 0.72, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let sizeValue = NSTextField(labelWithString: "104 pt")
    private let colorWell = NSColorWell()
    private let colorCodeField = NSTextField()
    private let customColorButton = NSButton()
    private let applyColorButton = NSButton()
    private let defaultColorsButton = NSButton()
    private var presetColorButtons: [NSButton] = []
    private var colorControlsHeightConstraint: NSLayoutConstraint?
    private var customColorExpanded = false
    private var defaultColorsExpanded = false
    private let reduceMotion = NSButton(checkboxWithTitle: "Уменьшить движение", target: nil, action: nil)
    private let increaseContrast = NSButton(checkboxWithTitle: "Повысить контраст", target: nil, action: nil)
    private let presetColors: [OrbPreviewState: [NSColor]] = [
        .recording: [
            NSColor(srgbRed: 0.98, green: 0.36, blue: 0.31, alpha: 1),
            NSColor(srgbRed: 0.91, green: 0.31, blue: 0.40, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.48, blue: 0.27, alpha: 1)
        ],
        .processing: [
            NSColor(srgbRed: 0.52, green: 0.43, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.31, green: 0.51, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.69, green: 0.35, blue: 0.89, alpha: 1)
        ],
        .success: [
            NSColor(srgbRed: 0.20, green: 0.68, blue: 0.48, alpha: 1),
            NSColor(srgbRed: 0.13, green: 0.65, blue: 0.63, alpha: 1),
            NSColor(srgbRed: 0.39, green: 0.72, blue: 0.31, alpha: 1)
        ],
        .error: [
            NSColor(srgbRed: 0.94, green: 0.55, blue: 0.16, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.64, blue: 0.15, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.42, blue: 0.38, alpha: 1)
        ]
    ]
    private var levelTimer: Timer?
    private var phase: CGFloat = 0

    init(persistsChanges: Bool = false, onSettingsChanged: (() -> Void)? = nil) {
        self.persistsChanges = persistsChanges
        self.onSettingsChanged = onSettingsChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = persistsChanges ? "Sayo — настройки HUD" : "Sayo — дизайн орбиты"
        window.minSize = NSSize(width: 860, height: 680)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildInterface()
        resetControls(loadSavedValues: persistsChanges)
        window.initialFirstResponder = stateControl
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.colorWell.deactivate()
            NSColorPanel.shared.orderOut(nil)
            self.window?.makeFirstResponder(self.stateControl)
        }
        startLevelSimulation()
    }

    required init?(coder: NSCoder) { nil }

    deinit { levelTimer?.invalidate() }

    func windowWillClose(_ notification: Notification) {
        if persistsChanges {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        stage.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stage)

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)

        let heading = NSTextField(labelWithString: "Орбита")
        heading.font = .systemFont(ofSize: 26, weight: .bold)
        controls.addArrangedSubview(heading)

        let introText = persistsChanges
            ? "Настройте рабочий HUD. Форма, тема, материал, цвета, размер и движение сохраняются автоматически."
            : "Настройте характер HUD и проверьте, как состояния читаются на разных слоях. Это отдельный preview: изменения не сохраняются."
        let intro = NSTextField(wrappingLabelWithString: introText)
        intro.textColor = .secondaryLabelColor
        controls.addArrangedSubview(intro)
        intro.widthAnchor.constraint(equalToConstant: 350).isActive = true

        controls.addArrangedSubview(sectionLabel("Состояние"))
        configure(stateControl, action: #selector(stateChanged))
        stateControl.setAccessibilityLabel("Состояние орбиты")
        controls.addArrangedSubview(stateControl)

        controls.addArrangedSubview(sectionLabel("Форма"))
        configure(shapeControl, action: #selector(shapeChanged))
        shapeControl.setAccessibilityLabel("Форма HUD")
        controls.addArrangedSubview(shapeControl)

        controls.addArrangedSubview(sectionLabel("Тема"))
        configure(themeControl, action: #selector(themeChanged))
        themeControl.setAccessibilityLabel("Тема орбиты")
        controls.addArrangedSubview(themeControl)

        controls.addArrangedSubview(sectionLabel("Материал"))
        configure(materialControl, action: #selector(materialChanged))
        materialControl.setAccessibilityLabel("Материал орбиты")
        controls.addArrangedSubview(materialControl)

        controls.addArrangedSubview(sectionLabel("Фон проверки"))
        configure(backdropControl, action: #selector(backdropChanged))
        backdropControl.setAccessibilityLabel("Фон проверки контраста")
        controls.addArrangedSubview(backdropControl)

        controls.addArrangedSubview(sectionLabel("Цвет состояния"))
        controls.addArrangedSubview(makeColorControls())

        controls.addArrangedSubview(sliderRow(label: "Размер", slider: sizeSlider, value: sizeValue, action: #selector(sizeChanged)))
        controls.addArrangedSubview(sliderRow(label: "Реакция на голос", slider: intensitySlider, value: nil, action: #selector(intensityChanged)))

        reduceMotion.target = self
        reduceMotion.action = #selector(reduceMotionChanged)
        controls.addArrangedSubview(reduceMotion)

        increaseContrast.target = self
        increaseContrast.action = #selector(increaseContrastChanged)
        controls.addArrangedSubview(increaseContrast)

        let resetTitle = persistsChanges ? "Вернуть стандартные настройки" : "Вернуть значения preview"
        let reset = NSButton(title: resetTitle, target: self, action: #selector(resetPreview))
        reset.bezelStyle = .rounded
        controls.addArrangedSubview(reset)

        let note = NSTextField(wrappingLabelWithString: "Темы «Космос» и «Маскот» подключены к Sayo. «Природа» остаётся следующим отдельным этапом.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        controls.addArrangedSubview(note)
        note.widthAnchor.constraint(equalToConstant: 350).isActive = true

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stage.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stage.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            stage.widthAnchor.constraint(equalToConstant: 430),
            controls.leadingAnchor.constraint(equalTo: stage.trailingAnchor, constant: 36),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            controls.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stateControl.widthAnchor.constraint(equalToConstant: 350),
            shapeControl.widthAnchor.constraint(equalToConstant: 350),
            themeControl.widthAnchor.constraint(equalToConstant: 350),
            materialControl.widthAnchor.constraint(equalToConstant: 350),
            backdropControl.widthAnchor.constraint(equalToConstant: 350)
        ])
    }

    private func configure(_ control: NSSegmentedControl, action: Selector) {
        control.target = self
        control.action = action
        control.segmentStyle = .rounded
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeColorControls() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 32))
        container.translatesAutoresizingMaskIntoConstraints = false
        colorControlsHeightConstraint = container.heightAnchor.constraint(equalToConstant: 32)
        colorControlsHeightConstraint?.isActive = true
        container.widthAnchor.constraint(equalToConstant: 350).isActive = true

        customColorButton.title = "Свой цвет…  ▾"
        customColorButton.target = self
        customColorButton.action = #selector(toggleCustomColor)
        customColorButton.bezelStyle = .rounded
        customColorButton.alignment = .left
        customColorButton.frame = NSRect(x: 0, y: 2, width: 158, height: 30)
        customColorButton.autoresizingMask = [.minYMargin]
        customColorButton.setAccessibilityLabel("Показать настройку собственного цвета")
        container.addSubview(customColorButton)

        defaultColorsButton.title = "Цвет по умолчанию  ▾"
        defaultColorsButton.target = self
        defaultColorsButton.action = #selector(toggleDefaultColors)
        defaultColorsButton.bezelStyle = .rounded
        defaultColorsButton.alignment = .left
        defaultColorsButton.frame = NSRect(x: 170, y: 2, width: 180, height: 30)
        defaultColorsButton.autoresizingMask = [.minYMargin]
        defaultColorsButton.setAccessibilityLabel("Показать рекомендованные цвета по умолчанию")
        container.addSubview(defaultColorsButton)

        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.colorWellStyle = .minimal
        colorWell.frame = NSRect(x: 0, y: 2, width: 30, height: 30)
        colorWell.isHidden = true
        colorWell.setAccessibilityLabel("Текущий собственный цвет")
        container.addSubview(colorWell)

        colorCodeField.placeholderString = "HEX или RGB"
        colorCodeField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        colorCodeField.target = self
        colorCodeField.action = #selector(applyColorCode)
        colorCodeField.frame = NSRect(x: 38, y: 3, width: 248, height: 27)
        colorCodeField.isHidden = true
        colorCodeField.setAccessibilityLabel("Код собственного цвета HEX или RGB")
        colorCodeField.toolTip = "Например: #FA5C4F, rgb(250, 92, 79) или 250/92/79"
        container.addSubview(colorCodeField)

        applyColorButton.title = "ОК"
        applyColorButton.target = self
        applyColorButton.action = #selector(applyColorCode)
        applyColorButton.bezelStyle = .rounded
        applyColorButton.frame = NSRect(x: 294, y: 2, width: 56, height: 30)
        applyColorButton.isHidden = true
        applyColorButton.setAccessibilityLabel("Применить код цвета")
        container.addSubview(applyColorButton)

        presetColorButtons = (0..<3).map { index in
            let button = NSButton(title: "", target: self, action: #selector(presetColorChanged(_:)))
            button.tag = index
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.frame = NSRect(x: CGFloat(index) * 38, y: 2, width: 30, height: 30)
            button.isHidden = true
            button.setAccessibilityLabel("Рекомендованный цвет (index + 1)")
            container.addSubview(button)
            return button
        }
        return container
    }

    private func sliderRow(label: String, slider: NSSlider, value: NSTextField?, action: Selector) -> NSView {
        let row = NSView()
        let title = NSTextField(labelWithString: label)
        title.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = action
        row.addSubview(title)
        row.addSubview(slider)
        if let value {
            value.translatesAutoresizingMaskIntoConstraints = false
            value.alignment = .right
            value.textColor = .secondaryLabelColor
            row.addSubview(value)
            NSLayoutConstraint.activate([
                value.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                value.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                value.widthAnchor.constraint(equalToConstant: 52),
                slider.trailingAnchor.constraint(equalTo: value.leadingAnchor, constant: -8)
            ])
        } else {
            slider.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 350),
            row.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 132),
            slider.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func startLevelSimulation() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.08
            let wave = 0.42 + sin(self.phase) * 0.22 + sin(self.phase * 2.7) * 0.09
            self.stage.simulateAudioLevel(Float(max(0.08, min(0.92, wave))))
        }
        if let levelTimer { RunLoop.main.add(levelTimer, forMode: .common) }
    }

    private func resetControls(loadSavedValues: Bool = false) {
        let arguments = ProcessInfo.processInfo.arguments
        for state in [OrbPreviewState.recording, .processing, .success, .error] {
            if let baseColor = presetColors[state]?.first {
                let saved = loadSavedValues
                    ? UserDefaults.standard.string(forKey: colorDefaultsKey(for: state)).flatMap(parseColor)
                    : nil
                stage.setColor(saved ?? baseColor, for: state)
            }
        }
        if arguments.contains("--preview-state=processing") {
            stateControl.selectedSegment = 1
        } else if arguments.contains("--preview-state=success") {
            stateControl.selectedSegment = 2
        } else if arguments.contains("--preview-state=error") {
            stateControl.selectedSegment = 3
        } else {
            stateControl.selectedSegment = 0
        }
        if loadSavedValues {
            shapeControl.selectedSegment = UserDefaults.standard.string(forKey: "hudShape") == "capsule" ? 1 : 0
        } else {
            shapeControl.selectedSegment = arguments.contains("--preview-shape=capsule")
                || arguments.contains("--preview-hover") ? 1 : 0
        }
        let savedTheme = loadSavedValues ? UserDefaults.standard.string(forKey: "hudTheme") : nil
        if arguments.contains("--preview-theme=mascot")
            || savedTheme == "mascot"
            || (loadSavedValues && savedTheme == nil) {
            themeControl.selectedSegment = 2
        } else if arguments.contains("--preview-theme=cosmos") || savedTheme == "cosmos" {
            themeControl.selectedSegment = 1
        } else {
            themeControl.selectedSegment = 0
        }
        if loadSavedValues {
            switch UserDefaults.standard.string(forKey: "hudMaterial") {
            case "clear": materialControl.selectedSegment = 1
            case "matte": materialControl.selectedSegment = 2
            default: materialControl.selectedSegment = 0
            }
        } else {
            materialControl.selectedSegment = 0
        }
        backdropControl.selectedSegment = arguments.contains("--preview-backdrop=light") ? 1 : 0
        if loadSavedValues, UserDefaults.standard.object(forKey: "hudSize") != nil {
            sizeSlider.doubleValue = (UserDefaults.standard.double(forKey: "hudSize") - 80) / 48
        } else {
            sizeSlider.doubleValue = loadSavedValues
                ? 16 / 48
                : (arguments.contains("--preview-size=small") ? 0 : 0.55)
        }
        intensitySlider.doubleValue = loadSavedValues && UserDefaults.standard.object(forKey: "hudResponseIntensity") != nil
            ? UserDefaults.standard.double(forKey: "hudResponseIntensity")
            : 0.72
        reduceMotion.state = loadSavedValues
            ? (UserDefaults.standard.bool(forKey: "hudReduceMotion") ? .on : .off)
            : (arguments.contains("--preview-motion=reduced") ? .on : .off)
        increaseContrast.state = loadSavedValues
            ? (UserDefaults.standard.bool(forKey: "hudIncreaseContrast") ? .on : .off)
            : (arguments.contains("--preview-contrast=high") ? .on : .off)
        defaultColorsExpanded = arguments.contains("--preview-colors-expanded")
        customColorExpanded = arguments.contains("--preview-custom-color-expanded")
        if defaultColorsExpanded { customColorExpanded = false }
        updateColorDisclosure()
        stateChanged()
        shapeChanged()
        themeChanged()
        materialChanged()
        backdropChanged()
        sizeChanged()
        intensityChanged()
        reduceMotionChanged()
        increaseContrastChanged()
    }

    @objc private func stateChanged() {
        let state = OrbPreviewState(rawValue: stateControl.selectedSegment) ?? .recording
        stage.setState(state)
        updateColorControls()
    }

    @objc private func shapeChanged() {
        stage.setShape(OrbPreviewShape(rawValue: shapeControl.selectedSegment) ?? .circle)
        persistSettings()
    }

    @objc private func themeChanged() {
        stage.setTheme(OrbPreviewTheme(rawValue: themeControl.selectedSegment) ?? .standard)
        persistSettings()
    }

    @objc private func materialChanged() {
        stage.setMaterial(OrbPreviewMaterial(rawValue: materialControl.selectedSegment) ?? .milky)
        persistSettings()
    }

    @objc private func backdropChanged() {
        stage.setDarkBackdrop(backdropControl.selectedSegment == 0)
    }

    @objc private func sizeChanged() {
        let points = 80 + Int(round(sizeSlider.doubleValue * 48))
        sizeValue.stringValue = "\(points) pt"
        stage.setDiameter(140 + CGFloat(sizeSlider.doubleValue) * 65)
        persistSettings()
    }

    @objc private func intensityChanged() {
        stage.setResponseIntensity(0.35 + CGFloat(intensitySlider.doubleValue))
        persistSettings()
    }

    @objc private func colorChanged() {
        applySelectedColor(colorWell.color)
    }

    @objc private func presetColorChanged(_ sender: NSButton) {
        let state = OrbPreviewState(rawValue: stateControl.selectedSegment) ?? .recording
        guard let colors = presetColors[state], colors.indices.contains(sender.tag) else { return }
        applySelectedColor(colors[sender.tag])
    }

    @objc private func toggleCustomColor() {
        customColorExpanded.toggle()
        if customColorExpanded { defaultColorsExpanded = false }
        updateColorDisclosure()
    }

    @objc private func toggleDefaultColors() {
        defaultColorsExpanded.toggle()
        if defaultColorsExpanded { customColorExpanded = false }
        updateColorDisclosure()
    }

    private func updateColorDisclosure() {
        let expanded = customColorExpanded || defaultColorsExpanded
        colorControlsHeightConstraint?.constant = expanded ? 72 : 32
        customColorButton.title = customColorExpanded ? "Свой цвет…  ▴" : "Свой цвет…  ▾"
        defaultColorsButton.title = defaultColorsExpanded
            ? "Цвет по умолчанию  ▴"
            : "Цвет по умолчанию  ▾"
        customColorButton.setAccessibilityLabel(customColorExpanded
            ? "Скрыть настройку собственного цвета"
            : "Показать настройку собственного цвета")
        defaultColorsButton.setAccessibilityLabel(defaultColorsExpanded
            ? "Скрыть рекомендованные цвета по умолчанию"
            : "Показать рекомендованные цвета по умолчанию")
        colorWell.isHidden = !customColorExpanded
        colorCodeField.isHidden = !customColorExpanded
        applyColorButton.isHidden = !customColorExpanded
        presetColorButtons.forEach { $0.isHidden = !defaultColorsExpanded }
    }

    @objc private func applyColorCode() {
        guard let color = parseColor(colorCodeField.stringValue) else {
            colorCodeField.textColor = .systemRed
            colorCodeField.toolTip = "Используйте #RRGGBB, rgb(255, 128, 64) или 255/128/64"
            NSSound.beep()
            return
        }
        colorCodeField.textColor = .labelColor
        colorCodeField.toolTip = nil
        applySelectedColor(color)
    }

    private func applySelectedColor(_ color: NSColor) {
        let state = OrbPreviewState(rawValue: stateControl.selectedSegment) ?? .recording
        stage.setColor(color, for: state)
        updateColorControls()
        persistSettings()
    }

    private func updateColorControls() {
        let state = OrbPreviewState(rawValue: stateControl.selectedSegment) ?? .recording
        let selected = stage.color(for: state).usingColorSpace(.sRGB) ?? stage.color(for: state)
        let colors = presetColors[state] ?? []

        colorWell.color = selected
        colorWell.setAccessibilityValue(hexString(for: selected))
        colorCodeField.stringValue = hexString(for: selected)
        colorCodeField.textColor = .labelColor
        colorCodeField.toolTip = "Можно вставить HEX, rgb(...) или три RGB-числа"

        for (index, button) in presetColorButtons.enumerated() {
            guard colors.indices.contains(index) else { continue }
            let color = colors[index]
            button.layer?.backgroundColor = color.cgColor
            button.layer?.borderWidth = colorsAreClose(color, selected) ? 2 : 0
            button.layer?.borderColor = NSColor.controlAccentColor.cgColor
            button.toolTip = "Рекомендованный цвет \(index + 1) · \(hexString(for: color))"
            button.setAccessibilityValue(hexString(for: color))
        }
    }

    private func parseColor(_ input: String) -> NSColor? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("0x") { value.removeFirst(2) }
        if value.hasPrefix("#") { value.removeFirst() }

        if value.count == 3 || value.count == 6 {
            let expanded = value.count == 3
                ? value.map { "\($0)\($0)" }.joined()
                : value
            if let hex = UInt64(expanded, radix: 16) {
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            }
        }

        let components = value
            .lowercased()
            .replacingOccurrences(of: "rgb", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .components(separatedBy: CharacterSet(charactersIn: ",/; "))
            .filter { !$0.isEmpty }
            .compactMap(Double.init)
        guard components.count == 3 else { return nil }
        let divisor = components.allSatisfy { $0 >= 0 && $0 <= 1 } ? 1.0 : 255.0
        let normalized = components.map { $0 / divisor }
        guard normalized.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return nil }
        return NSColor(
            srgbRed: CGFloat(normalized[0]),
            green: CGFloat(normalized[1]),
            blue: CGFloat(normalized[2]),
            alpha: 1
        )
    }

    private func hexString(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func colorsAreClose(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = lhs.usingColorSpace(.sRGB) ?? lhs
        let right = rhs.usingColorSpace(.sRGB) ?? rhs
        return abs(left.redComponent - right.redComponent) < 0.006
            && abs(left.greenComponent - right.greenComponent) < 0.006
            && abs(left.blueComponent - right.blueComponent) < 0.006
    }

    @objc private func reduceMotionChanged() {
        stage.setMotionReduced(reduceMotion.state == .on)
        persistSettings()
    }

    @objc private func increaseContrastChanged() {
        stage.setIncreasedContrast(increaseContrast.state == .on)
        persistSettings()
    }

    @objc private func resetPreview() {
        if persistsChanges {
            let defaults = UserDefaults.standard
            [
                "hudShape", "hudMaterial", "hudSize", "hudResponseIntensity",
                "hudReduceMotion", "hudIncreaseContrast", "hudColorRecording",
                "hudColorProcessing", "hudColorSuccess", "hudColorError"
            ].forEach(defaults.removeObject(forKey:))
            defaults.set("mascot", forKey: "hudTheme")
        }
        resetControls(loadSavedValues: persistsChanges)
        persistSettings()
    }

    private func colorDefaultsKey(for state: OrbPreviewState) -> String {
        switch state {
        case .recording: return "hudColorRecording"
        case .processing: return "hudColorProcessing"
        case .success: return "hudColorSuccess"
        case .error: return "hudColorError"
        }
    }

    private func persistSettings() {
        guard persistsChanges else { return }
        let defaults = UserDefaults.standard
        defaults.set(shapeControl.selectedSegment == 1 ? "capsule" : "circle", forKey: "hudShape")
        let themes = ["standard", "cosmos", "mascot"]
        defaults.set(themes[max(0, min(2, themeControl.selectedSegment))], forKey: "hudTheme")
        let materials = ["milky", "clear", "matte"]
        defaults.set(materials[max(0, min(2, materialControl.selectedSegment))], forKey: "hudMaterial")
        defaults.set(80 + sizeSlider.doubleValue * 48, forKey: "hudSize")
        defaults.set(intensitySlider.doubleValue, forKey: "hudResponseIntensity")
        defaults.set(reduceMotion.state == .on, forKey: "hudReduceMotion")
        defaults.set(increaseContrast.state == .on, forKey: "hudIncreaseContrast")
        for state in [OrbPreviewState.recording, .processing, .success, .error] {
            defaults.set(hexString(for: stage.color(for: state)), forKey: colorDefaultsKey(for: state))
        }
        onSettingsChanged?()
    }
}

private final class RecordingHUD {
    private enum State { case hidden, recording, processing, success, message }
    private enum Shape: String { case circle, capsule }
    private enum Material: String { case milky, clear, matte }

    enum Theme: String, CaseIterable {
        case standard
        case cosmos
        case mascot

        var title: String {
            switch self {
            case .standard: return "Стандартная"
            case .cosmos: return "Космос"
            case .mascot: return "Маскот"
            }
        }
    }

    private var compactDiameter: CGFloat = 96
    private var compactSize: NSSize { NSSize(width: compactDiameter, height: compactDiameter) }
    private let expandedSize = NSSize(width: 316, height: 82)
    private var coral = NSColor(srgbRed: 0.98, green: 0.36, blue: 0.31, alpha: 1)
    private var lavender = NSColor(srgbRed: 0.52, green: 0.43, blue: 0.96, alpha: 1)
    private var mint = NSColor(srgbRed: 0.20, green: 0.68, blue: 0.48, alpha: 1)
    private var amber = NSColor(srgbRed: 0.94, green: 0.55, blue: 0.16, alpha: 1)
    private var preferredShape: Shape = .circle
    private var preferredMaterial: Material = .milky
    private var responseIntensity: CGFloat = 1.07
    private var motionReduced = false
    private var increasedContrast = false

    private let panel: NSPanel
    private let background = DraggableEffectView()
    private let themeBackground = OrbThemeBackgroundView()
    private let themeImage = NonIntrinsicImageView()
    private let tintView = NSView()
    private let chrome = OrbChromeView()
    private let orb = VoiceOrbView()
    private let captionPill = NSView()
    private let compactTime = NSTextField(labelWithString: "00:00")
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private var durationTimer: Timer?
    private var delayedHide: DispatchWorkItem?
    private var startedAt: Date?
    private var state: State = .hidden
    private var hasPositioned = false
    private var isResizing = false
    private var theme = Theme(
        rawValue: UserDefaults.standard.string(forKey: "hudTheme") ?? ""
    ) ?? .mascot
    private var orbLeadingConstraint: NSLayoutConstraint!
    private var orbCenterXConstraint: NSLayoutConstraint!
    private var orbCenterYConstraint: NSLayoutConstraint!
    private var orbWidthConstraint: NSLayoutConstraint!
    private var orbHeightConstraint: NSLayoutConstraint!
    private var captionBottomConstraint: NSLayoutConstraint!
    private var captionWidthConstraint: NSLayoutConstraint!
    private var captionHeightConstraint: NSLayoutConstraint!
    private var expandedContentConstraints: [NSLayoutConstraint] = []
    private var moveObserver: NSObjectProtocol?

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 96, height: 96)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system window shadow follows the rectangular NSPanel frame even when
        // the visible material is circular or pill-shaped. Keep it disabled so no
        // bright square corners leak around the selected HUD shape.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow

        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = compactSize.height / 2
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        background.toolTip = "Правый ⌘ — завершить · Esc — отменить · панель можно перетаскивать"
        panel.contentView = background

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(
            srgbRed: 1,
            green: 0.97,
            blue: 0.92,
            alpha: 0.44
        ).cgColor

        themeBackground.translatesAutoresizingMaskIntoConstraints = false
        themeImage.translatesAutoresizingMaskIntoConstraints = false
        themeImage.imageScaling = .scaleAxesIndependently
        themeImage.wantsLayer = true
        themeImage.setContentHuggingPriority(.defaultLow, for: .horizontal)
        themeImage.setContentHuggingPriority(.defaultLow, for: .vertical)
        themeImage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        themeImage.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        chrome.translatesAutoresizingMaskIntoConstraints = false

        captionPill.translatesAutoresizingMaskIntoConstraints = false
        captionPill.wantsLayer = true
        captionPill.layer?.cornerRadius = 11
        captionPill.layer?.borderWidth = 0.7

        orb.translatesAutoresizingMaskIntoConstraints = false

        compactTime.cell = VerticallyCenteredTextFieldCell(textCell: compactTime.stringValue)
        compactTime.translatesAutoresizingMaskIntoConstraints = false
        compactTime.alignment = .center
        compactTime.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        compactTime.textColor = NSColor(calibratedWhite: 0.18, alpha: 0.68)

        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 15.5, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        title.lineBreakMode = .byTruncatingTail

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .systemFont(ofSize: 11.5, weight: .medium)
        detail.textColor = NSColor(calibratedWhite: 0.24, alpha: 0.68)
        detail.lineBreakMode = .byTruncatingTail

        badge.cell = VerticallyCenteredTextFieldCell(textCell: badge.stringValue)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.masksToBounds = true

        background.addSubview(themeBackground)
        background.addSubview(themeImage)
        background.addSubview(tintView)
        background.addSubview(chrome)
        background.addSubview(orb)
        background.addSubview(captionPill)
        captionPill.addSubview(compactTime)
        background.addSubview(title)
        background.addSubview(detail)
        background.addSubview(badge)
        orbLeadingConstraint = orb.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14)
        orbCenterXConstraint = orb.centerXAnchor.constraint(equalTo: background.centerXAnchor)
        orbCenterYConstraint = orb.centerYAnchor.constraint(equalTo: background.centerYAnchor, constant: -8)
        orbWidthConstraint = orb.widthAnchor.constraint(equalToConstant: 64)
        orbHeightConstraint = orb.heightAnchor.constraint(equalToConstant: 64)
        captionBottomConstraint = captionPill.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8)
        captionWidthConstraint = captionPill.widthAnchor.constraint(equalToConstant: 58)
        captionHeightConstraint = captionPill.heightAnchor.constraint(equalToConstant: 22)
        orbCenterXConstraint.isActive = true
        NSLayoutConstraint.activate([
            themeBackground.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            themeBackground.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            themeBackground.topAnchor.constraint(equalTo: background.topAnchor),
            themeBackground.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            themeImage.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            themeImage.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            themeImage.topAnchor.constraint(equalTo: background.topAnchor),
            themeImage.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: background.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: background.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            orbCenterYConstraint,
            orbWidthConstraint,
            orbHeightConstraint,
            captionPill.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            captionBottomConstraint,
            captionWidthConstraint,
            captionHeightConstraint,
            compactTime.leadingAnchor.constraint(equalTo: captionPill.leadingAnchor, constant: 4),
            compactTime.trailingAnchor.constraint(equalTo: captionPill.trailingAnchor, constant: -4),
            compactTime.topAnchor.constraint(equalTo: captionPill.topAnchor),
            compactTime.bottomAnchor.constraint(equalTo: captionPill.bottomAnchor)
        ])
        expandedContentConstraints = [
            title.leadingAnchor.constraint(equalTo: orb.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
            title.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -10),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            detail.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            badge.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            badge.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            badge.widthAnchor.constraint(equalToConstant: 72),
            badge.heightAnchor.constraint(equalToConstant: 17)
        ]

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isResizing else { return }
            self.savePosition()
        }
        reloadPreferences()
        panel.setContentSize(compactSize)
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        orb.stop()
    }

    func showRecording() {
        stopTimers()
        state = .recording
        if preferredShape == .capsule {
            resize(to: expandedSize)
            configureExpanded()
            title.stringValue = "Слушаю"
            detail.stringValue = "⌘ завершить  ·  Esc отменить"
        } else {
            resize(to: compactSize)
            configureCompact()
        }
        startedAt = Date()
        compactTime.stringValue = "00:00"
        compactTime.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        setAppearance(color: coral, badgeText: preferredShape == .capsule ? "Запись" : "")
        configureOrbMotion()
        orb.start(mode: .recording, color: coral, mark: .voice)
        show()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        if let durationTimer { RunLoop.main.add(durationTimer, forMode: .common) }
    }

    func showProcessing() {
        stopTimers()
        state = .processing
        if preferredShape == .capsule {
            resize(to: expandedSize)
            configureExpanded()
            title.stringValue = "Пишу…"
            detail.stringValue = "Превращаю речь в текст"
        } else {
            resize(to: compactSize)
            configureCompact()
        }
        compactTime.stringValue = "Пишу…"
        compactTime.font = .systemFont(ofSize: 9.5, weight: .semibold)
        background.toolTip = "Преобразую речь в текст"
        setAppearance(color: lavender, badgeText: preferredShape == .capsule ? "Текст" : "")
        configureOrbMotion()
        orb.start(mode: .processing, color: lavender, mark: .processing)
        show()
    }

    func showSuccess(autoPasted: Bool) {
        stopTimers()
        state = .success
        if preferredShape == .capsule {
            resize(to: expandedSize)
            configureExpanded()
            title.stringValue = "Готово"
            detail.stringValue = autoPasted ? "Текст вставлен" : "Текст скопирован"
        } else {
            resize(to: compactSize)
            configureCompact()
        }
        compactTime.stringValue = "Готово"
        compactTime.font = .systemFont(ofSize: 9.5, weight: .semibold)
        background.toolTip = autoPasted ? "Текст вставлен" : "Текст скопирован"
        setAppearance(color: mint, badgeText: preferredShape == .capsule ? "Готово" : "")
        configureOrbMotion()
        orb.start(mode: .success, color: mint, mark: .success)
        show()
        hide(after: 1.25)
    }

    func showCancelled() {
        stopTimers()
        state = .success
        if preferredShape == .capsule {
            resize(to: expandedSize)
            configureExpanded()
            title.stringValue = "Отмена"
            detail.stringValue = "Запись удалена"
        } else {
            resize(to: compactSize)
            configureCompact()
        }
        compactTime.stringValue = "Отмена"
        compactTime.font = .systemFont(ofSize: 9.5, weight: .semibold)
        background.toolTip = "Запись отменена, аудио удалено"
        let neutral = NSColor(srgbRed: 0.46, green: 0.48, blue: 0.52, alpha: 1)
        setAppearance(color: neutral, badgeText: preferredShape == .capsule ? "Отмена" : "")
        configureOrbMotion()
        orb.start(mode: .settled, color: neutral, mark: .cancelled)
        show()
        hide(after: 1.0)
    }

    func showPermissionNeeded() {
        stopTimers()
        state = .message
        resize(to: NSSize(width: 352, height: 82))
        configureExpanded()
        setAppearance(color: amber, badgeText: "Доступ")
        title.stringValue = "Разрешите правый ⌘"
        detail.stringValue = "Подхвачу разрешение без перезапуска"
        configureOrbMotion()
        orb.start(mode: .settled, color: amber, mark: .access)
        show()
        hide(after: 4.5)
    }

    func showError(_ message: String) {
        stopTimers()
        state = .message
        resize(to: NSSize(width: 352, height: 82))
        configureExpanded()
        setAppearance(color: amber, badgeText: "Ошибка")
        title.stringValue = "Не получилось"
        detail.stringValue = message
        configureOrbMotion()
        orb.start(mode: .settled, color: amber, mark: .warning)
        show()
        hide(after: 4.0)
    }

    func updateAudioLevel(_ level: Float) {
        orb.setLevel(level)
    }

    func setTheme(_ theme: Theme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "hudTheme")
        refreshTheme(compact: state != .message)
    }

    func selectedTheme() -> Theme { theme }

    func reloadPreferences() {
        let defaults = UserDefaults.standard
        preferredShape = Shape(rawValue: defaults.string(forKey: "hudShape") ?? "") ?? .circle
        preferredMaterial = Material(rawValue: defaults.string(forKey: "hudMaterial") ?? "") ?? .milky
        if defaults.object(forKey: "hudSize") != nil {
            compactDiameter = CGFloat(max(80, min(128, defaults.double(forKey: "hudSize"))))
        } else {
            compactDiameter = 96
        }
        responseIntensity = defaults.object(forKey: "hudResponseIntensity") != nil
            ? 0.35 + CGFloat(defaults.double(forKey: "hudResponseIntensity"))
            : 1.07
        motionReduced = defaults.bool(forKey: "hudReduceMotion")
        increasedContrast = defaults.bool(forKey: "hudIncreaseContrast")
        theme = Theme(rawValue: defaults.string(forKey: "hudTheme") ?? "") ?? .mascot
        coral = storedColor(key: "hudColorRecording", fallback: NSColor(srgbRed: 0.98, green: 0.36, blue: 0.31, alpha: 1))
        lavender = storedColor(key: "hudColorProcessing", fallback: NSColor(srgbRed: 0.52, green: 0.43, blue: 0.96, alpha: 1))
        mint = storedColor(key: "hudColorSuccess", fallback: NSColor(srgbRed: 0.20, green: 0.68, blue: 0.48, alpha: 1))
        amber = storedColor(key: "hudColorError", fallback: NSColor(srgbRed: 0.94, green: 0.55, blue: 0.16, alpha: 1))
        chrome.increasedContrast = increasedContrast
        if state != .hidden { configureOrbMotion() }
        if state == .hidden {
            panel.setContentSize(compactSize)
        }
        refreshTheme(compact: state != .message && preferredShape == .circle)
    }

    func resetPosition() {
        let defaults = UserDefaults.standard
        ["hudCenterX", "hudCenterY", "hudOriginX", "hudOriginY"].forEach {
            defaults.removeObject(forKey: $0)
        }
        hasPositioned = false
        guard panel.isVisible else { return }
        restorePositionOrUseDefault()
        hasPositioned = true
    }

    func hide() {
        delayedHide?.cancel()
        delayedHide = nil
        stopTimers()
        orb.stop()
        startedAt = nil
        state = .hidden
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue < 0.05 else { return }
            self.panel.orderOut(nil)
        }
    }

    private func configureCompact() {
        NSLayoutConstraint.deactivate(expandedContentConstraints)
        orbLeadingConstraint.isActive = false
        orbCenterXConstraint.isActive = true
        title.isHidden = true
        detail.isHidden = true
        badge.isHidden = true
        captionPill.isHidden = false
        compactTime.isHidden = false
        let scale = compactDiameter / 96
        orbCenterYConstraint.constant = -8 * scale
        orbWidthConstraint.constant = 64 * scale
        orbHeightConstraint.constant = 64 * scale
        captionBottomConstraint.constant = -8 * scale
        captionWidthConstraint.constant = 58 * scale
        captionHeightConstraint.constant = 22 * scale
        captionPill.layer?.cornerRadius = 11 * scale
        compactTime.font = .monospacedDigitSystemFont(ofSize: max(8.5, 9.5 * scale), weight: .semibold)
        background.layer?.cornerRadius = compactSize.height / 2
        background.toolTip = "Правый ⌘ — завершить · Esc — отменить · круг можно перетаскивать"
        refreshTheme(compact: true)
    }

    private func configureExpanded() {
        orbCenterXConstraint.isActive = false
        orbLeadingConstraint.isActive = true
        NSLayoutConstraint.activate(expandedContentConstraints)
        title.isHidden = false
        detail.isHidden = false
        badge.isHidden = false
        captionPill.isHidden = true
        compactTime.isHidden = true
        orbCenterYConstraint.constant = -8
        orbWidthConstraint.constant = 64
        orbHeightConstraint.constant = 64
        background.layer?.cornerRadius = expandedSize.height / 2
        background.toolTip = "Панель можно перетаскивать"
        refreshTheme(compact: false)
    }

    private func updateDuration() {
        guard let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        compactTime.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func setAppearance(color: NSColor, badgeText: String) {
        badge.stringValue = badgeText
        badge.textColor = color
        badge.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        themeBackground.accentColor = color
        chrome.accentColor = color
    }

    private func refreshTheme(compact: Bool) {
        themeImage.isHidden = !compact || theme == .standard
        themeBackground.isHidden = !compact
        chrome.isHidden = !compact

        if !compact {
            orb.alphaValue = 1
            background.material = .popover
            background.alphaValue = 1
            background.layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
            tintView.layer?.backgroundColor = NSColor(
                srgbRed: 1,
                green: 0.94,
                blue: 0.88,
                alpha: 0.48
            ).cgColor
            applyVisualPreferences(compact: false)
            return
        }

        switch theme {
        case .standard:
            orb.alphaValue = 1
            themeBackground.isCosmos = false
            themeImage.image = nil
            chrome.isCosmos = false
            background.material = .popover
            background.layer?.borderColor = NSColor.white.withAlphaComponent(0.94).cgColor
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.24).cgColor
            compactTime.textColor = NSColor(calibratedWhite: 0.12, alpha: 0.78)
            captionPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.64).cgColor
            captionPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.78).cgColor
        case .cosmos:
            orb.alphaValue = 1
            themeBackground.isCosmos = true
            themeImage.image = loadThemeImage(named: "cosmos-orb-512")
            chrome.isCosmos = true
            background.material = .sidebar
            background.layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
            compactTime.textColor = NSColor.white.withAlphaComponent(0.94)
            captionPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
            captionPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        case .mascot:
            orb.alphaValue = 0.58
            themeBackground.isCosmos = false
            themeImage.image = loadThemeImage(named: "mascot-orb-512")
            chrome.isCosmos = false
            background.material = .popover
            background.layer?.borderColor = NSColor.white.withAlphaComponent(0.96).cgColor
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            compactTime.textColor = NSColor(calibratedWhite: 0.12, alpha: 0.82)
            captionPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.68).cgColor
            captionPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        }
        applyVisualPreferences(compact: true)
    }

    private func applyVisualPreferences(compact: Bool) {
        switch preferredMaterial {
        case .milky:
            if !compact { background.material = .popover }
        case .clear:
            background.material = .sidebar
            tintView.alphaValue = 0.72
        case .matte:
            background.material = .contentBackground
            tintView.alphaValue = 1
        }
        if preferredMaterial == .milky { tintView.alphaValue = 1 }
        if increasedContrast {
            background.layer?.borderColor = NSColor.white.withAlphaComponent(0.98).cgColor
            background.layer?.borderWidth = 1.5
            detail.textColor = NSColor(calibratedWhite: 0.16, alpha: 0.86)
        } else {
            background.layer?.borderWidth = 1
            detail.textColor = NSColor(calibratedWhite: 0.24, alpha: 0.68)
        }
    }

    private func configureOrbMotion() {
        orb.configureMotion(reduced: motionReduced, responseIntensity: responseIntensity)
    }

    private func storedColor(key: String, fallback: NSColor) -> NSColor {
        guard var value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return fallback
        }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let hex = UInt64(value, radix: 16) else { return fallback }
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private func loadThemeImage(named name: String) -> NSImage? {
        Bundle.main.image(forResource: NSImage.Name(name))
    }

    private func show() {
        delayedHide?.cancel()
        delayedHide = nil
        if !hasPositioned {
            restorePositionOrUseDefault()
            hasPositioned = true
        }
        let wasVisible = panel.isVisible
        if !wasVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
    }

    private func resize(to size: NSSize) {
        guard panel.frame.size != size else { return }
        let oldFrame = panel.frame
        let newFrame = NSRect(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        isResizing = true
        panel.setFrame(newFrame, display: true, animate: panel.isVisible)
        isResizing = false
    }

    private func hide(after delay: TimeInterval) {
        delayedHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        delayedHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func restorePositionOrUseDefault() {
        let defaults = UserDefaults.standard
        var savedCenter: NSPoint?
        if defaults.object(forKey: "hudCenterX") != nil,
           defaults.object(forKey: "hudCenterY") != nil {
            savedCenter = NSPoint(
                x: defaults.double(forKey: "hudCenterX"),
                y: defaults.double(forKey: "hudCenterY")
            )
        } else if defaults.object(forKey: "hudOriginX") != nil,
                  defaults.object(forKey: "hudOriginY") != nil {
            savedCenter = NSPoint(
                x: defaults.double(forKey: "hudOriginX") + 216,
                y: defaults.double(forKey: "hudOriginY") + 42
            )
        }

        if let savedCenter {
            let proposedFrame = NSRect(
                x: savedCenter.x - panel.frame.width / 2,
                y: savedCenter.y - panel.frame.height / 2,
                width: panel.frame.width,
                height: panel.frame.height
            )
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(proposedFrame) }) {
                let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                let clampedOrigin = NSPoint(
                    x: min(max(proposedFrame.minX, visible.minX), visible.maxX - proposedFrame.width),
                    y: min(max(proposedFrame.minY, visible.minY), visible.maxY - proposedFrame.height)
                )
                panel.setFrameOrigin(clampedOrigin)
                return
            }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 46
            ))
        }
    }

    private func savePosition() {
        UserDefaults.standard.set(panel.frame.midX, forKey: "hudCenterX")
        UserDefaults.standard.set(panel.frame.midY, forKey: "hudCenterY")
    }
}

private enum DictationError: LocalizedError {
    case microphoneDenied
    case noInputDevice
    case missingExecutable(String)
    case missingModel(String)
    case conversionFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Нет доступа к микрофону"
        case .noInputDevice:
            return "Микрофон не найден"
        case .missingExecutable(let name):
            return "Не найден \(name)"
        case .missingModel(let path):
            return "Не найдена модель: \(path)"
        case .conversionFailed(let message):
            return "Не удалось подготовить аудио: \(message)"
        case .transcriptionFailed(let message):
            return "Ошибка распознавания: \(message)"
        case .emptyTranscript:
            return "Речь не распознана"
        }
    }
}

private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

private enum RecognizerState {
    case loading
    case ready
    case recovering
    case fallback
}

private struct RecognitionPlan {
    var offsetMs = 0
    var durationMs = 0 // 0 means until the end of the recording
    var singleWindow = true
}

private final class DictationController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var modelPath: String {
        let defaults = UserDefaults.standard
        let configuredPath = defaults.string(forKey: "modelPath")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            configuredPath,
            "~/Library/Application Support/Sayo/Models/ggml-large-v2.bin",
            "~/Library/Application Support/superwhisper/ggml-large.bin"
        ]
        .compactMap { $0 }
        .map { NSString(string: $0).expandingTildeInPath }

        return candidates.first(where: FileManager.default.fileExists(atPath:))
            ?? NSString(
                string: "~/Library/Application Support/Sayo/Models/ggml-large-v2.bin"
            ).expandingTildeInPath
    }

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var sourceAudioURL: URL?
    private var recognizerServer: Process?
    // The headless check uses its own port so it never talks to the installed app's server.
    private let isHeadless = ProcessInfo.processInfo.arguments.contains("--transcribe")
    private let recognizerPort = ProcessInfo.processInfo.arguments.contains("--transcribe") ? 18081 : 18080
    private let recognizerLock = NSLock()
    private let transcriptionQueue = DispatchQueue(label: "ru.specit.Sayo.transcription", qos: .userInitiated)
    private var recognizerState: RecognizerState = .loading
    private var recognizerHealthTimer: Timer?
    private var permissionRecoveryTimer: Timer?
    private let hud = RecordingHUD()
    private var statusLineItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var themeMenu: NSMenu!
    private var autoPasteItem: NSMenuItem!
    private var retryRecoveryItem: NSMenuItem!
    private var discardRecoveryItem: NSMenuItem!
    private var hotkeyStatusItem: NSMenuItem!
    private var inputMonitoringStatusItem: NSMenuItem!
    private var microphoneStatusItem: NSMenuItem!
    private var serverStatusItem: NSMenuItem!
    private var transcriptHistory: [String] = []
    private var autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
    private var isRecording = false
    private var isTranscribing = false
    private var lastRightCommandDown = false
    private var recordingStartedAt: Date?
    private var designPreviewWindow: OrbDesignPreviewWindowController?
    private var hasRequestedInputMonitoring = false

    private let idleIcon = "waveform"
    private let recordingIcon = "record.circle.fill"
    private let workingIcon = "ellipsis.circle"
    private let recoveryDirectoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Sayo", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--preview-settings") {
            NSApplication.shared.setActivationPolicy(.regular)
            designPreviewWindow = OrbDesignPreviewWindowController()
            designPreviewWindow?.showWindow(nil)
            designPreviewWindow?.window?.center()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--transcribe"), arguments.indices.contains(index + 1) {
            runHeadlessTranscription(of: URL(fileURLWithPath: arguments[index + 1]))
            return
        }

        transcriptHistory = UserDefaults.standard.stringArray(forKey: "transcriptHistory") ?? []
        configureMenuBar()

        if let preview = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-hud=") }) {
            switch preview.replacingOccurrences(of: "--preview-hud=", with: "") {
            case "cycle": runHUDPreviewCycle()
            case "processing": hud.showProcessing()
            case "success": hud.showSuccess(autoPasted: true)
            case "permission": hud.showPermissionNeeded()
            default:
                hud.showRecording()
                hud.updateAudioLevel(0.74)
            }
            return
        }

        requestAccessibilityPermission()
        installRightCommandTap(showFailure: true)
        startPermissionRecovery()
        requestMicrophonePermission()
        warmUpRecognizerServer()
    }

    /// Runs the production recognition pipeline on an audio file and prints the transcript.
    /// Verifies recognition changes without the microphone, HUD or global hotkey.
    private func runHeadlessTranscription(of input: URL) {
        transcriptionQueue.async { [self] in
            var status: Int32 = 0
            do {
                let wavURL = try convertToWhisperWAV(input)
                defer { try? FileManager.default.removeItem(at: wavURL) }
                print(try transcribe(wavURL))
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                status = 1
            }
            stopRecognizerServer()
            exit(status)
        }
    }

    private func runHUDPreviewCycle() {
        hud.showRecording()
        hud.updateAudioLevel(0.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.hud.updateAudioLevel(0.78)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            self?.hud.updateAudioLevel(0.34)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.hud.showProcessing()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.hud.showSuccess(autoPasted: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.3) { [weak self] in
            self?.runHUDPreviewCycle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = nil
        recognizerHealthTimer?.invalidate()
        recognizerHealthTimer = nil
        stopRecordingWithoutTranscription()
        stopRecognizerServer()
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setStatus(icon: idleIcon, title: "Готово — нажмите правый ⌘")

        let menu = NSMenu()
        menu.delegate = self
        statusLineItem = NSMenuItem(title: "● Готово", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: "Начать диктовку",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        toggleMenuItem.image = menuSymbol("waveform")
        menu.addItem(toggleMenuItem)

        autoPasteItem = NSMenuItem(
            title: "Вставлять текст автоматически",
            action: #selector(toggleAutoPaste),
            keyEquivalent: ""
        )
        autoPasteItem.target = self
        autoPasteItem.state = autoPasteEnabled ? .on : .off
        autoPasteItem.image = menuSymbol("doc.on.clipboard")
        menu.addItem(autoPasteItem)

        let customizeHUD = NSMenuItem(
            title: "Настроить HUD…",
            action: #selector(openHUDSettings),
            keyEquivalent: ","
        )
        customizeHUD.target = self
        customizeHUD.image = menuSymbol("slider.horizontal.3")
        menu.addItem(customizeHUD)

        let themeRoot = NSMenuItem(title: "Тема орбиты", action: nil, keyEquivalent: "")
        themeRoot.image = menuSymbol("sparkles")
        themeMenu = NSMenu(title: "Тема орбиты")
        for theme in RecordingHUD.Theme.allCases {
            let item = NSMenuItem(
                title: theme.title,
                action: #selector(selectHUDTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            themeMenu.addItem(item)
        }
        themeRoot.submenu = themeMenu
        menu.addItem(themeRoot)

        let historyRoot = NSMenuItem(title: "Последние фразы", action: nil, keyEquivalent: "")
        historyRoot.image = menuSymbol("clock.arrow.circlepath")
        historyMenu = NSMenu(title: "Последние фразы")
        historyRoot.submenu = historyMenu
        menu.addItem(historyRoot)
        rebuildHistoryMenu()

        retryRecoveryItem = NSMenuItem(
            title: "Повторить сохранённую запись",
            action: #selector(retryFailedRecording),
            keyEquivalent: ""
        )
        retryRecoveryItem.target = self
        retryRecoveryItem.image = menuSymbol("arrow.clockwise.circle")
        menu.addItem(retryRecoveryItem)

        discardRecoveryItem = NSMenuItem(
            title: "Удалить сохранённые записи…",
            action: #selector(discardFailedRecordings),
            keyEquivalent: ""
        )
        discardRecoveryItem.target = self
        discardRecoveryItem.image = menuSymbol("trash")
        menu.addItem(discardRecoveryItem)
        menu.addItem(.separator())

        hotkeyStatusItem = NSMenuItem(title: "Правый ⌘: проверяю…", action: nil, keyEquivalent: "")
        hotkeyStatusItem.isEnabled = false
        hotkeyStatusItem.image = menuSymbol("command")
        menu.addItem(hotkeyStatusItem)

        inputMonitoringStatusItem = NSMenuItem(title: "Мониторинг ввода: проверяю…", action: nil, keyEquivalent: "")
        inputMonitoringStatusItem.isEnabled = false
        inputMonitoringStatusItem.image = menuSymbol("keyboard")
        menu.addItem(inputMonitoringStatusItem)

        microphoneStatusItem = NSMenuItem(title: "Микрофон: проверяю…", action: nil, keyEquivalent: "")
        microphoneStatusItem.isEnabled = false
        microphoneStatusItem.image = menuSymbol("mic")
        menu.addItem(microphoneStatusItem)

        serverStatusItem = NSMenuItem(title: "Whisper Large: загружается…", action: nil, keyEquivalent: "")
        serverStatusItem.isEnabled = false
        serverStatusItem.image = menuSymbol("bolt.horizontal.circle")
        menu.addItem(serverStatusItem)

        let permissions = NSMenuItem(
            title: "Разрешения и диагностика…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissions.target = self
        permissions.image = menuSymbol("gearshape")
        menu.addItem(permissions)

        let resetHUD = NSMenuItem(
            title: "Вернуть панель вниз экрана",
            action: #selector(resetHUDPosition),
            keyEquivalent: ""
        )
        resetHUD.target = self
        resetHUD.image = menuSymbol("rectangle.bottomthird.inset.filled")
        menu.addItem(resetHUD)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.image = menuSymbol("power")
        menu.addItem(quit)
        statusItem.menu = menu
        refreshMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
    }

    private func refreshMenuState() {
        guard toggleMenuItem != nil else { return }
        toggleMenuItem.title = isRecording
            ? "Завершить и распознать"
            : (isTranscribing ? "Распознаю…" : "Начать диктовку")
        toggleMenuItem.image = menuSymbol(isRecording ? "stop.circle.fill" : "waveform")
        toggleMenuItem.isEnabled = !isTranscribing

        let recoveryCount = recoverableRecordings().count
        retryRecoveryItem.title = recoveryCount > 1
            ? "Повторить сохранённую запись (\(recoveryCount))"
            : "Повторить сохранённую запись"
        retryRecoveryItem.isHidden = recoveryCount == 0
        retryRecoveryItem.isEnabled = recoveryCount > 0 && !isRecording && !isTranscribing
        discardRecoveryItem.isHidden = recoveryCount == 0
        discardRecoveryItem.isEnabled = recoveryCount > 0 && !isRecording && !isTranscribing

        let selectedTheme = hud.selectedTheme()
        themeMenu?.items.forEach { item in
            item.state = item.representedObject as? String == selectedTheme.rawValue ? .on : .off
        }

        let accessibilityReady = AXIsProcessTrusted()
        let inputMonitoringReady = CGPreflightListenEventAccess()
        let hotkeyReady = eventTap != nil && accessibilityReady
        if hotkeyReady {
            hotkeyStatusItem.title = "Правый ⌘: готов"
        } else if !accessibilityReady {
            hotkeyStatusItem.title = "Правый ⌘: нужен Универсальный доступ"
        } else if !inputMonitoringReady {
            hotkeyStatusItem.title = "Правый ⌘: нужен Мониторинг ввода"
        } else {
            hotkeyStatusItem.title = "Правый ⌘: восстанавливаю…"
        }
        if hotkeyReady {
            inputMonitoringStatusItem.title = "Мониторинг ввода: не требуется"
        } else {
            inputMonitoringStatusItem.title = inputMonitoringReady
                ? "Мониторинг ввода: резервный доступ есть"
                : "Мониторинг ввода: резервный доступ не выдан"
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatusItem.title = "Микрофон: доступ есть"
        case .notDetermined: microphoneStatusItem.title = "Микрофон: ожидает разрешения"
        default: microphoneStatusItem.title = "Микрофон: нужен доступ"
        }

        if !FileManager.default.fileExists(atPath: modelPath) {
            serverStatusItem.title = "Whisper Large: модель не найдена"
        } else {
            switch recognizerState {
            case .loading:
                serverStatusItem.title = "Whisper Large: загружается локально…"
            case .ready:
                serverStatusItem.title = "Whisper Large: Metal GPU готов"
            case .recovering:
                serverStatusItem.title = "Whisper Large: перезапускаю локально…"
            case .fallback:
                serverStatusItem.title = "Whisper Large: резервный запуск модели"
            }
        }
    }

    private func setStatus(icon: String, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = NSImage(
                systemSymbolName: icon,
                accessibilityDescription: title
            )
            self.statusItem.button?.contentTintColor = icon == self.recordingIcon ? .systemRed : nil
            self.statusItem.button?.toolTip = title
            if let statusLineItem = self.statusLineItem {
                let prefix: String
                if icon == self.recordingIcon { prefix = "● " }
                else if icon == self.workingIcon { prefix = "◌ " }
                else if icon == "exclamationmark.triangle" { prefix = "⚠︎ " }
                else { prefix = "● " }
                statusLineItem.title = prefix + title
            }
        }
    }

    @objc private func selectHUDTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = RecordingHUD.Theme(rawValue: rawValue) else { return }
        hud.setTheme(theme)
        refreshMenuState()
        hud.showSuccess(autoPasted: false)
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            break
        }
    }

    private func startPermissionRecovery() {
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let eventTap = self.eventTap, CFMachPortIsValid(eventTap) {
                return
            }
            self.eventTap = nil
            guard AXIsProcessTrusted() else {
                self.refreshMenuState()
                return
            }
            self.installRightCommandTap(showFailure: false)
            if self.eventTap == nil,
               !CGPreflightListenEventAccess(),
               !self.hasRequestedInputMonitoring {
                self.hasRequestedInputMonitoring = true
                _ = CGRequestListenEventAccess()
            }
        }
        if let permissionRecoveryTimer {
            RunLoop.main.add(permissionRecoveryTimer, forMode: .common)
        }
    }

    private func installRightCommandTap(showFailure: Bool) {
        guard eventTap == nil else { return }
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DictationController>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = controller.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown { return controller.handleKeyDown(event) }
            if type == .flagsChanged { return controller.handleFlagsChanged(event) }
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            setStatus(icon: "exclamationmark.triangle", title: "Правому ⌘ нужен Универсальный доступ")
            refreshMenuState()
            if showFailure { hud.showPermissionNeeded() }
            return
        }

        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        setStatus(icon: idleIcon, title: "Готово — нажмите правый ⌘")
        refreshMenuState()
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 54 is the hardware key code of the right Command key on Apple keyboards.
        guard event.getIntegerValueField(.keyboardEventKeycode) == 54 else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = event.flags.contains(.maskCommand)
        if isDown && !lastRightCommandDown {
            DispatchQueue.main.async { [weak self] in self?.toggleDictation() }
        }
        lastRightCommandDown = isDown

        // The right Command key is dedicated to dictation while the app is running.
        return nil
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Escape cancels the active recording without sending it for recognition.
        guard event.getIntegerValueField(.keyboardEventKeycode) == 53, isRecording else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in self?.cancelRecording() }
        return nil
    }

    @objc private func toggleFromMenu() {
        toggleDictation()
    }

    @objc private func toggleAutoPaste() {
        autoPasteEnabled.toggle()
        autoPasteItem.state = autoPasteEnabled ? .on : .off
        UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPaste")
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        setStatus(icon: idleIcon, title: "Фраза скопирована")
        NSSound(named: "Glass")?.play()
    }

    @objc private func clearHistory() {
        transcriptHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "transcriptHistory")
        rebuildHistoryMenu()
    }

    private func ensureRecoveryDirectory() throws {
        try FileManager.default.createDirectory(
            at: recoveryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func recoverableRecordings() -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: recoveryDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { url in
                url.pathExtension == "caf" && url != sourceAudioURL
            }
            .sorted { lhs, rhs in
                let leftDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rightDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }
    }

    @objc private func retryFailedRecording() {
        guard !isRecording, !isTranscribing,
              let sourceURL = recoverableRecordings().first else { return }
        beginTranscription(of: sourceURL, isRecovery: true)
    }

    @objc private func discardFailedRecordings() {
        let recordings = recoverableRecordings()
        guard !recordings.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = recordings.count == 1
            ? "Удалить сохранённую запись?"
            : "Удалить сохранённые записи (\(recordings.count))?"
        alert.informativeText = "После удаления повторить локальное распознавание будет нельзя."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        recordings.forEach { try? FileManager.default.removeItem(at: $0) }
        setStatus(icon: idleIcon, title: "Сохранённые записи удалены")
        refreshMenuState()
    }

    private func toggleDictation() {
        if isTranscribing { return }
        if isRecording {
            finishRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            showError(DictationError.microphoneDenied.localizedDescription)
            openPrivacySettings(anchor: "Privacy_Microphone")
            return
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            showError(DictationError.missingModel(modelPath).localizedDescription)
            return
        }

        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw DictationError.noInputDevice
            }

            try ensureRecoveryDirectory()
            let url = recoveryDirectoryURL
                .appendingPathComponent("dictation-\(UUID().uuidString).caf")
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            audioEngine = engine
            audioFile = file
            sourceAudioURL = url

            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                try? file.write(from: buffer)
                guard let samples = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                guard count > 0 else { return }
                var sum: Float = 0
                for index in stride(from: 0, to: count, by: 2) {
                    let sample = samples[index]
                    sum += sample * sample
                }
                let sampledCount = max(1, (count + 1) / 2)
                let rms = sqrt(sum / Float(sampledCount))
                let decibels = 20 * log10(max(rms, 0.000_01))
                let normalized = max(0, min(1, (decibels + 52) / 42))
                DispatchQueue.main.async {
                    self?.hud.updateAudioLevel(normalized)
                }
            }
            engine.prepare()
            try engine.start()

            isRecording = true
            recordingStartedAt = Date()
            setStatus(icon: recordingIcon, title: "Запись… правый ⌘ — готово, Esc — отмена")
            hud.showRecording()
            refreshMenuState()
            NSSound(named: "Tink")?.play()
        } catch {
            stopRecordingWithoutTranscription()
            showError(error.localizedDescription)
        }
    }

    private func finishRecordingAndTranscribe() {
        guard let sourceURL = sourceAudioURL else { return }
        let recordingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        stopAudioEngine()
        sourceAudioURL = nil
        recordingStartedAt = nil
        isRecording = false

        guard recordingDuration >= 0.45 else {
            try? FileManager.default.removeItem(at: sourceURL)
            setStatus(icon: idleIcon, title: "Запись слишком короткая")
            hud.showError("Скажите фразу чуть дольше")
            refreshMenuState()
            return
        }

        beginTranscription(of: sourceURL, isRecovery: false)
    }

    private func beginTranscription(of sourceURL: URL, isRecovery: Bool) {
        isTranscribing = true
        setStatus(
            icon: workingIcon,
            title: isRecovery ? "Повторяю локальное распознавание…" : "Распознаю речь…"
        )
        hud.showProcessing()
        refreshMenuState()
        NSSound(named: "Pop")?.play()

        transcriptionQueue.async { [weak self] in
            guard let self else { return }

            do {
                let wavURL = try self.convertToWhisperWAV(sourceURL)
                defer { try? FileManager.default.removeItem(at: wavURL) }
                let transcript = try self.transcribe(wavURL)
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.copyAndPaste(transcript)
                    try? FileManager.default.removeItem(at: sourceURL)
                    self.refreshMenuState()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.showError("\(error.localizedDescription). Запись сохранена — можно повторить из меню")
                }
            }
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        stopRecordingWithoutTranscription()
        hud.showCancelled()
        setStatus(icon: idleIcon, title: "Запись отменена")
        refreshMenuState()
        NSSound(named: "Funk")?.play()
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
    }

    private func stopRecordingWithoutTranscription() {
        stopAudioEngine()
        if let sourceAudioURL {
            try? FileManager.default.removeItem(at: sourceAudioURL)
        }
        sourceAudioURL = nil
        recordingStartedAt = nil
        isRecording = false
    }

    private func convertToWhisperWAV(_ input: URL) throws -> URL {
        guard let ffmpeg = locateExecutable(candidates: [
            "/usr/local/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg"
        ]) else {
            throw DictationError.missingExecutable("ffmpeg")
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("right-command-\(UUID().uuidString).wav")
        let result = runProcess(ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", input.path,
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            output.path
        ], timeout: 60)
        guard result.status == 0 else {
            throw DictationError.conversionFailed(result.stderr)
        }
        return output
    }

    private func transcribe(_ input: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw DictationError.missingModel(modelPath)
        }

        let plan = try recognitionPlan(for: input)
        if isHeadless {
            FileHandle.standardError.write(Data("plan: \(plan)\n".utf8))
        }

        if ensureRecognizerServerReady(maxWait: 20, stateWhileStarting: .recovering) {
            do {
                return try transcribeThroughServer(input, plan: plan)
            } catch {
                updateRecognizerState(.recovering)
                stopRecognizerServer()
                if ensureRecognizerServerReady(maxWait: 20, stateWhileStarting: .recovering),
                   let transcript = try? transcribeThroughServer(input, plan: plan) {
                    return transcript
                }
            }
        }

        updateRecognizerState(.fallback)
        return try transcribeThroughCLI(input, plan: plan)
    }

    /// Decides which part of the recording to recognize and how.
    ///
    /// Whisper reads audio in 30-second windows. Without timestamps every window is decoded
    /// on its own and whatever the model did not finish is silently dropped, so long
    /// recordings lose whole sentences. With timestamps the windows are stitched correctly,
    /// but the model invents text when a window starts or ends with long silence. So silence
    /// around the speech is skipped, speech that fits one window keeps the timestamp-free
    /// mode, and longer speech is decoded with timestamps.
    private func recognitionPlan(for wav: URL) throws -> RecognitionPlan {
        guard let file = try? AVAudioFile(forReading: wav),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else {
            throw DictationError.conversionFailed("WAV не читается")
        }

        let sampleRate = file.processingFormat.sampleRate
        let frameCount = Int(buffer.frameLength)
        let totalMs = Int(Double(frameCount) / sampleRate * 1000)
        let stepMs = 20
        let step = Int(sampleRate) * stepMs / 1000

        var levels: [Float] = []
        var position = 0
        while position + step <= frameCount {
            var sum: Float = 0
            for index in position..<(position + step) {
                sum += samples[index] * samples[index]
            }
            levels.append(10 * log10(max(sum / Float(step), 1e-10)))
            position += step
        }

        var startMs = 0
        var endMs = totalMs
        if !levels.isEmpty {
            let sorted = levels.sorted()
            let noiseFloor = sorted[sorted.count / 10]
            let speechLevel = sorted[sorted.count * 95 / 100]
            // A flat level profile cannot separate speech from background: recognize everything.
            if speechLevel - noiseFloor >= 10 {
                let threshold = max(noiseFloor + 10, speechLevel - 30)
                if let first = levels.firstIndex(where: { $0 > threshold }),
                   let last = levels.lastIndex(where: { $0 > threshold }) {
                    startMs = max(0, first * stepMs - 500)
                    endMs = min(totalMs, (last + 1) * stepMs + 500)
                }
            }
        }

        var plan = RecognitionPlan()
        // Skipping less than a second of silence is not worth altering the request.
        if startMs >= 1000 { plan.offsetMs = startMs }
        if totalMs - endMs >= 1000 { plan.durationMs = endMs - plan.offsetMs }
        let spanMs = plan.durationMs > 0 ? plan.durationMs : totalMs - plan.offsetMs
        plan.singleWindow = spanMs <= 30_000
        return plan
    }

    private func warmUpRecognizerServer() {
        updateRecognizerState(.loading)
        transcriptionQueue.async { [weak self] in
            _ = self?.ensureRecognizerServerReady(maxWait: 20, stateWhileStarting: .loading)
        }

        recognizerHealthTimer?.invalidate()
        recognizerHealthTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, !self.isRecording, !self.isTranscribing else { return }
            self.transcriptionQueue.async { [weak self] in
                guard let self else { return }
                if !self.recognizerServerIsHealthy() {
                    _ = self.ensureRecognizerServerReady(maxWait: 20, stateWhileStarting: .recovering)
                }
            }
        }
        if let recognizerHealthTimer {
            RunLoop.main.add(recognizerHealthTimer, forMode: .common)
        }
    }

    private func updateRecognizerState(_ state: RecognizerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recognizerState = state
            self.refreshMenuState()
        }
    }

    private func recognizerProcess() -> Process? {
        recognizerLock.lock()
        defer { recognizerLock.unlock() }
        return recognizerServer
    }

    private func startRecognizerServerProcess() -> Bool {
        guard FileManager.default.fileExists(atPath: modelPath),
              let server = locateExecutable(candidates: [
                  "/opt/homebrew/bin/whisper-server",
                  "/usr/local/bin/whisper-server"
              ]) else { return false }

        // A server orphaned by a crashed or force-quit Sayo would keep the model in memory.
        _ = runProcess("/usr/bin/pkill", arguments: [
            "-P", "1", "-f", "whisper-server.*--port \(recognizerPort)"
        ], timeout: 3)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: server)
        process.arguments = [
            "-m", modelPath,
            "-l", "auto",
            "-nt",
            "-t", "8",
            "--host", "127.0.0.1",
            "--port", "\(recognizerPort)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            recognizerLock.lock()
            recognizerServer = process
            recognizerLock.unlock()
            return true
        } catch {
            recognizerLock.lock()
            recognizerServer = nil
            recognizerLock.unlock()
            return false
        }
    }

    private func stopRecognizerServer() {
        recognizerLock.lock()
        let process = recognizerServer
        recognizerServer = nil
        recognizerLock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private func recognizerServerIsHealthy() -> Bool {
        guard recognizerProcess()?.isRunning == true else { return false }
        let result = runProcess("/usr/bin/curl", arguments: [
            "--silent", "--show-error", "--fail",
            "--connect-timeout", "1", "--max-time", "2",
            "--output", "/dev/null",
            "http://127.0.0.1:\(recognizerPort)/"
        ], timeout: 3)
        return result.status == 0
    }

    private func ensureRecognizerServerReady(
        maxWait: TimeInterval,
        stateWhileStarting: RecognizerState
    ) -> Bool {
        if recognizerServerIsHealthy() {
            updateRecognizerState(.ready)
            return true
        }

        stopRecognizerServer()
        updateRecognizerState(stateWhileStarting)
        guard startRecognizerServerProcess() else {
            updateRecognizerState(.fallback)
            return false
        }

        let deadline = Date().addingTimeInterval(maxWait)
        while Date() < deadline {
            guard recognizerProcess()?.isRunning == true else { break }
            if recognizerServerIsHealthy() {
                updateRecognizerState(.ready)
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        stopRecognizerServer()
        updateRecognizerState(.fallback)
        return false
    }

    private func transcribeThroughServer(_ input: URL, plan: RecognitionPlan) throws -> String {
        // The server keeps request parameters between calls, so every one is sent explicitly.
        let result = runProcess("/usr/bin/curl", arguments: [
            "--silent", "--show-error", "--fail-with-body",
            "--connect-timeout", "2", "--max-time", "120",
            "http://127.0.0.1:\(recognizerPort)/inference",
            "-F", "file=@\(input.path)",
            "-F", "response_format=json",
            "-F", "language=auto",
            "-F", "offset_t=\(plan.offsetMs)",
            "-F", "duration=\(plan.durationMs)"
        ] + (plan.singleWindow
            ? ["-F", "no_timestamps=true"]
            : ["-F", "no_timestamps=false", "-F", "token_timestamps=false", "-F", "max_context=0"]
        ), timeout: 125)
        guard result.status == 0 else {
            throw DictationError.transcriptionFailed(result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawText = json["text"] as? String else {
            throw DictationError.transcriptionFailed("Некорректный ответ локального сервера")
        }
        return try cleanedTranscript(rawText)
    }

    private func transcribeThroughCLI(_ input: URL, plan: RecognitionPlan) throws -> String {
        guard let whisper = locateExecutable(candidates: [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]) else {
            throw DictationError.missingExecutable("whisper-cli")
        }

        let result = runProcess(whisper, arguments: [
            "-m", modelPath,
            "-f", input.path,
            "-l", "auto",
            "-np",
            "-bo", "2", "-bs", "2",
            "-ot", "\(plan.offsetMs)",
            "-d", "\(plan.durationMs)"
        ] + (plan.singleWindow ? ["-nt"] : ["-mc", "0"]), timeout: 240)
        guard result.status == 0 else {
            throw DictationError.transcriptionFailed(result.stderr)
        }

        return try cleanedTranscript(result.stdout)
    }

    private func cleanedTranscript(_ rawText: String) throws -> String {
        let text = rawText
            .split(separator: "\n")
            .map {
                $0
                    // whisper-cli prefixes every segment with its time range.
                    .replacingOccurrences(
                        of: #"^\[[\d:.]+ --> [\d:.]+\]"#, with: "", options: .regularExpression
                    )
                    // Stage remarks such as *смех* are invented by the model on silence.
                    .replacingOccurrences(of: #"\*[^*]*\*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw DictationError.emptyTranscript }
        return text
    }

    private func copyAndPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        addToHistory(text)

        guard autoPasteEnabled, AXIsProcessTrusted() else {
            setStatus(icon: idleIcon, title: "Текст скопирован в буфер")
            hud.showSuccess(autoPasted: false)
            NSSound(named: "Glass")?.play()
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        commandDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        commandUp?.flags = []

        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
        hud.showSuccess(autoPasted: true)
        NSSound(named: "Glass")?.play()
    }

    private func addToHistory(_ text: String) {
        transcriptHistory.removeAll { $0 == text }
        transcriptHistory.insert(text, at: 0)
        transcriptHistory = Array(transcriptHistory.prefix(12))
        UserDefaults.standard.set(transcriptHistory, forKey: "transcriptHistory")
        rebuildHistoryMenu()
    }

    private func rebuildHistoryMenu() {
        guard historyMenu != nil else { return }
        historyMenu.removeAllItems()
        if transcriptHistory.isEmpty {
            let empty = NSMenuItem(title: "История пока пуста", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
            return
        }

        for text in transcriptHistory {
            let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            let title = oneLine.count > 72 ? String(oneLine.prefix(72)) + "…" : oneLine
            let item = NSMenuItem(title: title, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = text
            item.toolTip = text
            historyMenu.addItem(item)
        }
        historyMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Очистить историю", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        historyMenu.addItem(clear)
    }

    private func locateExecutable(candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func runProcess(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(
                status: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false
            )
        }

        let readGroup = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        readGroup.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        var stderr = String(data: stderrData, encoding: .utf8) ?? ""
        if timedOut {
            if !stderr.isEmpty && !stderr.hasSuffix("\n") { stderr += "\n" }
            stderr += "Превышено время ожидания процесса \(URL(fileURLWithPath: executable).lastPathComponent)"
        }
        return ProcessResult(
            status: timedOut ? -2 : process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }

    private func showError(_ message: String) {
        setStatus(icon: "exclamationmark.triangle", title: message)
        hud.showError(message)
        refreshMenuState()
        NSSound.beep()
    }

    @objc private func openHUDSettings() {
        if designPreviewWindow == nil {
            designPreviewWindow = OrbDesignPreviewWindowController(
                persistsChanges: true,
                onSettingsChanged: { [weak self] in
                    self?.hud.reloadPreferences()
                    self?.refreshMenuState()
                }
            )
        }
        NSApplication.shared.setActivationPolicy(.regular)
        designPreviewWindow?.showWindow(nil)
        designPreviewWindow?.window?.center()
        designPreviewWindow?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openAccessibilitySettings() {
        if !AXIsProcessTrusted() {
            openPrivacySettings(anchor: "Privacy_Accessibility")
        } else if eventTap == nil && !CGPreflightListenEventAccess() {
            hasRequestedInputMonitoring = true
            _ = CGRequestListenEventAccess()
            openPrivacySettings(anchor: "Privacy_ListenEvent")
        } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            openPrivacySettings(anchor: "Privacy_Microphone")
        } else {
            openPrivacySettings(anchor: "Privacy_Accessibility")
        }
    }

    @objc private func resetHUDPosition() {
        hud.resetPosition()
        setStatus(icon: idleIcon, title: "Панель вернётся вниз экрана")
    }

    private func openPrivacySettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

let app = NSApplication.shared
private let delegate = DictationController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
