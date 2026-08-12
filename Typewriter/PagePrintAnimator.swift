import AppKit

enum PagePrintAnimator {
    struct Page {
        let snapshot: NSImage
        let frame: NSRect
    }

    private static let flightDuration: CFTimeInterval = 0.66
    private static let stackHoldDuration: CFTimeInterval = 0.08
    private static let emptyCanvasBeatDuration: CFTimeInterval = 0.16
    private static let returnDuration: CFTimeInterval = 0.44

    static func animate(
        pages: [Page],
        in container: NSView,
        revealContent: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        guard let topPage = pages.first else {
            revealContent()
            completion()
            return
        }

        let stack = PageStackAnimationView(pages: pages)
        container.addSubview(stack, positioned: .above, relativeTo: nil)

        // Give AppKit one display pass at the pages' separated positions before
        // beginning the gather. Starting in the same transaction makes the pages
        // appear to pop directly into their stacked geometry.
        DispatchQueue.main.async {
            stack.gatherPages {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + stackHoldDuration
                ) {
                    addMotionTrails(
                        behind: stack,
                        in: container,
                        pageFrame: topPage.frame
                    )
                    animateStackExit(
                        stack,
                        containerHeight: container.bounds.height
                    )

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + flightDuration
                    ) {
                        stack.removeFromSuperview()

                        // A brief empty canvas separates sending the printed stack
                        // from calmly restoring the editable document.
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + emptyCanvasBeatDuration
                        ) {
                            animatePagesBack(
                                pages,
                                in: container,
                                revealContent: revealContent,
                                completion: completion
                            )
                        }
                    }
                }
            }
        }
    }

    /// Attaches a named CIMotionBlur filter to sheet imagery only. The stack's
    /// shared shadow deliberately lives on a separate, unfiltered layer.
    private static func attachMotionBlur(to layer: CALayer, angle: CGFloat) {
        guard let blur = CIFilter(name: "CIMotionBlur") else { return }
        blur.setDefaults()
        blur.name = "pageMotionBlur"
        blur.setValue(0, forKey: "inputRadius")
        blur.setValue(angle, forKey: "inputAngle")
        layer.filters = [blur]
    }

    private static func animateStackExit(
        _ stack: PageStackAnimationView,
        containerHeight: CGFloat
    ) {
        guard let stackLayer = stack.layer else { return }

        var start = CATransform3DIdentity
        start.m34 = -1 / 850
        var anticipation = CATransform3DTranslate(start, 0, -12, 12)
        anticipation = CATransform3DRotate(
            anticipation,
            0.018,
            0,
            0,
            1
        )
        var lift = CATransform3DTranslate(start, -22, 96, 70)
        lift = CATransform3DRotate(lift, -0.035, 0, 0, 1)
        lift = CATransform3DRotate(lift, 0.07, 1, 0, 0)
        var exit = CATransform3DTranslate(
            start,
            172,
            containerHeight + 260,
            170
        )
        exit = CATransform3DRotate(exit, 0.15, 0, 0, 1)
        exit = CATransform3DRotate(exit, -0.28, 1, 0, 0)
        exit = CATransform3DScale(exit, 0.72, 0.72, 1)

        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = [start, anticipation, lift, exit]
        transform.keyTimes = [0, 0.1, 0.34, 1]

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 1, 0]
        opacity.keyTimes = [0, 0.25, 0.72, 1]

        let stackGroup = CAAnimationGroup()
        stackGroup.animations = [transform, opacity]
        stackGroup.duration = flightDuration
        stackGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        stackGroup.isRemovedOnCompletion = false
        stackGroup.fillMode = .forwards
        stackLayer.add(stackGroup, forKey: "typewriter.pageStackFlight")

        animateLiftShadow(stack.shadowLayer)
        animateSheetMotionBlur(stack.sheetImageLayers)
    }

    private static func animateLiftShadow(_ layer: CALayer) {
        let shadowOpacity = CAKeyframeAnimation(keyPath: "shadowOpacity")
        shadowOpacity.values = [0.13, 0.2, 0.38, 0.4, 0.28, 0]
        shadowOpacity.keyTimes = [0, 0.1, 0.34, 0.52, 0.78, 1]

        let shadowRadius = CAKeyframeAnimation(keyPath: "shadowRadius")
        shadowRadius.values = [11, 16, 30, 38, 44, 48]
        shadowRadius.keyTimes = shadowOpacity.keyTimes

        let shadowOffset = CAKeyframeAnimation(keyPath: "shadowOffset")
        shadowOffset.values = [
            NSValue(size: NSSize(width: 0, height: -2)),
            NSValue(size: NSSize(width: 0, height: -6)),
            NSValue(size: NSSize(width: -3, height: -18)),
            NSValue(size: NSSize(width: -5, height: -25)),
            NSValue(size: NSSize(width: -7, height: -31)),
            NSValue(size: NSSize(width: -9, height: -34))
        ]
        shadowOffset.keyTimes = shadowOpacity.keyTimes

        let group = CAAnimationGroup()
        group.animations = [shadowOpacity, shadowRadius, shadowOffset]
        group.duration = flightDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        layer.add(group, forKey: "typewriter.pageStackLiftShadow")
    }

    private static func animateSheetMotionBlur(_ layers: [CALayer]) {
        for layer in layers {
            attachMotionBlur(to: layer, angle: .pi / 2)

            let motionBlur = CAKeyframeAnimation(
                keyPath: "filters.pageMotionBlur.inputRadius"
            )
            motionBlur.values = [0, 0.5, 2, 5, 7]
            motionBlur.keyTimes = [0, 0.12, 0.34, 0.72, 1]
            motionBlur.duration = flightDuration
            motionBlur.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            motionBlur.isRemovedOnCompletion = false
            motionBlur.fillMode = .forwards
            layer.add(
                motionBlur,
                forKey: "typewriter.pageStackMotionBlur"
            )
        }
    }

    private static func animatePagesBack(
        _ pages: [Page],
        in container: NSView,
        revealContent: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        let returningPages = pages.map { page -> PageSheetView in
            let startFrame = NSRect(
                x: page.frame.minX,
                y: -page.frame.height - 36,
                width: page.frame.width,
                height: page.frame.height
            )
            return PageSheetView(
                snapshot: page.snapshot,
                frame: startFrame,
                shadowStyle: .resting
            )
        }

        for index in returningPages.indices.reversed() {
            container.addSubview(
                returningPages[index],
                positioned: .above,
                relativeTo: nil
            )
        }

        // Commit the below-window starting geometry before the calm return.
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = returnDuration
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.18,
                    0.88,
                    0.24,
                    1
                )
                for index in returningPages.indices {
                    returningPages[index].animator().frame = pages[index].frame
                }
            } completionHandler: {
                revealContent()
                // Keep the matching snapshots in place for one display pass so
                // the real canvas and its resting shadows can take over invisibly.
                DispatchQueue.main.async {
                    returningPages.forEach { $0.removeFromSuperview() }
                    completion()
                }
            }
        }
    }

    private static func addMotionTrails(
        behind page: NSView,
        in container: NSView,
        pageFrame: NSRect
    ) {
        let horizontalOffsets: [CGFloat] = [-42, 24, -4]

        for index in horizontalOffsets.indices {
            let width = CGFloat(40 + index * 12)
            let streak = NSView(frame: NSRect(
                x: pageFrame.midX + horizontalOffsets[index] - width / 2,
                y: pageFrame.maxY - CGFloat(14 + index * 7),
                width: width,
                height: 2
            ))
            streak.wantsLayer = true
            streak.alphaValue = 0

            let gradient = CAGradientLayer()
            gradient.frame = streak.bounds
            gradient.colors = [
                TypewriterTheme.paper.withAlphaComponent(0).cgColor,
                TypewriterTheme.paper.withAlphaComponent(0.7).cgColor,
                TypewriterTheme.paper.withAlphaComponent(0).cgColor
            ]
            gradient.locations = [0, 0.5, 1]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            gradient.cornerRadius = 1
            streak.layer?.addSublayer(gradient)
            container.addSubview(streak, positioned: .below, relativeTo: page)

            let verticalPosition = CABasicAnimation(
                keyPath: "transform.translation.y"
            )
            verticalPosition.fromValue = 0
            verticalPosition.toValue = CGFloat(82 + index * 24)

            let horizontalPosition = CABasicAnimation(
                keyPath: "transform.translation.x"
            )
            horizontalPosition.fromValue = 0
            horizontalPosition.toValue = CGFloat([-10, 14, 6][index])

            let stretch = CABasicAnimation(keyPath: "transform.scale.x")
            stretch.fromValue = 0.72
            stretch.toValue = 1.18

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.28, 0.2, 0]
            opacity.keyTimes = [0, 0.22, 0.58, 1]

            let group = CAAnimationGroup()
            group.animations = [
                verticalPosition,
                horizontalPosition,
                stretch,
                opacity
            ]
            group.beginTime = CACurrentMediaTime()
                + 0.07
                + Double(index) * 0.03
            group.duration = 0.32
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            streak.layer?.add(group, forKey: "typewriter.motionTrail")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                streak.removeFromSuperview()
            }
        }
    }
}

