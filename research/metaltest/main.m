// Metallib retag feasibility test. Loads every .metallib in the
// bundle's libs/ with -[MTLDevice newLibraryWithData:error:], runs kernel "sptest" over 256 threads
// and checks out[i] == i * 3 + 0x1234 (plus a float check), then draws with spvert/spfrag. Our own shader only, never the game's.
// Log goes to stdout and Documents/spmetal.log. Exits well within the no-scene watchdog.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>

static FILE *logf_;
static void say(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void say(NSString *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);
  printf("%s\n", s.UTF8String);
  if (logf_) { fprintf(logf_, "%s\n", s.UTF8String); fflush(logf_); }
}

enum { N = 256 };

static void run(id<MTLDevice> dev, id<MTLCommandQueue> q, NSString *path) {
  NSString *name = path.lastPathComponent;
  NSData *data = [NSData dataWithContentsOfFile:path];
  NSError *err = nil;
  dispatch_data_t dd = dispatch_data_create(data.bytes, data.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
  id<MTLLibrary> lib = [dev newLibraryWithData:dd error:&err];
  if (!lib) { say(@"%@: LOAD FAIL %@", name, err); return; }
  say(@"%@: loaded, functions %@", name, lib.functionNames);
  id<MTLFunction> fn = [lib newFunctionWithName:@"sptest"];
  if (!fn) { say(@"%@: no function sptest", name); return; }
  id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn error:&err];
  if (!ps) { say(@"%@: PIPELINE FAIL %@", name, err); return; }
  id<MTLBuffer> out = [dev newBufferWithLength:N * 4 options:MTLResourceStorageModeShared];
  id<MTLBuffer> fout = [dev newBufferWithLength:N * 4 options:MTLResourceStorageModeShared];
  memset(out.contents, 0xff, N * 4);
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
  [enc setComputePipelineState:ps];
  [enc setBuffer:out offset:0 atIndex:0];
  [enc setBuffer:fout offset:0 atIndex:1];
  [enc dispatchThreads:MTLSizeMake(N, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
  [enc endEncoding];
  [cb commit];
  [cb waitUntilCompleted];
  if (cb.error) { say(@"%@: EXEC FAIL %@", name, cb.error); return; }
  const uint32_t *o = out.contents;
  const float *f = fout.contents;
  int bad = 0;
  for (uint32_t i = 0; i < N; i++) {
    float want = sqrtf((float)i) * 0.5f + 1.0f;
    if (o[i] != i * 3 + 0x1234 || fabsf(f[i] - want) > 1e-3f) bad++;
  }
  say(@"%@: EXEC %s (%d/%d wrong; out[5]=0x%x f[16]=%g)", name, bad ? "WRONG" : "OK", bad, N, o[5], f[16]);

  // Render pipeline: fullscreen triangle into an 8x8 RGBA8 target, fragment samples a 1x1 texture
  // holding (1, 1, 1, 1); expect (64, 128, 191, 255) in every pixel.
  MTLRenderPipelineDescriptor *rpd = [MTLRenderPipelineDescriptor new];
  rpd.vertexFunction = [lib newFunctionWithName:@"spvert"];
  rpd.fragmentFunction = [lib newFunctionWithName:@"spfrag"];
  rpd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  id<MTLRenderPipelineState> rps = [dev newRenderPipelineStateWithDescriptor:rpd error:&err];
  if (!rps) { say(@"%@: RENDER PIPELINE FAIL %@", name, err); return; }
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                               width:8 height:8 mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget;
  td.storageMode = MTLStorageModeShared;
  id<MTLTexture> rt = [dev newTextureWithDescriptor:td];
  td.width = td.height = 1;
  td.usage = MTLTextureUsageShaderRead;
  id<MTLTexture> white = [dev newTextureWithDescriptor:td];
  uint32_t px = 0xffffffff;
  [white replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&px bytesPerRow:4];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = rt;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  cb = [q commandBuffer];
  id<MTLRenderCommandEncoder> re = [cb renderCommandEncoderWithDescriptor:pass];
  [re setRenderPipelineState:rps];
  [re setFragmentTexture:white atIndex:0];
  [re drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [re endEncoding];
  [cb commit];
  [cb waitUntilCompleted];
  if (cb.error) { say(@"%@: RENDER FAIL %@", name, cb.error); return; }
  uint8_t pix[8 * 8 * 4];
  [rt getBytes:pix bytesPerRow:32 fromRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0];
  bad = 0;
  for (int i = 0; i < 64; i++)
    if (abs(pix[i * 4] - 64) > 1 || abs(pix[i * 4 + 1] - 128) > 1 || abs(pix[i * 4 + 2] - 191) > 1 || pix[i * 4 + 3] != 255) bad++;
  say(@"%@: RENDER %s (%d/64 wrong; px0=%d,%d,%d,%d)", name, bad ? "WRONG" : "OK", bad, pix[0], pix[1], pix[2], pix[3]);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    logf_ = fopen([docs stringByAppendingPathComponent:@"spmetal.log"].fileSystemRepresentation, "w");
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    say(@"=== spmetal device %@", dev.name);
    id<MTLCommandQueue> q = [dev newCommandQueue];
    NSString *dir = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"libs"];
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]
                      sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *f in files)
      if ([f hasSuffix:@".metallib"]) run(dev, q, [dir stringByAppendingPathComponent:f]);
    say(@"=== done");
  }
  return 0;
}
