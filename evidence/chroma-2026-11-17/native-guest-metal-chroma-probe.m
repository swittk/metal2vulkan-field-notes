// Guest-side diagnostic. Unchanged AVFoundation 4K HEVC Main10 decode, actual
// CoreVideo IOSurface, single-plane and converted YCbCr Metal texture reads.
// Source/codec/settings are unchanged. The guest itself judges its GPU reads.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreVideo/CVPixelBufferIOSurface.h>
#import <IOSurface/IOSurface.h>
#import <CoreMedia/CoreMedia.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

enum { GRID=16, MAX_FRAMES=20 };
static NSString *shader =
@"#include <metal_stdlib>\n"
@"using namespace metal;\n"
@"kernel void read_planes(texture2d<float,access::read> luma [[texture(0)]],\n"
@"texture2d<float,access::read> chroma [[texture(1)]],\n"
@"device float4* out [[buffer(0)]],\n"
@"constant uint2& dims [[buffer(1)]],\n"
@"uint2 gid [[thread_position_in_grid]]) {\n"
@"  uint2 at = gid*16;\n"
@"  if (at.x>=dims.x || at.y>=dims.y) return;\n"
@"  uint cols=(dims.x+15)/16;\n"
@"  uint index=gid.y*cols+gid.x;\n"
@"  float Y=luma.read(at).r;\n"
@"  float2 UV=chroma.read(at/2).rg;\n"
@"  float vY=(Y*65535.0f-64.0f*64.0f)/(876.0f*64.0f);\n"
@"  float cb=(UV.x*65535.0f-512.0f*64.0f)/(896.0f*64.0f);\n"
@"  float cr=(UV.y*65535.0f-512.0f*64.0f)/(896.0f*64.0f);\n"
@"  float3 RGB=clamp(float3(vY+1.5748f*cr,vY-0.187324f*cb-0.468124f*cr,vY+1.8556f*cb),0.0f,1.0f);\n"
@"  out[index*2]=float4(Y,UV.x,UV.y,0);\n"
@"  out[index*2+1]=float4(RGB,0);\n"
@"}\n";

