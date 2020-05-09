# Metal merge streams 
Use `Metal` to merge CVPixelBuffers and resize CVPixelBuffer in hight performance.
## Merge frames
* Time consuming 0.2 ~ 1.5 ms can make sure the living real-time.
* Inputs are tow CVPixelBuffers. CVPixelBuffer-A (from front camera) and CVPixelBuffer-B (from video 'rtpVideo.mp4'). Output is new CVPixelBuffers.
*  Upload pixel buffer as MTLTexture and in-frame location to GPU
*  `MTLComputeCommandEncoder` compute new texture 


## Resize frame

* Input is CVPixelBuffers. Output is new CVPixelBuffers.
*  `MPSImageBilinearScale` to resize pixel buffer, support mode `ScaleToFill`,`ScaleAspectFit`,`ScaleAspectFill`

### Tow method to create new pixel buufer.
#### With pixel buffer pool
* Time consuming 1 ~ 2 ms.
* Create output CVPixelBuffer from Pixel CVPixelBufferPool
* Create a new MTLTexture from output CVPixelBuffer
* Compute and wait for completion
* Return the result CVPixelBuffer which is IOSurface-backed

#### Without pixel buffer pool
* Time consuming 6 ~ 7 ms.
* Create a texture from `MTLDevice`
* Compute and wait for completion
* `MTLBlitCommandEncoder` copy computed texture from GPU to CPU as `MTLBuffer`
* Create output CVPixelBuffer from `MTLBuffer`, but the output CVPixelBuffer is not IOSurface-backed
* Deep copy output CVPixelBuffer and config the copied output is IOSurface-backed


