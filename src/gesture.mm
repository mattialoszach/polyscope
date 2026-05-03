#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#include "gesture.h"
#include <mutex>
#include <deque>
#include <cmath>
#include <optional>

// ── Geometry helpers ──────────────────────────────────────────────────────────

static float ptDist(CGPoint a, CGPoint b) {
    float dx = a.x - b.x, dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

// A finger is extended when its tip is farther from the wrist than its MCP.
static bool isExtended(CGPoint tip, CGPoint mcp, CGPoint wrist) {
    return ptDist(tip, wrist) > ptDist(mcp, wrist) * 1.4f;
}

// ── Internal state ────────────────────────────────────────────────────────────
// GestureImpl is forward-declared at file scope in gesture.h so that the
// Objective-C CaptureDelegate can reference it without private-access issues.

struct GestureImpl {
    AVCaptureSession* __strong session  = nil;
    id                __strong delegate = nil;   // CaptureDelegate*

    std::mutex               mtx;
    std::deque<GestureEvent> queue;              // capture thread → main thread

    // Delta-tracking — only touched on the serial capture queue (no lock needed)
    bool  havePrev  = false;
    float prevX     = 0.f;
    float prevY     = 0.f;
    float prevPinch = 0.f;

    void push(GestureEvent e) {
        std::lock_guard<std::mutex> lk(mtx);
        queue.clear();          // keep only the freshest event per frame
        queue.push_back(e);
    }

    GestureEvent pop() {
        std::lock_guard<std::mutex> lk(mtx);
        if (queue.empty()) return {};
        auto e = queue.front();
        queue.pop_front();
        return e;
    }
};

// ── Vision helper (free function, callable from ObjC methods) ─────────────────

static std::optional<CGPoint>
getJoint(VNHumanHandPoseObservation* obs, VNHumanHandPoseObservationJointName name)
{
    NSError* e = nil;
    VNRecognizedPoint* pt = [obs recognizedPointForJointName:name error:&e];
    if (!pt || pt.confidence < 0.4f) return std::nullopt;
    return pt.location;   // normalized [0,1], Vision origin is bottom-left
}

// ── AVFoundation sample-buffer delegate ──────────────────────────────────────

@interface CaptureDelegate
    : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, assign) GestureImpl* impl;
@property (nonatomic, strong) VNDetectHumanHandPoseRequest* req;
@end

@implementation CaptureDelegate

