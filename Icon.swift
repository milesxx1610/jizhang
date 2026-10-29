import AppKit
import Foundation

let root = URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
func draw(name: String, dark: Bool) throws {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    (dark ? color(0.07, 0.10, 0.12) : color(0.96, 0.96, 0.94)).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    let ink = dark ? color(0.91, 0.95, 0.93) : color(0.12, 0.20, 0.19)
    ink.setStroke()
    let wallet = NSBezierPath(roundedRect: NSRect(x: 225, y: 305, width: 574, height: 414), xRadius: 112, yRadius: 112)
    wallet.lineWidth = 52
    wallet.stroke()
    let flap = NSBezierPath(roundedRect: NSRect(x: 565, y: 430, width: 238, height: 140), xRadius: 68, yRadius: 68)
    ink.setFill(); flap.fill()
    color(0.33, 0.78, 0.65).setFill()
    NSBezierPath(ovalIn: NSRect(x: 626, y: 477, width: 46, height: 46)).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("icon encoding failed") }
    try png.write(to: root.appendingPathComponent(name))
}
try draw(name: "light.png", dark: false)
try draw(name: "dark.png", dark: true)
let json = """
{"images":[{"filename":"light.png","idiom":"universal","platform":"ios","size":"1024x1024"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"filename":"dark.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try json.write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

