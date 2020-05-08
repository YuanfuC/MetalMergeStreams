//
//  FrameMixer.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/18.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import CoreMedia
import MetalKit
import MetalPerformanceShaders

@objc public enum PixelResizeMode: Int {
    case scaleToFill = 1
    case scaleAspectFit = 2
    case scaleAspectFill = 3
}

@objc public class FrameMixer: NSObject {
    
    @objc public var inFrame = CGRect.zero
    @objc public var isPrepared:Bool = false
    @objc public var isMirror:Bool = false
    
    private let metalDevice:MTLDevice? = MTLCreateSystemDefaultDevice()
    private let computePipelineState:MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?
    
    private lazy var commandQueue: MTLCommandQueue? = {
        guard let device =  metalDevice else {
            return nil
        }
        return device.makeCommandQueue()
    }()
    
    private(set) var inputFormatDescription: CMFormatDescription?
    private(set) var outputFormatDescription: CMFormatDescription?
    private var outputPixelBufferPool: CVPixelBufferPool?
    
    private var resizePoolDimensions = CMVideoDimensions.init(width: 0, height: 0)
    private var resizePixelBufferPool: CVPixelBufferPool?
    
    @objc public override init() {
        guard let device = metalDevice,
            let library = device.makeDefaultLibrary(),
            let kernalFunction = library.makeFunction(name: "frameMixer") else {
                print("FrameMixer object init failed")
                computePipelineState = nil
                super.init()
                return
        }
        
        do {
            try computePipelineState = device.makeComputePipelineState(function: kernalFunction)
        } catch  {
            print("FrameMixer pipeLine state create failed")
            computePipelineState = nil
            super.init()
            return
        }
        super.init()
    }
    
    @objc public func resetPixelBufferPool(){
        isPrepared = false;
        if let pool = outputPixelBufferPool {
            CVPixelBufferPoolFlush(pool, .excessBuffers)
        }
    }
    
    @objc public func prepare(with videoFormatDescription:CMFormatDescription, outputRetainedBufferCountHint: Int) {
        (outputPixelBufferPool, _, outputFormatDescription) = allocOutputBufferPool(with: videoFormatDescription,
                                                                                    outputRetainedBufferCountHint: outputRetainedBufferCountHint)
        if outputPixelBufferPool == nil {
            return
        }
        inputFormatDescription = videoFormatDescription
        
        guard let metalDevice = metalDevice else {
            return
        }
        
        var metalTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
            assertionFailure("FrameMixer unable to allocate video mixer texture cache")
        } else {
            textureCache = metalTextureCache
        }
        