private final class PageStackAnimationView: NSView {
    private static let maximumVisibleDepth = 5
    private static let horizontalDepthOffset: CGFloat = 2.2
    private static let verticalDepthOffset: CGFloat = -3.2

    private let shadowView: PageLiftShadowView
    private let sheetViews: [PageSheetView]

    var shadowLayer: CALayer {
        shadowView.layer ?? CALayer()
    }

    var sheetImageLayers: [CALayer] {
        sheetViews.map(\.imageLayer)
    }

    init(pages: [PagePrintAnimator.Page]) {
        precondition(!pages.isEmpty)

        let topFrame = pages[0].frame
        shadowView = PageLiftShadowView(
            frame: NSRect(origin: .zero, size: topFrame.size)
        )
        sheetViews = pages.map {
            PageSheetView(
                snapshot: $0.snapshot,
                frame: $0.frame,
                shadowStyle: .stackContact
            )
        }

        super.init(frame: topFrame)
        wantsLayer = true
        layer?.masksToBounds = false

        shadowView.frame = bounds
        addSubview(shadowView)

        for index in sheetViews.indices.reversed() {
            let pageFrame = pages[index].frame
            sheetViews[index].frame = pageFrame.offsetBy(
                dx: -topFrame.minX,
                dy: -topFrame.minY
            )
            addSubview(sheetViews[index])
        }
    }

