import CoreGraphics

enum TornPaperPath {
    static func make(
        in rect: CGRect,
        cornerRadius: CGFloat,
        toothWidth: CGFloat,
        tearHeight: CGFloat,
        jitter: [CGFloat]
    ) -> CGPath {
        let path = CGMutablePath()
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let tearTop = rect.maxY - tearHeight

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: tearTop))

        let midline = rect.maxY - tearHeight / 2
        let amplitude = tearHeight / 2
        var x = rect.maxX
        var index = 0
        var pointsDown = true
        while x > rect.minX {
            let jitterValue = jitter.isEmpty ? 0.5 : jitter[index % jitter.count]
            x = max(rect.minX, x - toothWidth)
            let offset = amplitude * (0.7 + 0.3 * jitterValue)
            path.addLine(to: CGPoint(
                x: x,
                y: pointsDown ? midline + offset : midline - offset
            ))
            pointsDown.toggle()
            index += 1
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.closeSubpath()
        return path
    }
}