        isPrepared = true
    }
    
    @objc public func resizePixelBufferWithPool(sourcePixelFrame:CVPixelBuffer, targetSize:MTLSize, resizeMode: PixelResizeMode) -> CVPixelBuffer? {
        
        guard isPrepared,
            let description = outputFormatDescription else {
                assertionFailure("FrameMixer resize invalid state: Not prepared")
                return nil
        }
        
        if (self.resizePixelBufferPool == nil ||  self.resizePoolDimensions.width != targetSize.width || self.resizePoolDimensions.height != targetSize.height) {
            self.resizePoolDimensions = CMVideoDimensions.init(width: Int32(targetSize.width), height: Int32(targetSize.height))
            (resizePixelBufferPool,_,_) = allocOutputBufferPool(with: description, outputRetainedBufferCountHint: 3, dimension: resizePoolDimensions)
        }
        
        guard let outputPixelBufferPool = resizePixelBufferPool else {
            print("FrameMixer resize create pixel bufferpool failed")
            return nil
        }
        
        var newPixelBuffer:CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool, &newPixelBuffer)
        guard let outputPixelBuffer = newPixelBuffer else {
            print("FrameMixer failed: Could not get pixel buffer from pool (\(self))")
            return nil
        }
        
        guard let desTexture = makeTextureFromCVPixelBuffer(outputPixelBuffer),
            let sourceTexture = makeTextureFromCVPixelBuffer(sourcePixelFrame) else {
                return nil
        }
        resizeTexture(sourceTexture: sourceTexture, desTexture: desTexture, targetSize: targetSize, resizeMode: resizeMode)
        return newPixelBuffer
    }
    
    @objc public func resizePixelBufferNeedCopy(sourcePixelFrame:CVPixelBuffer, targetSize:MTLSize, resizeMode: PixelResizeMode) -> CVPixelBuffer? {
        
        guard let sourceTexture = makeTextureFromCVPixelBuffer(sourcePixelFrame) else {
            print("FrameMixer resize convert to texture failed")
            return nil
        }
        guard let queue = self.commandQueue else {
            print("FrameMixer makeCommandBuffer failed")
            return nil
        }
        
        let device = queue.device;
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat, width: targetSize.width, height: targetSize.height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
        
        guard let desTexture = device.makeTexture(descriptor: descriptor) else {
            print("FrameMixer resize makeTexture failed")
            return nil
        }
        
        self.resizeTexture(sourceTexture:sourceTexture, desTexture: desTexture, targetSize: targetSize, resizeMode: resizeMode)
        
        // Copy texture to buffer
        let bytesPerPoint = CVPixelBufferGetBytesPerRow(sourcePixelFrame) / CVPixelBufferGetWidth(sourcePixelFrame)
        guard let commandBuffer = queue.makeCommandBuffer() ,
            let encoder = commandBuffer.makeBlitCommandEncoder(),
            let textureBuffer = device.makeBuffer(length: targetSize.width * targetSize.height * bytesPerPoint, options: .storageModeShared)else {
                return nil
        }
        encoder.copy(from: desTexture,
                     sourceSlice: 0,
                     sourceLevel: 0,
                     sourceOrigin: MTLOrigin.init(x: 0, y: 0, z: 0),
                     sourceSize: MTLSize.init(width: desTexture.width, height: desTexture.height, depth: 1),
                     to: textureBuffer,
                     destinationOffset: 0,
                     destinationBytesPerRow: targetSize.width * bytesPerPoint,
                     destinationBytesPerImage: textureBuffer.length)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Create CVPixelBuffer from buffer
        var resultBuffer: CVPixelBuffer?
        let pixelFormatType = CVPixelBufferGetPixelFormatType(sourcePixelFrame)
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                     desTexture.width,
                                     desTexture.height,
                                     pixelFormatType,
                                     textureBuffer.contents(),
                                     targetSize.width * bytesPerPoint,
                                     nil,
                                     nil,
                                     nil,
                                     &resultBuffer)
        let attributes : [NSObject:AnyObject] = [
            kCVPixelBufferIOSurfacePropertiesKey : NSDictionary.init(),
        ]
        // Copy for IOSuerface back off
        let buffer = deepCopyPixelBuffer(srcPixelBuffer: resultBuffer!,attributes:attributes as! [String : Any])
        return buffer
    }
    
    func resizeTexture(sourceTexture:MTLTexture, desTexture:MTLTexture, targetSize:MTLSize, resizeMode:PixelResizeMode) {
        guard let queue = self.commandQueue,
            let commandBuffer = queue.makeCommandBuffer() else {
                print("FrameMixer resizeTexture command buffer create failed")
                return
        }
        
        let device = queue.device;
        
        // Scale texture
        let sourceWidth = sourceTexture.width
        let sourceHeight = sourceTexture.height
        let widthRatio: Double = Double(targetSize.width) / Double(sourceWidth)
        let heightRatio: Double = Double(targetSize.height) / Double(sourceHeight)
        var scaleX: Double = 0;
        var scaleY: Double  = 0;
        var translateX: Double = 0;
        var translateY: Double = 0;
        if resizeMode == .scaleToFill {
            //ScaleFill
            scaleX = Double(targetSize.width) / Double(sourceWidth)
            scaleY = Double(targetSize.height) / Double(sourceHeight)
            
        } else if resizeMode == .scaleAspectFit {
            //AspectFit
            if heightRatio > widthRatio {
                scaleX = Double(targetSize.width) / Double(sourceWidth)
                scaleY = scaleX
                let currentHeight = Double(sourceHeight) * scaleY
                translateY = (Double(targetSize.height) - currentHeight) * 0.5
            } else {
                scaleY = Double(targetSize.height) / Double(sourceHeight)
                scaleX = scaleY
                let currentWidth = Double(sourceWidth) * scaleX
                translateX = (Double(targetSize.width) - currentWidth) * 0.5
            }
        } else if resizeMode == .scaleAspectFill {
            //AspectFill
            if heightRatio > widthRatio {
                scaleY = Double(targetSize.height) / Double(sourceHeight)
                scaleX = scaleY
                let currentWidth = Double(sourceWidth) * scaleX
                translateX = (Double(targetSize.width) - currentWidth) * 0.5
                
            } else {
                scaleX = Double(targetSize.width) / Double(sourceWidth)
                scaleY = scaleX
                let currentHeight = Double(sourceHeight) * scaleY
                translateY = (Double(targetSize.height) - currentHeight) * 0.5
            }
        }
        var transform = MPSScaleTransform(scaleX: scaleX, scaleY: scaleY, translateX: translateX, translateY: translateY)
        let scale = MPSImageBilinearScale.init(device: device)
        withUnsafePointer(to: &transform) { (transformPtr: UnsafePointer<MPSScaleTransform>) -> () in
            scale.scaleTransform = transformPtr
            scale.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: desTexture)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    struct MixerParameters {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var isMirror: Int
    }
    
    @objc public func mixFrame(background:CVPixelBuffer, window:CVPixelBuffer) -> CVPixelBuffer? {
        
        guard isPrepared,
            let outputPixelBufferPool = outputPixelBufferPool else {
                assertionFailure("FrameMixer invalid state: Not prepared")
                return nil
        }
        
        var newPixelBuffer:CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool, &newPixelBuffer)
        guard let outputPixelBuffer = newPixelBuffer else {
            print("FrameMixer failed: Could not get pixel buffer from pool (\(self))")
            return nil
        }
        
        guard let outputTexture = makeTextureFromCVPixelBuffer(outputPixelBuffer),
            let buffer1Texture = makeTextureFromCVPixelBuffer(background),
            let buffer2Texture = makeTextureFromCVPixelBuffer(window) else {
                return nil
        }
        
        let inFramePosition = SIMD2(Float(inFrame.origin.x) * Float(buffer1Texture.width), Float(inFrame.origin.y) * Float(buffer1Texture.height))
        let inFrameSize = SIMD2(Float(inFrame.size.width) * Float(buffer2Texture.width), Float(inFrame.size.height) * Float(buffer2Texture.height))
        
        var parameters = MixerParameters(position: inFramePosition, size: inFrameSize, isMirror: isMirror ? 1 : 0)
        
        
        guard let commandQueue = self.commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let commandEncoder = commandBuffer.makeComputeCommandEncoder(),
            let computePipelineState = self.computePipelineState else {
                print("FrameMixer failed to create Metal command encoder")
                if let textureCache = textureCache {
                    CVMetalTextureCacheFlush(textureCache, 0)
                }
                return nil
        }
        
        commandEncoder.label = "Mixer pip"
        commandEncoder.setComputePipelineState(computePipelineState)
        commandEncoder.setTexture(buffer1Texture, index: 0)
        commandEncoder.setTexture(buffer2Texture, index: 1)
        commandEncoder.setTexture(outputTexture, index: 2)
        commandEncoder.setBytes(UnsafeMutableRawPointer(&parameters), length: MemoryLayout<MixerParameters>.size, index: 0)
        
        let width = computePipelineState.threadExecutionWidth
        let height = computePipelineState.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
        let threadgroupsPerGrid = MTLSize(width: (buffer1Texture.width + width - 1) / width,
                                          height: (buffer1Texture.height + height - 1) / height,
                                          depth: 1)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        return outputPixelBuffer
    }
    
    private func makeTextureFromCVPixelBuffer(_ pixelBuffer:CVPixelBuffer) -> MTLTexture? {
        
        guard let textureCache = textureCache else {
            print("FrameMixer make buffer failed, texture cache is not exist")
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTextureOut:CVMetalTexture?
        
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTextureOut)
        assert(result == kCVReturnSuccess)
        
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("FrameMixer make buffer failed to create preview texture")
            
            CVMetalTextureCacheFlush(textureCache, 0)
            return nil
        }
        
        return texture
        
    }
}

