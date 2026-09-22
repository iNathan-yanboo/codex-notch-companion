import CoreGraphics

struct NotchContourGeometry {
    let size: CGSize
    let bodyInset: CGFloat
    let strokeInset: CGFloat

    let bodyRect: CGRect
    let start: CGPoint
    let end: CGPoint
    let bottomCenter: CGPoint

    let bodyPath: CGPath
    let contourPath: CGPath

    init(size: CGSize, bodyInset: CGFloat, strokeInset: CGFloat) {
        self.size = size
        self.bodyInset = max(0, bodyInset)
        self.strokeInset = max(0, strokeInset)

        let bodyWidth = max(0, size.width - self.bodyInset * 2)
        let bodyHeight = max(0, size.height - self.bodyInset)
        let bodyRect = CGRect(x: self.bodyInset, y: 0, width: bodyWidth, height: bodyHeight)
        let lineBottom = max(0, bodyRect.maxY - self.strokeInset)
        let start = CGPoint(x: bodyRect.minX + self.strokeInset, y: 0)
        let end = CGPoint(x: bodyRect.maxX - self.strokeInset, y: 0)
        let bottomCenter = CGPoint(x: bodyRect.midX, y: lineBottom)

        self.bodyRect = bodyRect
        self.start = start
        self.end = end
        self.bottomCenter = bottomCenter

        let bodyRadius = min(24, max(12, bodyRect.height * 0.35))
        let body = CGMutablePath()
        body.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
        body.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY))
        body.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - bodyRadius))
        body.addCurve(
            to: CGPoint(x: bodyRect.maxX - bodyRadius, y: bodyRect.maxY),
            control1: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - bodyRadius * 0.42),
            control2: CGPoint(x: bodyRect.maxX - bodyRadius * 0.42, y: bodyRect.maxY)
        )
        body.addLine(to: CGPoint(x: bodyRect.minX + bodyRadius, y: bodyRect.maxY))
        body.addCurve(
            to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY - bodyRadius),
            control1: CGPoint(x: bodyRect.minX + bodyRadius * 0.42, y: bodyRect.maxY),
            control2: CGPoint(x: bodyRect.minX, y: bodyRect.maxY - bodyRadius * 0.42)
        )
        body.closeSubpath()
        self.bodyPath = body

        let contourRadius = max(0, bodyRadius - self.strokeInset)
        let contourCurveStartY = max(0, lineBottom - contourRadius)
        let curveControlOffset = contourRadius * 0.58

        let contour = CGMutablePath()
        contour.move(to: start)
        contour.addLine(to: CGPoint(x: start.x, y: contourCurveStartY))
        contour.addCurve(
            to: CGPoint(x: start.x + contourRadius, y: lineBottom),
            control1: CGPoint(x: start.x, y: contourCurveStartY + curveControlOffset),
            control2: CGPoint(x: start.x + contourRadius - curveControlOffset, y: lineBottom)
        )
        contour.addLine(to: CGPoint(x: end.x - contourRadius, y: lineBottom))
        contour.addCurve(
            to: CGPoint(x: end.x, y: contourCurveStartY),
            control1: CGPoint(x: end.x - contourRadius + curveControlOffset, y: lineBottom),
            control2: CGPoint(x: end.x, y: contourCurveStartY + curveControlOffset)
        )
        contour.addLine(to: end)
        self.contourPath = contour
    }

    static func normalizedProgress(_ percent: Double) -> CGFloat {
        CGFloat(min(max(percent / 100, 0), 1))
    }
}
