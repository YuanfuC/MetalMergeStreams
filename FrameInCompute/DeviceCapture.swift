//
//  DeviceCapture.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/22.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import Foundation
import AVFoundation

@objc public protocol CaptureDataOutputDelegate:AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate{}

@objc public class DeviceCapture: NSObject {
    
    @objc public let cameraOutput = AVCaptureVideoDataOutput()
    @objc public let microphoneOutput = AVCaptureAudioDataOutput()
    private let captureSession = AVCaptureSession()
    private var microphoneInput: AVCaptureDeviceInput?
    private var videoInput: AVCaptureInput?
    
    @objc public func setSampleBufferDelegate(_ sampleBufferDelegate: CaptureDataOutputDelegate, queue sampleBufferCallbackQueue: DispatchQueue?) {
        cameraOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferCallbackQueue)
        microphoneOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferCallbackQueue)
    }
    
    @objc public func launchCamera(for mediaType: AVMediaType?, whichCamera: AVCaptureDevice.Position, orientation:AVCaptureVideoOrientation) -> AVCaptureSession? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("DeviceCapture Camera device is not eixst")
            return nil
        }
        
        videoInput = try? AVCaptureDeviceInput(device: device)
        guard let videoDeviceInput = videoInput else {
            print("DeviceCapture create video input failed")
            return nil
        }
        
        captureSession.beginConfiguration()
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
        } else {
            print("DeviceCapture can't add video device input to the session.")
            captureSession.commitConfiguration()
            return nil
        }
        
        captureSession.sessionPreset = .hd1280x720
        device.supportsSessionPreset(.hd1280x720)
        captureSession.commitConfiguration()
        cameraOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        
        if captureSession.canAddOutput(cameraOutput) {
            captureSession.addOutput(cameraOutput)
            let conection = cameraOutput.connection(with: .video)
            conection?.videoOrientation = .landscapeRight
        }else {
            print("DeviceCapture can't add video output to the session.")
            captureSession.commitConfiguration()
            return nil
        }
        
        return captureSession;
    }
    
    @objc public func launchMicrophone() ->AVCaptureSession? {
        captureSession.beginConfiguration()
        
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("DeviceCapture can't find the microphone")
            return nil
        }
        
        do {
            microphoneInput = try AVCaptureDeviceInput.init(device: audioDevice)
            
            guard let input = microphoneInput,
                captureSession.canAddInput(input) else {
                    print("DeviceCapture could not add microphone device input")
                    return nil
            }
            captureSession.addInput(input)
        } catch {
            print("DeviceCapture could not create microphone input: \(error)")
            return nil
        }
        
        guard captureSession.canAddOutput(microphoneOutput) else {
            print("Could not add the back microphone audio data output")
            return nil
        }
        
        captureSession.addOutput(microphoneOutput)
        captureSession.commitConfiguration()
        return captureSession
    }
    
    @objc public func switchCamera(for mediaType: AVMediaType?, position: AVCaptureDevice.Position) -> Void {
        self.captureSession.beginConfiguration()
        if let videoInput = self.videoInput {
            self.captureSession.removeInput(videoInput)
        }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: mediaType, position: position),
            let  videoDeviceInput = try? AVCaptureDeviceInput(device: device) else {
                print("DeviceCapture Switch Camera device is not eixst")
                self.captureSession.commitConfiguration()
                return
        }
        self.videoInput = videoDeviceInput
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
        } else {
            print("DeviceCapture Swtich can't add video device input to the session.")
        }
        captureSession.commitConfiguration()
    }
    
    deinit {
        print("DeviceCapture dealloc")
    }    
}
