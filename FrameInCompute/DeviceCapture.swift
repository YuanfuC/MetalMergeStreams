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
    private var videoDevice:AVCaptureDevice?
    private var resolution: AVCaptureSession.Preset = .hd1280x720
    
    @objc public func setSampleBufferDelegate(_ sampleBufferDelegate: CaptureDataOutputDelegate, queue sampleBufferCallbackQueue: DispatchQueue?) {
        cameraOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferCallbackQueue)
        microphoneOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferCallbackQueue)
    }
    
    @objc public func setupResolution(preset: AVCaptureSession.Preset) {
        self.resolution = preset
        captureSession.beginConfiguration()
        
        if let device = videoDevice,
            captureSession.canSetSessionPreset(preset) && device.supportsSessionPreset(preset) {
            captureSession.sessionPreset = preset
        } else {
            assertionFailure("Session preset can't be set")
        }
        captureSession.commitConfiguration()
    }
    
    @objc public func launchCamera(for mediaType: AVMediaType, whichCamera: AVCaptureDevice.Position, orientation:AVCaptureVideoOrientation, preset:AVCaptureSession.Preset) -> AVCaptureSession? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: mediaType, position: whichCamera) else {
            print("DeviceCapture Camera device is not eixst")
            return nil
        }
        
        videoDevice = device
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
        
        cameraOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        
        if captureSession.canAddOutput(cameraOutput) {
            captureSession.addOutput(cameraOutput)
            let conection = cameraOutput.connection(with: mediaType)
            conection?.videoOrientation = orientation
        }else {
            print("DeviceCapture can't add video output to the session.")
            captureSession.commitConfiguration()
            return nil
        }
        captureSession.commitConfiguration()
        setupResolution(preset: preset)
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
    
    @objc public func switchCamera(for mediaType: AVMediaType, position: AVCaptureDevice.Position, orientation:AVCaptureVideoOrientation) -> Void {
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
            let conection = cameraOutput.connection(with: mediaType)
            conection?.videoOrientation = orientation
        } else {
            print("DeviceCapture Swtich can't add video device input to the session.")
        }
        captureSession.commitConfiguration()
        setupResolution(preset: self.resolution)
    }
    
    deinit {
        print("DeviceCapture dealloc")
    }
}


