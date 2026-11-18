// Native macOS AppKit window motion: no Accessibility/TCC/Finder automation.
// Moves its OWN window at 40Hz; exits automatically. Logs timer timing.
#import <Cocoa/Cocoa.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>

@interface MotionSurface : NSView
@end
@implementation MotionSurface
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect {
    (void)rect;
    [[NSColor colorWithCalibratedRed:0.10 green:0.18 blue:0.27 alpha:1] setFill];
    NSRectFill([self bounds]);
    for (int i = 0; i < 16; i++) {
        NSRect stripe = NSMakeRect(30 + i * 47, 45, 24, 380);
        [[NSColor colorWithCalibratedRed:(i % 3) / 3.0 + 0.20
                                   green:(i % 5) / 6.0 + 0.18
                                    blue:(i % 7) / 8.0 + 0.19 alpha:1] setFill];
        NSRectFill(stripe);
    }
    // A static marker lets the host capture check actual frame position without
    // forcing redraws on every timer tick. It moves only with this window.
    [[NSColor colorWithSRGBRed:1.0 green:0.0 blue:1.0 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(8,30,12,400));
    NSDictionary *attrs = @{NSFontAttributeName:[NSFont boldSystemFontOfSize:32],
                            NSForegroundColorAttributeName:[NSColor whiteColor]};
    [@"REIMS native AppKit window-motion test" drawAtPoint:NSMakePoint(32,470)
                                            withAttributes:attrs];
}
@end

@interface MotionDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    NSTimer *_timer;
    CFAbsoluteTime _start;
    CFAbsoluteTime _prev;
    double _duration;
    double _maxGapMs;
    unsigned long _ticks;
    unsigned long _gaps60;
}
- (instancetype)initWithDuration:(double)seconds;
@end
@implementation MotionDelegate
- (instancetype)initWithDuration:(double)seconds {
    self = [super init];
    if (self) { _duration = seconds; }
    return self;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    NSRect frame = NSMakeRect(500, 175, 850, 540);
    _window = [[NSWindow alloc] initWithContentRect:frame
                       styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                       backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:@"REIMS motion - native macOS window"];
    [_window setContentView:[[MotionSurface alloc] initWithFrame:NSMakeRect(0,0,850,540)]];
    [_window setReleasedWhenClosed:NO];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    _start = CFAbsoluteTimeGetCurrent();
    _prev = _start;
    printf("APP_START duration=%.2f window=850x540 schedule=40Hz period=4.40s x=500..850 wall_epoch=%.6f\n", _duration, _start + kCFAbsoluteTimeIntervalSince1970);
    fflush(stdout);
    _timer = [NSTimer timerWithTimeInterval:0.025 target:self selector:@selector(tick:)
                                  userInfo:nil repeats:YES];
    [_timer setTolerance:0.001];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)tick:(NSTimer *)timer {
    (void)timer;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double elapsed = now - _start;
    double dt = (now - _prev) * 1000.0;
    _prev = now;
    if (dt > _maxGapMs) _maxGapMs = dt;
    if (dt > 60.0) _gaps60++;
    double phase = fmod(elapsed,4.4) / 4.4;
    double frac = phase <= 0.5 ? phase * 2.0 : 2.0 - phase * 2.0;
    double x = 500.0 + 350.0 * frac;
    [_window setFrameOrigin:NSMakePoint(round(x),175)];
    _ticks++;
    printf("TICK elapsed_ms=%.3f dt_ms=%.3f x=%.0f\n",elapsed*1000.0,dt,x);
    if (elapsed >= _duration) {
        printf("APP_DONE ticks=%lu max_interval_ms=%.3f gaps_over60=%lu duration_ms=%.3f\n",
               _ticks,_maxGapMs,_gaps60,elapsed*1000.0);
        fflush(stdout);
        [_timer invalidate];
        [NSApp terminate:nil];
    }
}
@end

int main(int argc,char **argv) {
    @autoreleasepool {
        double seconds = argc>1 ? atof(argv[1]) : 55.0;
        if (!(seconds>=3.0 && seconds<=360.0)) {
            fprintf(stderr,"duration must be 3 to 360 seconds\n");
            return 2;
        }
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        MotionDelegate *delegate = [[MotionDelegate alloc] initWithDuration:seconds];
        [app setDelegate:delegate];
        [app run];
        return 0;
    }
}
