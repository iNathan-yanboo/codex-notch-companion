import AppKit
import Metal
import QuartzCore
import simd

struct ContourSegmentGPU {
    var ax: Float
    var ay: Float
    var bx: Float
    var by: Float
    var t0: Float
    var t1: Float
}

struct ContourUniformsGPU {
    var viewportWidth: Float
    var viewportHeight: Float
    var progress: Float
    var flowPhase: Float
    var hovering: Float
    var expanded: Float
    var segmentCount: UInt32
    var contentScale: Float
    var glowIntensity: Float
    var style: Float
    var pelletFrac: Float
    var pelletCell: Float
}

enum NotchContourPathSampler {
    static func segments(from geometry: NotchContourGeometry, curveSamples: Int = 24) -> [ContourSegmentGPU] {
        let bodyRect = geometry.bodyRect
        let strokeInset = geometry.strokeInset
        let bodyRadius = min(24, max(12, bodyRect.height * 0.35))
        let contourRadius = max(0, bodyRadius - strokeInset)
        let lineBottom = max(0, bodyRect.maxY - strokeInset)
        let contourCurveStartY = max(0, lineBottom - contourRadius)
        let curveControlOffset = contourRadius * 0.58

        var points: [CGPoint] = []
        points.append(geometry.start)
        points.append(CGPoint(x: geometry.start.x, y: contourCurveStartY))

        appendCubicSamples(
            to: &points,
            from: CGPoint(x: geometry.start.x, y: contourCurveStartY),
            control1: CGPoint(x: geometry.start.x, y: contourCurveStartY + curveControlOffset),
            control2: CGPoint(x: geometry.start.x + contourRadius - curveControlOffset, y: lineBottom),
            to: CGPoint(x: geometry.start.x + contourRadius, y: lineBottom),
            samples: curveSamples
        )

        points.append(CGPoint(x: geometry.end.x - contourRadius, y: lineBottom))

        appendCubicSamples(
            to: &points,
            from: CGPoint(x: geometry.end.x - contourRadius, y: lineBottom),
            control1: CGPoint(x: geometry.end.x - contourRadius + curveControlOffset, y: lineBottom),
            control2: CGPoint(x: geometry.end.x, y: contourCurveStartY + curveControlOffset),
            to: CGPoint(x: geometry.end.x, y: contourCurveStartY),
            samples: curveSamples
        )

        points.append(geometry.end)

        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for index in 1..<points.count {
            let segmentLength = hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            lengths.append(segmentLength)
            total += segmentLength
        }
        guard total > 0 else { return [] }

        var segments: [ContourSegmentGPU] = []
        var traversed: CGFloat = 0
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let length = lengths[index - 1]
            guard length > 0 else { continue }

            let t0 = Float(traversed / total)
            traversed += length
            let t1 = Float(traversed / total)

            segments.append(
                ContourSegmentGPU(
                    ax: Float(start.x),
                    ay: Float(start.y),
                    bx: Float(end.x),
                    by: Float(end.y),
                    t0: t0,
                    t1: t1
                )
            )
        }
        return segments
    }

    private static func appendCubicSamples(
        to points: inout [CGPoint],
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint,
        samples: Int
    ) {
        guard samples > 1 else {
            points.append(end)
            return
        }
        for step in 1...samples {
            let t = CGFloat(step) / CGFloat(samples)
            let u = 1 - t
            let x = u * u * u * start.x
                + 3 * u * u * t * control1.x
                + 3 * u * t * t * control2.x
                + t * t * t * end.x
            let y = u * u * u * start.y
                + 3 * u * u * t * control1.y
                + 3 * u * t * t * control2.y
                + t * t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
    }
}

@MainActor
final class NotchContourMetalRenderer {
    static let layerName = "notch-contour-metal"

    let metalLayer = CAMetalLayer()

    private let device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var segmentBuffer: MTLBuffer?
    private var segmentCount: UInt32 = 0

    var weeklyProgress: CGFloat = 0
    var hovering = false
    var expanded = false
    var flowPhase: CGFloat = 0
    var glowIntensity: CGFloat = 1
    var style: Float = ProgressBarStyle.pacman.shaderValue
    var pelletFrac: Float = 0
    var pelletCell: Float = 0
    private(set) var isReady = false

    init() {
        device = MTLCreateSystemDefaultDevice()
        metalLayer.name = Self.layerName
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.backgroundColor = NSColor.clear.cgColor
        metalLayer.allowsNextDrawableTimeout = false

        guard let device else { return }
        commandQueue = device.makeCommandQueue()
        pipelineState = Self.makePipelineState(device: device)
        isReady = pipelineState != nil && commandQueue != nil
    }

    func update(
        weeklyPercent: Double,
        hovering: Bool,
        expanded: Bool,
        glowIntensity: CGFloat = 1,
        style: Float? = nil
    ) {
        weeklyProgress = NotchContourGeometry.normalizedProgress(weeklyPercent)
        self.hovering = hovering
        self.expanded = expanded
        self.glowIntensity = min(max(glowIntensity, 0), 1)
        if let style { self.style = style }
        render()
    }

    func advanceFlow(to phase: CGFloat) {
        flowPhase = min(max(phase, 0), 1)
        render()
    }

    /// Continuous, non-looping pellet scroll. `seconds` is a monotonically increasing
    /// clock; `cellsPerSecond` sets pellet speed. Split into frac + cell (mod 4096) so
    /// float precision holds and the pattern advances +1 uniformly forever (no wrap/stutter).
    /// Does not render; call `advanceFlow` afterwards to draw a single frame.
    func advancePellets(seconds: Double, cellsPerSecond: Double) {
        let scroll = seconds * cellsPerSecond
        let intPart = scroll.rounded(.down)
        pelletFrac = Float(scroll - intPart)
        pelletCell = Float(intPart.truncatingRemainder(dividingBy: 4096))
    }

    func layout(in bounds: CGRect, geometry: NotchContourGeometry) {
        metalLayer.frame = bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )

        let segments = NotchContourPathSampler.segments(from: geometry)
        guard let device, !segments.isEmpty else {
            segmentBuffer = nil
            segmentCount = 0
            return
        }

        segmentBuffer = device.makeBuffer(
            bytes: segments,
            length: MemoryLayout<ContourSegmentGPU>.stride * segments.count,
            options: .storageModeShared
        )
        segmentCount = UInt32(segments.count)
        render()
    }

    func render() {
        guard isReady,
              let pipelineState,
              let commandQueue,
              let segmentBuffer,
              segmentCount > 0,
              metalLayer.drawableSize.width > 1,
              metalLayer.drawableSize.height > 1,
              let drawable = metalLayer.nextDrawable() else {
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        var uniforms = ContourUniformsGPU(
            viewportWidth: Float(metalLayer.drawableSize.width),
            viewportHeight: Float(metalLayer.drawableSize.height),
            progress: Float(weeklyProgress),
            flowPhase: Float(flowPhase),
            hovering: hovering ? 1 : 0,
            expanded: expanded ? 1 : 0,
            segmentCount: segmentCount,
            contentScale: Float(metalLayer.contentsScale),
            glowIntensity: Float(glowIntensity),
            style: style,
            pelletFrac: pelletFrac,
            pelletCell: pelletCell
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ContourUniformsGPU>.stride, index: 0)
        encoder.setFragmentBuffer(segmentBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func makePipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: NotchContourMetalShaderSource.source, options: nil)
            guard let vertex = library.makeFunction(name: "contourVertex"),
                  let fragment = library.makeFunction(name: "contourFragment") else {
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
    }
}
