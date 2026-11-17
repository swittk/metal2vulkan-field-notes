/* Finite Metal self-read/load-clear observation. No private APIs or screen capture.
 * Records behavior; only Load and external-source controls have unconditional assertions.
 */
typedef void *P; typedef unsigned long U; typedef unsigned char B;
typedef struct{U x,y,z;} Origin;typedef struct{U width,height,depth;} Size;
typedef struct{double red,green,blue,alpha;} Color;
typedef struct{double x,y,width,height,znear,zfar;} Viewport;
extern unsigned alarm(unsigned);
extern P dlopen(const char*,int);extern P dlsym(P,const char*);extern int printf(const char*,...);extern int fflush(P);
static P msg;static P(*sel)(const char*);static P(*cls)(const char*);
static P get(P o,const char*s){return ((P(*)(P,P))msg)(o,sel(s));}
static void act(P o,const char*s){((void(*)(P,P))msg)(o,sel(s));}
static void put(P o,const char*s,P v){((void(*)(P,P,P))msg)(o,sel(s),v);}
static void num(P o,const char*s,U v){((void(*)(P,P,U))msg)(o,sel(s),v);}
static U val(P o,const char*s){return ((U(*)(P,P))msg)(o,sel(s));}
static P text(const char*s){return ((P(*)(P,P,const char*))msg)(cls("NSString"),sel("stringWithUTF8String:"),s);}
static const char*str(P o){return o?(const char*)get(o,"UTF8String"):"nil";}
static P attachment(P pass){return ((P(*)(P,P,U))msg)(get(pass,"colorAttachments"),sel("objectAtIndexedSubscript:"),0);}
static P texture(P device){
 P d=((P(*)(P,P,U,U,U,B))msg)(cls("MTLTextureDescriptor"),sel("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),70,144,64,0);
 num(d,"setStorageMode:",2);num(d,"setUsage:",5);return ((P(*)(P,P,P))msg)(device,sel("newTextureWithDescriptor:"),d);
}
static int seed(P queue,P tex){
 P cb=get(queue,"commandBuffer"),p=get(cls("MTLRenderPassDescriptor"),"renderPassDescriptor"),a=attachment(p);
 put(a,"setTexture:",tex);num(a,"setLoadAction:",2);num(a,"setStoreAction:",1);
 ((void(*)(P,P,Color))msg)(a,sel("setClearColor:"),(Color){1,.25,.5,1});
 P enc=((P(*)(P,P,P))msg)(cb,sel("renderCommandEncoderWithDescriptor:"),p);act(enc,"endEncoding");act(cb,"commit");act(cb,"waitUntilCompleted");return val(cb,"status")==4;
}
static int run(P device,P queue,P pipeline,U load,U width,U height,int external){
 P target=texture(device),source=external?texture(device):target;
 if(!target||!source||!seed(queue,target)||(external&&!seed(queue,source)))return 1;
 P out=((P(*)(P,P,U,U))msg)(device,sel("newBufferWithLength:options:"),1024*64,0);if(!out)return 2;
 P cb=get(queue,"commandBuffer"),p=get(cls("MTLRenderPassDescriptor"),"renderPassDescriptor"),a=attachment(p);
 num(p,"setRenderTargetWidth:",width);num(p,"setRenderTargetHeight:",height);
 put(a,"setTexture:",target);num(a,"setLoadAction:",load);num(a,"setStoreAction:",1);
 ((void(*)(P,P,Color))msg)(a,sel("setClearColor:"),(Color){0,0,0,0});
 P enc=((P(*)(P,P,P))msg)(cb,sel("renderCommandEncoderWithDescriptor:"),p);
 put(enc,"setRenderPipelineState:",pipeline);
 ((void(*)(P,P,Viewport))msg)(enc,sel("setViewport:"),(Viewport){0,0,(double)width,(double)height,0,1});
 ((void(*)(P,P,P,U))msg)(enc,sel("setFragmentTexture:atIndex:"),source,0);
 ((void(*)(P,P,U,U,U))msg)(enc,sel("drawPrimitives:vertexStart:vertexCount:"),3,0,3);act(enc,"endEncoding");
 P blit=get(cb,"blitCommandEncoder");
 ((void(*)(P,P,P,U,U,Origin,Size,P,U,U,U))msg)(blit,sel("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:"),target,0,0,(Origin){0,0,0},(Size){144,64,1},out,0,1024,1024*64);
 act(blit,"endEncoding");act(cb,"commit");act(cb,"waitUntilCompleted");
 B*b=(B*)get(out,"contents");U status=val(cb,"status"),old=0,zero=0;
 for(U y=0;y<height;y++)for(U x=0;x<width;x++){B*t=b+y*1024+x*4;old+=(t[0]>250&&t[3]>250);zero+=(t[0]<3&&t[1]<3&&t[2]<3&&t[3]<3);}
 B*c=b+1024+4;printf("CASE load=%lu region=%lux%lu external=%d status=%lu pixel=%u,%u,%u,%u old=%lu cleared=%lu total=%lu\n",load,width,height,external,status,c[0],c[1],c[2],c[3],old,zero,width*height);fflush(0);
 P error=get(cb,"error");if(error)printf("ERROR %s\n",str(get(error,"localizedDescription")));
 int bad=status!=4||((load==1||external)&&old!=width*height);
 act(out,"release");if(external)act(source,"release");act(target,"release");return bad;
}
int main(void){
 alarm(45);
 P objc=dlopen("/usr/lib/libobjc.A.dylib",10),metal=dlopen("/System/Library/Frameworks/Metal.framework/Metal",10);if(!objc||!metal)return 10;
 msg=dlsym(objc,"objc_msgSend");sel=(P(*)(const char*))dlsym(objc,"sel_registerName");cls=(P(*)(const char*))dlsym(objc,"objc_getClass");
 P pool=get(get(cls("NSAutoreleasePool"),"alloc"),"init");P(*create)(void)=(P(*)(void))dlsym(metal,"MTLCreateSystemDefaultDevice");P device=create();if(!device)return 11;
 printf("DEVICE %s\n",str(get(device,"name")));fflush(0);
 const char*msl="#include <metal_stdlib>\nusing namespace metal;\nvertex float4 v(uint i[[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[i],0,1);}\nfragment float4 f(float4 p[[position]],texture2d<float,access::read> src[[texture(0)]]){return src.read(uint2(p.xy));}\n";
 P error=0;P library=((P(*)(P,P,P,P,P*))msg)(device,sel("newLibraryWithSource:options:error:"),text(msl),0,&error);
 if(!library){printf("LIBRARY_ERROR %s\n",str(get(error,"localizedDescription")));return 12;}
 P vs=((P(*)(P,P,P))msg)(library,sel("newFunctionWithName:"),text("v"));P fs=((P(*)(P,P,P))msg)(library,sel("newFunctionWithName:"),text("f"));
 P desc=get(get(cls("MTLRenderPipelineDescriptor"),"alloc"),"init");put(desc,"setVertexFunction:",vs);put(desc,"setFragmentFunction:",fs);num(attachment(desc),"setPixelFormat:",70);
 P pipeline=((P(*)(P,P,P,P*))msg)(device,sel("newRenderPipelineStateWithDescriptor:error:"),desc,&error);
 if(!pipeline){printf("PIPELINE_ERROR %s\n",str(get(error,"localizedDescription")));return 13;}
 P queue=get(device,"newCommandQueue");int bad=0;
 for(int i=0;i<3;i++){bad+=run(device,queue,pipeline,1,3,40,0);bad+=run(device,queue,pipeline,2,3,40,1);bad+=run(device,queue,pipeline,2,3,40,0);bad+=run(device,queue,pipeline,2,144,64,0);}
 printf("SUMMARY control_failures=%d\n",bad);fflush(0);act(queue,"release");act(pipeline,"release");act(desc,"release");act(vs,"release");act(fs,"release");act(library,"release");act(device,"release");act(pool,"drain");return bad?1:0;
}
