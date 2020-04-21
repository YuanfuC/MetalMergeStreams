//
//  FrameMixShaders.metal
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/18.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct MixParameters
{
    float2 position;
    float2 size;
};

constant sampler bilinearSampler(filter::linear,  coord::pixel, address::clamp_to_edge);

kernel void frameMixer(texture2d <half, access::read> rptTexture[[texture(0)]],
                       texture2d <half, access::sample> frontCameraTexture[[texture(1)]],
                       texture2d<half, access::write> outputTexture[[texture(2)]],
                       const device MixParameters &parameters [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    uint2 position = uint2(parameters.position);
    uint2 size = uint2(parameters.size);

    half4 output;
    
    if ((gid.x >= position.x) &&
        (gid.y >= position.y) &&
        (gid.x <= position.x + size.x) &&
        (gid.y <= position.y + size.y)) {
        
        float2 frontCameraSampleCoordinate = float2(size.x - ( gid.x - position.x), gid.y - position.y) *
        float2(frontCameraTexture.get_width(), frontCameraTexture.get_height()) / float2(size);
        output =  frontCameraTexture.sample(bilinearSampler, frontCameraSampleCoordinate);
    } else {
        output = rptTexture.read(gid);
    }
    
    outputTexture.write(output, gid);
}