    required init?(coder: NSCoder) { nil }

    func gatherPages(completion: @escaping () -> Void) {
        guard sheetViews.count > 1 else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2,
                0.82,
                0.24,
                1
            )

            for index in 1..<sheetViews.count {
                let depth = min(index, Self.maximumVisibleDepth)
                sheetViews[index].animator().frame = bounds.offsetBy(
                    dx: CGFloat(depth) * Self.horizontalDepthOffset,
                    dy: CGFloat(depth) * Self.verticalDepthOffset
                )
            }

            let deepestVisiblePage = min(
                sheetViews.count - 1,
                Self.maximumVisibleDepth
            )
            shadowView.animator().frame = bounds.offsetBy(
                dx: CGFloat(deepestVisiblePage)
                    * Self.horizontalDepthOffset,
                dy: CGFloat(deepestVisiblePage)
                    * Self.verticalDepthOffset
            )
        } completionHandler: {
            completion()
        }
    }
}

private final class PageSheetView: NSView {
    enum ShadowStyle {
        case none
        case stackContact
        case resting
    }

    let imageLayer: CALayer

    init(
        snapshot: NSImage,
        frame: NSRect,
        shadowStyle: ShadowStyle = .none
    ) {
        let imageView = NSImageView(
            frame: NSRect(origin: .zero, size: frame.size)
        )
        imageView.image = snapshot
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4

        imageLayer = imageView.layer ?? CALayer()

        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        switch shadowStyle {
        case .none:
            layer?.shadowOpacity = 0
        case .stackContact:
            // A tight, constant contact shadow keeps the sheets legible as
            // individual pages. The separate stack shadow supplies all of the
            // larger lift effect, so lower pages never inherit that growth.
            layer?.shadowOpacity = 0.14
            layer?.shadowRadius = 4
            layer?.shadowOffset = NSSize(width: 0, height: -1.5)
        case .resting:
            layer?.shadowOpacity = 0.13
            layer?.shadowRadius = 11
            layer?.shadowOffset = NSSize(width: 0, height: -2)
        }
        if shadowStyle != .none {
            layer?.shadowPath = CGPath(
                roundedRect: bounds,
                cornerWidth: 4,
                cornerHeight: 4,
                transform: nil
            )
        }
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { nil }
}

private final class PageLiftShadowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.13
        layer?.shadowRadius = 11
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
    }

    required init?(coder: NSCoder) { nil }
}
