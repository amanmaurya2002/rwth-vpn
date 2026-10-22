import AppKit
import SwiftUI

/// The Dock icon, drawn in SwiftUI and converted to .icns at build time.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(Brand.gradient)
                .frame(width: 824, height: 824)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 430, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
enum IconRenderer {
    static func render(to path: String) {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("icon render failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