- (instancetype)initWithImpl:(GestureImpl*)impl {
    if ((self = [super init])) {
        _impl = impl;
        _req  = [[VNDetectHumanHandPoseRequest alloc] init];
        _req.maximumHandCount = 1;
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput*)output
 didOutputSampleBuffer:(CMSampleBufferRef)buf
       fromConnection:(AVCaptureConnection*)conn
{
    @autoreleasepool {
        CVPixelBufferRef pxbuf = CMSampleBufferGetImageBuffer(buf);
        if (!pxbuf) return;

        // kCGImagePropertyOrientationUpMirrored compensates for the mirrored
        // front-camera so that moving your hand right moves the camera right.
        VNImageRequestHandler* rh = [[VNImageRequestHandler alloc]
            initWithCVPixelBuffer:pxbuf
                      orientation:kCGImagePropertyOrientationUpMirrored
                          options:@{}];

        NSError* err = nil;
        [rh performRequests:@[self.req] error:&err];

        if (err || self.req.results.count == 0) {
            self.impl->havePrev = false;
            self.impl->push({});
            return;
        }

        VNHumanHandPoseObservation* obs = self.req.results.firstObject;

        // ── Extract joints ────────────────────────────────────────────────────
        auto wrist  = getJoint(obs, VNHumanHandPoseObservationJointNameWrist);
        auto idxTip = getJoint(obs, VNHumanHandPoseObservationJointNameIndexTip);
        auto idxMCP = getJoint(obs, VNHumanHandPoseObservationJointNameIndexMCP);
        auto midTip = getJoint(obs, VNHumanHandPoseObservationJointNameMiddleTip);
        auto midMCP = getJoint(obs, VNHumanHandPoseObservationJointNameMiddleMCP);
        auto rngTip = getJoint(obs, VNHumanHandPoseObservationJointNameRingTip);
        auto rngMCP = getJoint(obs, VNHumanHandPoseObservationJointNameRingMCP);
        auto lttTip = getJoint(obs, VNHumanHandPoseObservationJointNameLittleTip);
        auto lttMCP = getJoint(obs, VNHumanHandPoseObservationJointNameLittleMCP);
        auto tmbTip = getJoint(obs, VNHumanHandPoseObservationJointNameThumbTip);

        // Bail if the two most critical joints are missing
        if (!wrist || !idxTip || !idxMCP) {
            self.impl->havePrev = false;
            return;
        }

        // ── Finger extension flags ────────────────────────────────────────────
        bool idxExt = isExtended(*idxTip, *idxMCP, *wrist);
        bool midExt = midTip && midMCP && isExtended(*midTip, *midMCP, *wrist);
        bool rngExt = rngTip && rngMCP && isExtended(*rngTip, *rngMCP, *wrist);
        bool lttExt = lttTip && lttMCP && isExtended(*lttTip, *lttMCP, *wrist);
        int  extCnt = (int)idxExt + (int)midExt + (int)rngExt + (int)lttExt;

        // Pinch: thumb tip very close to index tip
        bool pinch = tmbTip && ptDist(*tmbTip, *idxTip) < 0.07f;

        // Palm anchor: wrist + index MCP [+ middle MCP] averaged
        float ancX = wrist->x, ancY = wrist->y;
        int   n    = 1;
        if (midMCP) { ancX += midMCP->x; ancY += midMCP->y; n++; }
        ancX /= n; ancY /= n;

        // ── Classify & emit event ─────────────────────────────────────────────
        GestureEvent ev{};

        if (pinch) {
            float d  = ptDist(*tmbTip, *idxTip);
            ev.type  = GestureEvent::Type::Zoom;
            if (self.impl->havePrev)
                ev.scale = (d - self.impl->prevPinch) * 20.f;
            self.impl->prevPinch = d;
            self.impl->havePrev  = true;

        } else if (idxExt && midExt && !rngExt && !lttExt) {
            // Peace sign → pan
            ev.type = GestureEvent::Type::Pan;
            if (self.impl->havePrev) {
                ev.dx = (ancX - self.impl->prevX) *  400.f;
                ev.dy = (ancY - self.impl->prevY) * -400.f;   // flip: Vision Y is bottom-up
            }
            self.impl->prevX    = ancX;
            self.impl->prevY    = ancY;
            self.impl->havePrev = true;

        } else if (extCnt >= 1) {
            // Any other extended finger(s) → orbit
            ev.type = GestureEvent::Type::Orbit;
            if (self.impl->havePrev) {
                ev.dx = (ancX - self.impl->prevX) *  400.f;
                ev.dy = (ancY - self.impl->prevY) * -400.f;
            }
            self.impl->prevX    = ancX;
            self.impl->prevY    = ancY;
            self.impl->havePrev = true;

        } else {
            // Closed fist / unknown → idle, reset delta tracking
            self.impl->havePrev = false;
        }

        self.impl->push(ev);
    }
}
@end

// ── GestureSource ─────────────────────────────────────────────────────────────

GestureSource::GestureSource() : m_impl(new GestureImpl) {
    AVCaptureDevice* cam =
        [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!cam) {
        NSLog(@"[gesture] No camera found — gesture control disabled");
        return;
    }

    NSError* err = nil;
    AVCaptureDeviceInput* input =
        [AVCaptureDeviceInput deviceInputWithDevice:cam error:&err];
    if (!input) {
        NSLog(@"[gesture] Camera input error: %@ — gesture control disabled", err);
        return;
    }

    CaptureDelegate* del = [[CaptureDelegate alloc] initWithImpl:m_impl];
    m_impl->delegate = del;

    AVCaptureVideoDataOutput* out = [[AVCaptureVideoDataOutput alloc] init];
    out.videoSettings = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
    out.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t q =
        dispatch_queue_create("polyscope.gesture", DISPATCH_QUEUE_SERIAL);
    [out setSampleBufferDelegate:del queue:q];

    m_impl->session = [[AVCaptureSession alloc] init];
    m_impl->session.sessionPreset = AVCaptureSessionPreset640x480;
    if ([m_impl->session canAddInput:input])  [m_impl->session addInput:input];
    if ([m_impl->session canAddOutput:out])   [m_impl->session addOutput:out];
    [m_impl->session startRunning];

    NSLog(@"[gesture] Camera session started — show your hand to navigate");
}

GestureSource::~GestureSource() {
    if (m_impl->session)
        [m_impl->session stopRunning];
    delete m_impl;
}

GestureEvent GestureSource::poll() { return m_impl->pop(); }

bool GestureSource::isRunning() const {
    return m_impl->session && [m_impl->session isRunning];
}
