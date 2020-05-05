//
//  ZZLiveController.h
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/30.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "LFLiveKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZZLiveController : NSObject

@property(nonatomic, assign, readonly) BOOL isLiving;

@property(nonatomic, weak) id <LFLiveSessionDelegate> sessionDelegate;

- (void)startLiveWithURL:(NSString *)urlString;

- (void)stopLive;

- (void)pushFrame:(CVPixelBufferRef)frame;

- (void)configDeviceRunning:(BOOL)camera microRunning:(BOOL)microphone;

@end

NS_ASSUME_NONNULL_END
