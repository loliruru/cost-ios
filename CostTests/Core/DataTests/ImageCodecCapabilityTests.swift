import CoreGraphics
import ImageIO
import Testing
@testable import Cost

struct ImageCodecCapabilityTests {
    @Test
    func recordSystemImageExchangeCapabilities() throws {
        let encoders = CGImageDestinationCopyTypeIdentifiers() as! [String]
        let decoders = CGImageSourceCopyTypeIdentifiers() as! [String]
        print("COST_IMAGE_ENCODERS=\(encoders.sorted().joined(separator: ","))")
        print("COST_IMAGE_DECODERS=\(decoders.sorted().joined(separator: ","))")
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        for type in ["public.png", "org.webmproject.webp"] {
            let bytes = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(bytes, type as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                let encoded = CGImageDestinationFinalize(destination)
                print("COST_IMAGE_ENCODE_\(type)=\(encoded);bytes=\(bytes.length)")
                if type == "public.png" {
                    #expect(encoded)
                    let source = try #require(CGImageSourceCreateWithData(bytes, nil))
                    #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
                }
            } else {
                print("COST_IMAGE_ENCODE_\(type)=unavailable")
                #expect(type != "public.png")
            }
        }
    }
}
