//
//  MixerUtilities.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/20.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import Foundation
import AVFoundation

func allocOutputBufferPool(with inputDescription:CMFormatDescription, outputRetainedBufferCountHint: Int, dimension:CMVideoDimensions) -> (bufferPool:CVPixelBufferPool?, colorSpace:CGColorSpace?, outputDescription:CMFormatDescription?) {
    let inputMediaSubType = CMFormatDescriptionGetMediaSubType(inputDescription)
    if inputMediaSubType != kCVPixelFormatType_32BGRA {
        assertionFailure("Pixel type \(inputMediaSubType) is invalid")
        return (nil, nil, nil)
    }
    
    var pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: UInt(inputMediaSubType),
        kCVPixelBufferWidthKey as String: Int(dimension.width),
        kCVPixelBufferHeightKey as String: Int(dimension.height),
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ]
    
    var cgColorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
    
    if let inputFormatDescriptionExtension = CMFormatDescriptionGetExtensions(inputDescription) as Dictionary? {
        let colorPrimaries = inputFormatDescriptionExtension[kCVImageBufferColorPrimariesKey]
        if let colorPrimaries = colorPrimaries {
            var colorSpaceProperties: [String: AnyObject] = [kCVImageBufferColorPrimariesKey as String: colorPrimaries]
            
            if let yCbCrMatrix = inputFormatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                colorSpaceProperties[kCVImageBufferYCbCrMatrixKey as String] = yCbCrMatrix
            }
            
            if let transferFunction = inputFormatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                colorSpaceProperties[kCVImageBufferTransferFunctionKey as String] = transferFunction
            }
            
            pixelBufferAttributes[kCVBufferPropagatedAttachmentsKey as String] = colorSpaceProperties
        }
        
        if let cvColorspace = inputFormatDescriptionExtension[kCVImageBufferCGColorSpaceKey],
            CFGetTypeID(cvColorspace) == CGColorSpace.typeID {
            cgColorSpace = (cvColorspace as! CGColorSpace)
        } else if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_P3_D65 as String) {
            cgColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        }
    }
    
    let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: outputRetainedBufferCountHint]
    var cvPixelBufferPool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as NSDictionary?, pixelBufferAttributes as NSDictionary?, &cvPixelBufferPool)
    guard let pixelBufferPool = cvPixelBufferPool else {
        assertionFailure("Allocation failure: Could not allocate pixel buffer pool.")
        return (nil, nil, nil)
    }
    preallocateBuffers(pool: pixelBufferPool, allocationThreshold: outputRetainedBufferCountHint)
    
    var pixelBuffer: CVPixelBuffer?
    var outputFormatDescription: CMFormatDescription?
    let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: outputRetainedBufferCountHint] as NSDictionary
    CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pixelBufferPool, auxAttributes, &pixelBuffer)
    if let pixelBuffer = pixelBuffer {
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &outputFormatDescription)
    }
    pixelBuffer = nil
    
    return (pixelBufferPool, cgColorSpace, outputFormatDescription)
}

func allocOutputBufferPool(with inputDescription:CMFormatDescription, outputRetainedBufferCountHint: Int) -> (bufferPool:CVPixelBufferPool?, colorSpace:CGColorSpace?, outputDescription:CMFormatDescription?) {
    let inputDimensions = CMVideoFormatDescriptionGetDimensions(inputDescription)
    return allocOutputBufferPool(with: inputDescription, outputRetainedBufferCountHint: outputRetainedBufferCountHint, dimension: inputDimensions)
}

private func preallocateBuffers(pool: CVPixelBufferPool, allocationThreshold: Int) {
    var pixelBuffers = [CVPixelBuffer]()
    var error: CVReturn = kCVReturnSuccess
    let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: allocationThreshold] as NSDictionary
    var pixelBuffer: CVPixelBuffer?
    while error == kCVReturnSuccess {
        error = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer)
        if let pixelBuffer = pixelBuffer {
            pixelBuffers.append(pixelBuffer)
        }
        pixelBuffer = nil
    }
    pixelBuffers.removeAll()
}
