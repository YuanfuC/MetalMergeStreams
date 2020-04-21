//
//  FrameMixer.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/18.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import CoreMedia
import MetalKit

class FrameMixer: NSObject {
    
    /// A normalized CGRect representing the position and size of the PiP in relation to the full screen video preview
    var inFrame = CGRect.zero
    
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
    var isPrepared:Bool = false
    
    override init() {
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
    
    func prepare(with videoFormatDescription:CMFormatDescription, outputRetainedBufferCountHint: Int) {
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
            assertionFailure("Unable to allocate video mixer texture cache")
        } else {
            textureCache = metalTextureCache
        }
        
        isPrepared = true
    }
    
    struct MixerParameters {
        var pipPosition: SIMD2<Float>
        var pipSize: SIMD2<Float>
    }
    
    func mixFrame(_ buffer1:CVPixelBuffer, _ buffer2:CVPixelBuffer) ->CVPixelBuffer? {
        
        guard isPrepared,
            let outputPixelBufferPool = outputPixelBufferPool else {
                assertionFailure("Invalid state: Not prepared")
                return nil
        }
        
        var newPixelBuffer:CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool, &newPixelBuffer)
        guard let outputPixelBuffer = newPixelBuffer else {
            print("Mix failed: Could not get pixel buffer from pool (\(self))")
            return nil
        }
        
        guard let outputTexture = makeTextureFromCVPixelBuffer(outputPixelBuffer),
            let buffer1Texture = makeTextureFromCVPixelBuffer(buffer1),
            let buffer2Texture = makeTextureFromCVPixelBuffer(buffer2) else {
                return nil
        }
        
        let inFramePosition = SIMD2(Float(inFrame.origin.x) * Float(buffer1Texture.width), Float(inFrame.origin.y) * Float(buffer1Texture.height))
        let inFrameSize = SIMD2(Float(inFrame.size.width) * Float(buffer2Texture.width), Float(inFrame.size.height) * Float(buffer2Texture.height))
        var parameters = MixerParameters(pipPosition: inFramePosition, pipSize: inFrameSize)
        
        
        guard let commandQueue = self.commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let commandEncoder = commandBuffer.makeComputeCommandEncoder(),
            let computePipelineState = self.computePipelineState else {
                print("Mix failed to create Metal command encoder")
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
            print("Make buffer failed, texture cache is not exist")
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTextureOut:CVMetalTexture?
        
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTextureOut)
        assert(result == kCVReturnSuccess)
        
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Make buffer failed to create preview texture")
            
            CVMetalTextureCacheFlush(textureCache, 0)
            return nil
        }
        
        return texture
        
    }
}