static NSString *fourcc(OSType f) {
 char s[5]={(char)(f>>24),(char)(f>>16),(char)(f>>8),(char)f,0};
 return [NSString stringWithUTF8String:s];
}
static float clip(float v) {return fminf(1.f,fmaxf(0.f,v));}
static int inspectFrame(id<MTLDevice> gpu,id<MTLComputePipelineState> pipe,CVMetalTextureCacheRef texcache,CVPixelBufferRef pb,int n) {
 size_t W=CVPixelBufferGetWidth(pb),H=CVPixelBufferGetHeight(pb);
 OSType pixel=CVPixelBufferGetPixelFormatType(pb);
 if(pixel!=kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange &&
    pixel!=kCVPixelFormatType_420YpCbCr10BiPlanarFullRange) {
  printf("INVALID_PIXEL_FORMAT frame=%d fourcc=%s\n",n,fourcc(pixel).UTF8String);
  return 3;
 }
 const size_t cols=(W+15)/16,rows=(H+15)/16;
 CVMetalTextureRef yCV=NULL,uvCV=NULL;
 CVReturn yst=CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,texcache,pb,NULL,
                   MTLPixelFormatR16Unorm,W,H,0,&yCV);
 CVReturn ust=CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,texcache,pb,NULL,
                   MTLPixelFormatRG16Unorm,W/2,H/2,1,&uvCV);
 printf("FRAME_META frame=%d format=%s W=%zu H=%zu planes=%zu pitchY=%zu pitchUV=%zu VT_Y=%d VT_UV=%d\n",
   n,fourcc(pixel).UTF8String,W,H,CVPixelBufferGetPlaneCount(pb),
   CVPixelBufferGetBytesPerRowOfPlane(pb,0),CVPixelBufferGetBytesPerRowOfPlane(pb,1),
   (int)yst,(int)ust);
 fflush(stdout);
 if(yst!=kCVReturnSuccess||ust!=kCVReturnSuccess) {
  if(yCV)CFRelease(yCV);if(uvCV)CFRelease(uvCV);
  return 4;
 }
 id<MTLTexture> ytex=CVMetalTextureGetTexture(yCV);
 id<MTLTexture> uvtex=CVMetalTextureGetTexture(uvCV);
 BOOL directUV = getenv("REIMS_UV_MODE") && strncmp(getenv("REIMS_UV_MODE"), "direct", 6) == 0;
 if (directUV) {
   IOSurfaceRef surf=CVPixelBufferGetIOSurface(pb);
   MTLTextureDescriptor *uvdesc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG16Unorm
                            width:W/2 height:H/2 mipmapped:NO];
   const char *mode=getenv("REIMS_UV_MODE");
   uvdesc.storageMode=uvtex.storageMode;
   uvdesc.usage=uvtex.usage;
   uvdesc.cpuCacheMode=uvtex.cpuCacheMode;
   if(mode && strstr(mode,"readonly"))uvdesc.usage=MTLTextureUsageShaderRead;
   if(mode && strstr(mode,"private"))uvdesc.storageMode=MTLStorageModePrivate;
   if(mode && strstr(mode,"shared"))uvdesc.storageMode=MTLStorageModeShared;
   id<MTLTexture> candidate=surf?[gpu newTextureWithDescriptor:uvdesc iosurface:surf plane:1]:nil;
   if (!candidate) {printf("DIRECT_UV_TEXTURE_UNAVAILABLE frame=%d\n", n);CFRelease(yCV);CFRelease(uvCV);return 7;}
   printf("DIRECT_UV_TEXTURE frame=%d descriptor_storage=%lu usage=%lu bpr=%zu\n",n,(unsigned long)uvdesc.storageMode,(unsigned long)uvdesc.usage,CVPixelBufferGetBytesPerRowOfPlane(pb,1));
   uvtex=candidate;
 }
 NSUInteger bytes=cols*rows*2*sizeof(simd_float4);
 id<MTLBuffer> output=[gpu newBufferWithLength:bytes options:MTLResourceStorageModeShared];
 id<MTLCommandQueue> queue=[gpu newCommandQueue];
 if(getenv("REIMS_UV_MODE") && (strcmp(getenv("REIMS_UV_MODE"),"copy-texture")==0 || strcmp(getenv("REIMS_UV_MODE"),"copy-then-original")==0)){
   MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG16Unorm
                 width:W/2 height:H/2 mipmapped:NO];
   desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
   desc.storageMode=MTLStorageModePrivate;
   id<MTLTexture> copied=[gpu newTextureWithDescriptor:desc];
   if(!copied){printf("COPY_UV_TEXTURE_ALLOC_FAILED frame=%d\n",n);CFRelease(yCV);CFRelease(uvCV);return 9;}
   id<MTLCommandBuffer> move=[queue commandBuffer];
   id<MTLBlitCommandEncoder> blit=[move blitCommandEncoder];
   [blit copyFromTexture:uvtex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(W/2,H/2,1) toTexture:copied destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
   [blit endEncoding];[move commit];[move waitUntilCompleted];
   if(move.status!=MTLCommandBufferStatusCompleted){
      printf("COPY_UV_TEXTURE_BLIT_FAILED frame=%d err=%s\n",n,move.error.description.UTF8String);
      CFRelease(yCV);CFRelease(uvCV);return 9;
   }
   if(n==0)printf("COPY_UV_TEXTURE_GPU_ONLY_READY %zux%zu\n",W/2,H/2);
   if(strcmp(getenv("REIMS_UV_MODE"),"copy-texture")==0)uvtex=copied;
 }
 if(getenv("REIMS_PREBLIT")) {
   size_t row=(W/2)*4;
   id<MTLBuffer> pre=[gpu newBufferWithLength:row*(H/2) options:MTLResourceStorageModeShared];
   id<MTLCommandBuffer> preCB=[queue commandBuffer];
   id<MTLBlitCommandEncoder> preBlit=[preCB blitCommandEncoder];
   [preBlit copyFromTexture:uvtex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
             sourceSize:MTLSizeMake(W/2,H/2,1) toBuffer:pre destinationOffset:0
             destinationBytesPerRow:row destinationBytesPerImage:row*(H/2)];
   [preBlit endEncoding];[preCB commit];[preCB waitUntilCompleted];
   if(preCB.status!=MTLCommandBufferStatusCompleted){
      printf("PREBLIT_FAILED frame=%d status=%lu\n",n,(unsigned long)preCB.status);
      CFRelease(yCV);CFRelease(uvCV);return 9;
   }
   if(n==0)printf("PREBLIT_COMPLETED_BEFORE_SHADER\n");
 }
 id<MTLCommandBuffer> cmd=[queue commandBuffer];
 id<MTLComputeCommandEncoder> enc=[cmd computeCommandEncoder];
 simd_uint2 dims={(unsigned)W,(unsigned)H};
 [enc setComputePipelineState:pipe];
 [enc setTexture:ytex atIndex:0];
 [enc setTexture:uvtex atIndex:1];
 [enc setBuffer:output offset:0 atIndex:0];
 [enc setBytes:&dims length:sizeof(dims) atIndex:1];
 [enc dispatchThreads:MTLSizeMake(cols,rows,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
 [enc endEncoding];[cmd commit];[cmd waitUntilCompleted];
 if(cmd.status!=MTLCommandBufferStatusCompleted) {
  printf("FRAME_GPU_ERROR %d %s\n",n,cmd.error.description.UTF8String);
  CFRelease(yCV);CFRelease(uvCV);return 5;
 }
 // Independent Metal blit reads the raw RG16Unorm texels without shader sampling.
 size_t chromaRow=(W/2)*4;
 id<MTLBuffer> chromaBlit=[gpu newBufferWithLength:chromaRow*(H/2) options:MTLResourceStorageModeShared];
 id<MTLCommandBuffer> blitCmd=[queue commandBuffer];
 id<MTLBlitCommandEncoder> be=[blitCmd blitCommandEncoder];
 [be copyFromTexture:uvtex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(W/2,H/2,1) toBuffer:chromaBlit destinationOffset:0
        destinationBytesPerRow:chromaRow destinationBytesPerImage:chromaRow*(H/2)];
 [be endEncoding];[blitCmd commit];[blitCmd waitUntilCompleted];
 if(blitCmd.status!=MTLCommandBufferStatusCompleted) {
   printf("FRAME_CHROMA_BLIT_FAILED frame=%d status=%lu err=%s\n",n,(unsigned long)blitCmd.status,blitCmd.error.description.UTF8String);
   CFRelease(yCV);CFRelease(uvCV);return 8;
 }
 CVReturn lock=CVPixelBufferLockBaseAddress(pb,kCVPixelBufferLock_ReadOnly);
 if(lock!=kCVReturnSuccess){printf("FRAME_LOCK_ERROR %d %d\n",n,(int)lock);CFRelease(yCV);CFRelease(uvCV);return 6;}
 const uint8_t *baseY=CVPixelBufferGetBaseAddressOfPlane(pb,0);
 const uint8_t *baseUV=CVPixelBufferGetBaseAddressOfPlane(pb,1);
 size_t sy=CVPixelBufferGetBytesPerRowOfPlane(pb,0);
 size_t suv=CVPixelBufferGetBytesPerRowOfPlane(pb,1);
 const simd_float4 *out=output.contents;
 size_t planeBad=0, badY=0, badU=0, badV=0, badBlitU=0, badBlitV=0, fusedGreen=0, expectedGreen=0, fusedDiff=0, sample=0;
 unsigned minX=UINT32_MAX,minY=UINT32_MAX,maxX=0,maxY=0;
 double abs_err=0, max_err=0;unsigned firstBadX=0,firstBadY=0;
 for(size_t gy=0;gy<rows;gy++)for(size_t gx=0;gx<cols;gx++) {
  size_t x=gx*GRID,y=gy*GRID,idx=(gy*cols+gx)*2;
  if(x>=W||y>=H)continue;
  const uint16_t *Y=(const uint16_t *)(baseY+y*sy+x*2);
  const uint16_t *U=(const uint16_t *)(baseUV+(y/2)*suv+(x/2)*4);
  const uint16_t *B=(const uint16_t *)((const uint8_t *)chromaBlit.contents+(y/2)*chromaRow+(x/2)*4);
  if(U[0]!=B[0])badBlitU++;
  if(U[1]!=B[1])badBlitV++;
  float yp=(float)Y[0]/65535.f,up=(float)U[0]/65535.f,vp=(float)U[1]/65535.f;
  simd_float4 measured=out[idx],rgb=out[idx+1];
  float errY=fabsf(yp-measured.x),errU=fabsf(up-measured.y),errV=fabsf(vp-measured.z);
  float err=fmaxf(errY,fmaxf(errU,errV));
  if(errY>0.00012f)badY++;
  if(errU>0.00012f)badU++;
  if(errV>0.00012f)badV++;
  if(err>0.00012f){
    planeBad++;
    if(planeBad==1){firstBadX=(unsigned)x;firstBadY=(unsigned)y;}
    if(x<minX)minX=(unsigned)x;if(y<minY)minY=(unsigned)y;
    if(x>maxX)maxX=(unsigned)x;if(y>maxY)maxY=(unsigned)y;
    if(n==0 && planeBad<=24){
      printf("BAD_SAMPLE x=%zu y=%zu Y_CPU=%u Y_GPU=%.7f U_CPU=%u U_GPU=%.7f V_CPU=%u V_GPU=%.7f\n",
       x,y,(unsigned)Y[0],measured.x,(unsigned)U[0],measured.y,(unsigned)U[1],measured.z);
    }
  }
  if(err>max_err)max_err=err;
  // SMPTE BT.709 studio-range x420 codes in upper ten bits of P010.
  float yv=((float)(Y[0]>>6)-64.f)/876.f;
  float cb=((float)(U[0]>>6)-512.f)/896.f;
  float cr=((float)(U[1]>>6)-512.f)/896.f;
  float expR=clip(yv+1.5748f*cr);
  float expG=clip(yv-0.187324f*cb-0.468124f*cr);
  float expB=clip(yv+1.8556f*cb);
  float dr=fabsf(rgb.x-expR),dg=fabsf(rgb.y-expG),db=fabsf(rgb.z-expB);
  float colorErr=fmaxf(dr,fmaxf(dg,db));
  abs_err+=dr+dg+db;
  if(colorErr>0.08f)fusedDiff++;
  if(rgb.y>0.67f&&rgb.x<0.18f&&rgb.z<0.25f)fusedGreen++;
  if(expG>0.67f&&expR<0.18f&&expB<0.25f)expectedGreen++;
  sample++;
 }
 CVPixelBufferUnlockBaseAddress(pb,kCVPixelBufferLock_ReadOnly);
 CFRelease(yCV);CFRelease(uvCV);
 printf("FRAME_COMPARE frame=%d samples=%zu plane_bad=%zu first_bad=(%u,%u) max_plane_delta=%.7f fused_neon=%zu expected_neon=%zu RGB_large_delta=%zu mean_rgb_abs=%.5f max_sample_chroma_offset=%zu\n",
  n,sample,planeBad,firstBadX,firstBadY,max_err,fusedGreen,expectedGreen,fusedDiff,
  abs_err/(sample*3),suv);
 printf("FRAME_BAD_PLANES frame=%d badY=%zu badU=%zu badV=%zu bbox=(%u,%u)-(%u,%u)\n",
 n,badY,badU,badV,minX,minY,maxX,maxY);
 printf("FRAME_CHROMA_BLIT frame=%d badU=%zu badV=%zu shader_badU=%zu shader_badV=%zu\n",
 n,badBlitU,badBlitV,badU,badV);
 fflush(stdout);
 return 0;
}
int main(int argc,char **argv){
 @autoreleasepool{
  NSString *path=argc>1? [NSString stringWithUTF8String:argv[1]] :
   @"/System/Library/Desktop Pictures/.wallpapers/Sequoia Sunrise/Sequoia Sunrise.mov";
  int limit=argc>2?atoi(argv[2]):12;
  if(limit<1||limit>MAX_FRAMES){fprintf(stderr,"invalid frame count\n");return 2;}
  id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();
  if(!gpu){printf("NO_METAL_DEVICE\n");return 3;}
  NSError *err=nil;
  NSString *shaderSource=shader;
  const char *shaderMode=getenv("REIMS_SHADER_MODE");
  if(shaderMode && strcmp(shaderMode,"sample")==0){
    shaderSource=[shaderSource stringByReplacingOccurrencesOfString:@"texture2d<float,access::read> chroma"
                                      withString:@"texture2d<float,access::sample> chroma"];
    shaderSource=[shaderSource stringByReplacingOccurrencesOfString:@"float2 UV=chroma.read(at/2).rg;"
       withString:@"constexpr sampler ns(coord::normalized, address::clamp_to_edge, filter::nearest); float2 UV=chroma.sample(ns,(float2(at/2)+0.5f)/float2(chroma.get_width(),chroma.get_height())).rg;"];
  } else if(shaderMode && strcmp(shaderMode,"half")==0){
    shaderSource=[shaderSource stringByReplacingOccurrencesOfString:@"texture2d<float,access::read> chroma"
                                      withString:@"texture2d<half,access::read> chroma"];
    shaderSource=[shaderSource stringByReplacingOccurrencesOfString:@"float2 UV=chroma.read(at/2).rg;"
                                      withString:@"float2 UV=float2(chroma.read(at/2).rg);"];
  }
  id<MTLLibrary> lib=[gpu newLibraryWithSource:shaderSource options:nil error:&err];
  if(!lib){printf("SHADER_COMPILE_ERROR %s\n",err.description.UTF8String);return 4;}
  id<MTLFunction> fun=[lib newFunctionWithName:@"read_planes"];
  id<MTLComputePipelineState> pipe=[gpu newComputePipelineStateWithFunction:fun error:&err];
  if(!pipe){printf("PIPELINE_ERROR %s\n",err.description.UTF8String);return 4;}
  CVMetalTextureCacheRef texcache=NULL;
  if(CVMetalTextureCacheCreate(kCFAllocatorDefault,NULL,gpu,NULL,&texcache)!=kCVReturnSuccess){puts("NO_CVMETAL_CACHE");return 4;}
  if(getenv("REIMS_SYNTHETIC_X420")) {
    printf("GUEST_SYNTHETIC_X420_START frames_requested=%d GPU=%s\n",limit,gpu.name.UTF8String);
    fflush(stdout);
    NSDictionary *props=@{
      (id)kCVPixelBufferIOSurfacePropertiesKey:@{},
      (id)kCVPixelBufferMetalCompatibilityKey:@1
    };
    int produced=0;
    for(int n=0;n<limit;n++){
      CVPixelBufferRef pb=NULL;
      CVReturn created=CVPixelBufferCreate(kCFAllocatorDefault,3840,2160,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        (__bridge CFDictionaryRef)props,&pb);
      if(created!=kCVReturnSuccess || !pb) {
        printf("SYNTHETIC_CREATE_FAILED frame=%d cv=%d\n",n,(int)created);
        CFRelease(texcache);return 11;
      }
      CVReturn locked=CVPixelBufferLockBaseAddress(pb,0);
      if(locked!=kCVReturnSuccess){printf("SYNTHETIC_LOCK_FAILED frame=%d code=%d\n",n,(int)locked);CVPixelBufferRelease(pb);CFRelease(texcache);return 12;}
      size_t sy=CVPixelBufferGetBytesPerRowOfPlane(pb,0);
      size_t suv=CVPixelBufferGetBytesPerRowOfPlane(pb,1);
      uint8_t *baseY=CVPixelBufferGetBaseAddressOfPlane(pb,0);
      uint8_t *baseUV=CVPixelBufferGetBaseAddressOfPlane(pb,1);
      memset(baseY,0,sy*2160);memset(baseUV,0,suv*1080);
      for(size_t y=0;y<2160;y++){
        uint16_t *row=(uint16_t *)(baseY+y*sy);
        for(size_t x=0;x<3840;x++){row[x]=(uint16_t)((64+(x*7+y*3+n*13)%876)<<6);}
      }
      for(size_t y=0;y<1080;y++){
        uint16_t *row=(uint16_t *)(baseUV+y*suv);
        for(size_t x=0;x<1920;x++){
          row[2*x]=(uint16_t)((256+(x*3+y*5+n*11)%512)<<6);
          row[2*x+1]=(uint16_t)((256+(x*13+y*7+n*17)%512)<<6);
        }
      }
      CVPixelBufferUnlockBaseAddress(pb,0);
      int ret=inspectFrame(gpu,pipe,texcache,pb,n);
      CVPixelBufferRelease(pb);
      if(ret!=0){CFRelease(texcache);return ret;}
      produced++;
    }
    CFRelease(texcache);
    printf("GUEST_SYNTHETIC_X420_DONE frames=%d\n",produced);
    return produced==limit?0:13;
  }
  AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
  AVAssetTrack *track=[[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  if(!track){puts("NO_VIDEO_TRACK");CFRelease(texcache);return 4;}
  AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:asset error:&err];
  if(!reader){printf("READER_ERROR %s\n",err.description.UTF8String);CFRelease(texcache);return 4;}
  NSDictionary *settings=@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
   (id)kCVPixelBufferMetalCompatibilityKey:@1};
  AVAssetReaderTrackOutput *out=[[AVAssetReaderTrackOutput alloc]initWithTrack:track outputSettings:settings];
  out.alwaysCopiesSampleData=NO;
  if(![reader canAddOutput:out]){puts("CANNOT_ADD_READER_OUTPUT");CFRelease(texcache);return 4;}
  [reader addOutput:out];
  if(![reader startReading]){printf("START_READER_FAIL %s\n",reader.error.description.UTF8String);CFRelease(texcache);return 4;}
  printf("GUEST_METAL_PROBE_START GPU=%s frames_requested=%d mode=%s asset=%s\n",gpu.name.UTF8String,limit,getenv("REIMS_UV_MODE")?: "cached",path.UTF8String);
  fflush(stdout);
  int processed=0;
  for(int i=0;i<limit;i++){
   CMSampleBufferRef sample=[out copyNextSampleBuffer];
   if(!sample){printf("NO_SAMPLE frame=%d status=%ld err=%s\n",i,(long)reader.status,reader.error.description.UTF8String);break;}
   CVImageBufferRef image=CMSampleBufferGetImageBuffer(sample);
   if(image){
    int ret=inspectFrame(gpu,pipe,texcache,(CVPixelBufferRef)image,i);
    if(ret!=0){CFRelease(sample);[reader cancelReading];CFRelease(texcache);return ret;}
    processed++;
   }
   CFRelease(sample);
  }
  [reader cancelReading];CFRelease(texcache);
  printf("GUEST_METAL_PROBE_DONE frames=%d status=%ld\n",processed,(long)reader.status);
  return processed==limit?0:8;
 }
}
