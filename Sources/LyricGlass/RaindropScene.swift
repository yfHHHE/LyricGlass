import AppKit
import SceneKit

/// Exact geometry exported from the user's offline Three.js avatar, with native rendering.
final class RaindropScene {
    struct Asset: Decodable {
        struct Mesh: Decodable {
            let name: String
            let positions: [Float]
            let colors: [Float]
            let indices: [UInt32]
            let color: String
        }
        let meshes: [Mesh]
    }
    let scene = SCNScene()
    let character = SCNNode()
    let camera = SCNNode()
    private var eyelids: [SCNNode] = []

    init(resourceURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("Avatar/raindrop.json")) throws {
        guard let resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: resourceURL))
        guard asset.meshes.count == 5 else { throw CocoaError(.fileReadCorruptFile) }
        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(character)
        for mesh in asset.meshes {
            guard mesh.positions.count % 3 == 0, mesh.indices.count % 3 == 0,
                  mesh.indices.allSatisfy({ Int($0) < mesh.positions.count / 3 }),
                  mesh.colors.isEmpty || mesh.colors.count == mesh.positions.count else { throw CocoaError(.fileReadCorruptFile) }
            let vertices = SCNGeometrySource(data: mesh.positions.withUnsafeBytes { Data($0) }, semantic: .vertex,
                vectorCount: mesh.positions.count / 3, usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
            var sources = [vertices]
            if !mesh.colors.isEmpty {
                var rgba: [Float] = []
                for i in stride(from: 0, to: mesh.colors.count, by: 3) { rgba += Array(mesh.colors[i..<i+3]) + [1] }
                sources.append(SCNGeometrySource(data: rgba.withUnsafeBytes { Data($0) }, semantic: .color,
                    vectorCount: rgba.count / 4, usesFloatComponents: true, componentsPerVector: 4,
                    bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
            }
            let element = SCNGeometryElement(data: mesh.indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                primitiveCount: mesh.indices.count / 3, bytesPerIndex: 4)
            let geometry = SCNGeometry(sources: sources, elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor(hex: mesh.color)
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = mesh.name
            if mesh.name.hasPrefix("eye-") {
                // Pivot in place: a blink must not move the eyes down the face.
                node.pivot = SCNMatrix4MakeTranslation(0, 0.09, 0)
                node.position.y = 0.09
                eyelids.append(node)
            }
            character.addChildNode(node)
        }
        let projection = SCNCamera()
        projection.usesOrthographicProjection = true
        projection.orthographicScale = 1.52
        projection.zNear = 0.1; projection.zFar = 30
        projection.wantsHDR = false
        camera.camera = projection
        camera.position = SCNVector3(0, 0, 8)
        scene.rootNode.addChildNode(camera)
    }

    func pose(time: Double, playing: Bool, motion: PetMotion, pulse: Double = 0,
              reducedMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        let moving = playing && motion != .still && !reducedMotion
        let phase = time * .pi * 2 * 1.4 // A gentle loop, explicitly not a measured musical beat.
        let energy = motion == .audio ? min(1, max(0, pulse)) : (sin(phase) + 1) / 2
        let bounce = moving ? energy : 0
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        character.position.y = CGFloat(bounce * 0.12)
        character.scale = SCNVector3(1 + bounce * 0.065, 1 - bounce * 0.065, 1)
        character.eulerAngles.z = CGFloat(moving ? sin(time * 3.1) * 0.045 * (motion == .audio ? energy : 1) : 0)
        let blinkPhase = time.truncatingRemainder(dividingBy: 5.3)
        let blink = !reducedMotion && blinkPhase > 5.1 ? max(0.08, abs(blinkPhase - 5.2) / 0.1) : 1
        for node in eyelids { node.scale.y = CGFloat(blink) }
        SCNTransaction.commit()
    }
}

enum PetMotion: String, Codable, CaseIterable {
    case still, gentle, audio
    var title: String { switch self { case .still: return "静止"; case .gentle: return "摇摆"; case .audio: return "音频律动" } }
}

final class RaindropPetView: SCNView {
    private(set) var avatar: RaindropScene?
    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 20
        rendersContinuously = false
        isPlaying = false
        allowsCameraControl = false
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setEnabled(_ enabled: Bool) {
        isHidden = !enabled
        if enabled && avatar == nil {
            do { let model = try RaindropScene(); avatar = model; scene = model.scene; pointOfView = model.camera }
            catch { NSLog("RainDrop asset unavailable: %@", error.localizedDescription) }
        } else if !enabled { scene = nil; avatar = nil }
    }
    func update(time: Double, playing: Bool, motion: PetMotion, pulse: Double = 0) {
        guard !isHidden, window?.isVisible == true else { return }
        avatar?.pose(time: time, playing: playing, motion: motion, pulse: pulse)
        needsDisplay = true
    }
    // The companion remains part of the draggable lyrics surface.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