extension FrameMixer {
    
    @objc public func calculateWindowPosition(backgroundViewFrame:CGRect, windowViewFrame:CGRect) -> CGRect{
        let normalizedTransform = CGAffineTransform(scaleX: 1.0 / backgroundViewFrame.width,
                                                    y: 1.0 / backgroundViewFrame.height)
        let frame = windowViewFrame.applying(normalizedTransform)
        return frame
    }
    
}

extension FrameMixer {
    func deepCopyPixelBuffer(srcPixelBuffer:CVPixelBuffer, attributes: [String: Any] = [:]) -> CVPixelBuffer? {
        let srcFlags: CVPixelBufferLockFlags = .readOnly
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(srcPixelBuffer, srcFlags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(srcPixelBuffer, srcFlags) }
        
        var combinedAttributes: [String: Any] = [:]
        
        // Copy attachment attributes.
        if let attachments = CVBufferGetAttachments(srcPixelBuffer, .shouldPropagate) as? [String: Any] {
            for (key, value) in attachments {
                combinedAttributes[key] = value
            }
        }
        
        // Add user attributes.
        combinedAttributes = combinedAttributes.merging(attributes) { $1 }
        
        var maybePixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         CVPixelBufferGetWidth(srcPixelBuffer),
                                         CVPixelBufferGetHeight(srcPixelBuffer),
                                         CVPixelBufferGetPixelFormatType(srcPixelBuffer),
                                         combinedAttributes as CFDictionary,
                                         &maybePixelBuffer)
        
        guard status == kCVReturnSuccess, let dstPixelBuffer = maybePixelBuffer else {
            return nil
        }
        
        let dstFlags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(dstPixelBuffer, dstFlags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(dstPixelBuffer, dstFlags) }
        
        for plane in 0...max(0, CVPixelBufferGetPlaneCount(srcPixelBuffer) - 1) {
            if let srcAddr = CVPixelBufferGetBaseAddressOfPlane(srcPixelBuffer, plane),
                let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dstPixelBuffer, plane) {
                let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(srcPixelBuffer, plane)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(dstPixelBuffer, plane)
                
                for h in 0..<CVPixelBufferGetHeightOfPlane(srcPixelBuffer, plane) {
                    let srcPtr = srcAddr.advanced(by: h*srcBytesPerRow)
                    let dstPtr = dstAddr.advanced(by: h*dstBytesPerRow)
                    dstPtr.copyMemory(from: srcPtr, byteCount: srcBytesPerRow)
                }
            }
        }
        return dstPixelBuffer
    }
}

