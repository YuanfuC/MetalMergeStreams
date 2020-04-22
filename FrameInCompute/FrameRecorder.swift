//
//  FrameRecorder.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/22.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import Foundation
import AVFoundation

@objc class FrameRecorder: NSObject {
    
    var adaptorFormatType = kCVPixelFormatType_32BGRA
    var videoWriter:AVAssetWriter? = nil
    var videoInput:AVAssetWriterInput? = nil
    var audioInput: AVAssetWriterInput?
    var videoInputAdaptor:AVAssetWriterInputPixelBufferAdaptor? = nil
    var isRecording:Bool = false
    private var videoSettings: [String: Any]
    private var audioSettings: [String: Any]
    
    init(videoSettings:[String:Any], audioSettings:[String:Any]) {
        self.videoSettings = videoSettings
        self.audioSettings = audioSettings
        super.init()
    }
    
    func startRecording(){
        let outputFileName = NSUUID().uuidString
        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("mp4")
        videoWriter = try? AVAssetWriter(url: outputFileURL, fileType: .mp4)
        guard let assetWriter = videoWriter else {
            print("FrameRecorder video wirter create failed")
            return
        }
        
        let videoInput = AVAssetWriterInput.init(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else {
            print("FrameRecorder video writer can't add video input")
            return
        }
        self.videoInput = videoInput
        
        let audioInput = AVAssetWriterInput.init(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        } else {
            print("FrameRecorder video writer can't add audio input")
            return
        }
        self.audioInput = audioInput
        
        configWirterInputPixelBufferAdaptor(width: videoSettings[AVVideoWidthKey] as! NSNumber,
                                            height: videoSettings[AVVideoHeightKey] as! NSNumber)
        isRecording = true
    }
    
    func stopRecording(completion: @escaping (URL) -> Void) {
        guard let assetWriter = videoWriter else {
            return
        }
        
        self.isRecording = false
        self.videoWriter = nil
        assetWriter.finishWriting {
            completion(assetWriter.outputURL)
        }
    }
    
    func recordVideo(sampleBuffer: CMSampleBuffer) {
        guard isRecording,
            let assetWriter = videoWriter else {
                return
        }
        
        if assetWriter.status == .unknown {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        } else if assetWriter.status == .writing {
            if let input = videoInput,
                input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            } else {
                print("FrameRecorder video input is node ready for media data")
            }
        }
    }
    
    func recordVideo(pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        guard isRecording,
            let assetWriter = videoWriter else {
                return
        }
        
        if assetWriter.status == .unknown {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime:presentationTime)
        } else if assetWriter.status == .writing {
            if let adaptor = videoInputAdaptor,
                adaptor.assetWriterInput.isReadyForMoreMediaData {
                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            } else {
                print("FrameRecorder adaptor's input is node ready for media data")
            }
        }
    }
    
    func recordAudio(sampleBuffer: CMSampleBuffer) {
        
        guard isRecording,
            let assetWriter = videoWriter,
            assetWriter.status == .writing,
            let input = audioInput else {
                return
        }
        
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
            
        } else {
            print("FrameRecorder adaptor's input is node ready for media data")
            
        }
    }
    
    func configWirterInputPixelBufferAdaptor(width:NSNumber, height:NSNumber){
        
        var videoWriterInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        let sourcePixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: self.adaptorFormatType,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
            ] as [String : Any]
        
        videoWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        guard let adaptor = videoWriterInputPixelBufferAdaptor else {
            print("FrameRecorder adaptor create failed")
            assert(false)
            return
        }
        videoInputAdaptor = adaptor
    }
}
