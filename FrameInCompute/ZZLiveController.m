//
//  ZZLiveController.m
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/30.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

#import "ZZLiveController.h"

@interface ZZLiveController()<LFLiveSessionDelegate>

@property(nonatomic, strong) LFLiveSession *session;
@property(nonatomic, strong)  dispatch_queue_t pushQueue;

@end

@implementation ZZLiveController

- (instancetype)initWithSession:(LFLiveSession *)session {
    if (self = [super init]) {
        _session = session;
    }
    return self;
}

- (void)startLiveWithURL:(NSString *)URLString {
    
    if (_isLiving == YES) {
        return;
    }
    
    LFLiveStreamInfo *stream = [LFLiveStreamInfo new];
    stream.url = URLString;
    [self.session startLive:stream];
    _isLiving = YES;
}

- (void)stopLive {
    if (_isLiving == NO) {
        return;
    }
    
    [self.session stopLive];
    _isLiving = NO;
}

- (void)pushFrame:(CVPixelBufferRef)frame {
    CVPixelBufferRetain(frame);
    dispatch_async(self.pushQueue, ^{
        [self.session pushVideo:frame];
        CVPixelBufferRelease(frame);
    });
}

- (void)configDeviceRunning:(BOOL)camera microRunning:(BOOL)microphone {
    [self.session configDeviceRunningForCamera:camera microphone:microphone];
    if (camera || microphone) {
        self.session.running = true;
    } else {
        self.session.running = false;
    }
}


#pragma mark - Session delegate

/** live status changed will callback */
- (void)liveSession:(nullable LFLiveSession *)session liveStateDidChange:(LFLiveState)state {
    NSLog(@"Session state change :%lu", (unsigned long)state);
    if ([self.sessionDelegate performSelector:@selector(liveSession:liveStateDidChange:)]) {
        [self.sessionDelegate liveSession:session liveStateDidChange:state];
    }
    switch (state) {
        case LFLiveReady:
            NSLog( @"未连接");
            break;
        case LFLivePending:
            NSLog( @"连接中");
            break;
        case LFLiveStart:
            NSLog( @"已连接");
            break;
        case LFLiveError:
            NSLog( @"连接错误");
            break;
        case LFLiveStop:
            NSLog( @"未连接");
            break;
        default:
            break;
    }
}

/** live debug info callback */
- (void)liveSession:(nullable LFLiveSession *)session debugInfo:(nullable LFLiveDebug *)debugInfo {
    NSLog(@"Session debug info: %@", debugInfo);
    if ([self.sessionDelegate performSelector:@selector(liveSession:debugInfo:)]) {
        [self.sessionDelegate liveSession:session debugInfo:debugInfo];
    }
    
}
/** callback socket errorcode */
- (void)liveSession:(nullable LFLiveSession *)session errorCode:(LFLiveSocketErrorCode)errorCode {
    NSLog(@"Session error error code: %lu", (unsigned long)errorCode);
    if ([self.sessionDelegate performSelector:@selector(liveSession:errorCode:)]) {
        [self.sessionDelegate liveSession:session errorCode:errorCode];
    }
}

#pragma mark - Getter

- (LFLiveSession *)session {
    if (!_session) {
        LFLiveAudioConfiguration *audioConfiguration = [LFLiveAudioConfiguration new];
        audioConfiguration.numberOfChannels = 2;
        audioConfiguration.audioBitrate = LFLiveAudioBitRate_128Kbps;
        audioConfiguration.audioSampleRate = LFLiveAudioSampleRate_44100Hz;
        
        LFLiveVideoConfiguration *videoConfiguration = [LFLiveVideoConfiguration new];
        videoConfiguration.videoSize = CGSizeMake(1280, 720);
        videoConfiguration.videoBitRate = 800 * 1024;
        videoConfiguration.videoMaxBitRate = 1000 * 1024;
        videoConfiguration.videoMinBitRate = 500 * 1024;
        videoConfiguration.videoFrameRate = 30;
        videoConfiguration.videoMaxKeyframeInterval = 30;
        videoConfiguration.sessionPreset = LFCaptureSessionPreset720x1280;
        
        _session = [[LFLiveSession alloc] initWithAudioConfiguration:audioConfiguration videoConfiguration:videoConfiguration];
        _session.delegate = self;
    }
    return _session;
}

- (dispatch_queue_t)pushQueue {
    if (!_pushQueue) {
        _pushQueue = dispatch_queue_create("Push-queue", DISPATCH_QUEUE_SERIAL);
    }
    return _pushQueue;
}


@end
