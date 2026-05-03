#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#include "gesture.h"
#include <mutex>
#include <deque>
#include <cmath>
#include <cstring>
#include <optional>

// ── Geometry helpers ──────────────────────────────────────────────────────────

static float ptDist(CGPoint a, CGPoint b) {
    float dx = a.x - b.x, dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

static bool isExtended(CGPoint tip, CGPoint mcp, CGPoint wrist) {
    return ptDist(tip, wrist) > ptDist(mcp, wrist) * 1.4f;
}

// ── Joint name table (index 0-20, matching FrameSnapshot::joints layout) ─────

// 0=wrist  1-4=thumb(CMC→tip)  5-8=index  9-12=middle  13-16=ring  17-20=little
static NSString* const kJointNames[21] = {
    VNHumanHandPoseObservationJointNameWrist,
    VNHumanHandPoseObservationJointNameThumbCMC,
    VNHumanHandPoseObservationJointNameThumbMP,
    VNHumanHandPoseObservationJointNameThumbIP,
    VNHumanHandPoseObservationJointNameThumbTip,
    VNHumanHandPoseObservationJointNameIndexMCP,
    VNHumanHandPoseObservationJointNameIndexPIP,
    VNHumanHandPoseObservationJointNameIndexDIP,
    VNHumanHandPoseObservationJointNameIndexTip,
    VNHumanHandPoseObservationJointNameMiddleMCP,
    VNHumanHandPoseObservationJointNameMiddlePIP,
    VNHumanHandPoseObservationJointNameMiddleDIP,
    VNHumanHandPoseObservationJointNameMiddleTip,
    VNHumanHandPoseObservationJointNameRingMCP,
    VNHumanHandPoseObservationJointNameRingPIP,
    VNHumanHandPoseObservationJointNameRingDIP,
    VNHumanHandPoseObservationJointNameRingTip,
    VNHumanHandPoseObservationJointNameLittleMCP,
    VNHumanHandPoseObservationJointNameLittlePIP,
    VNHumanHandPoseObservationJointNameLittleDIP,
    VNHumanHandPoseObservationJointNameLittleTip,
};

// ── Internal state ────────────────────────────────────────────────────────────

struct GestureImpl {
    AVCaptureSession* __strong session  = nil;
    id                __strong delegate = nil;   // CaptureDelegate*

    // ── Event queue (capture thread → main thread) ────────────────────────────
    std::mutex               evMtx;
    std::deque<GestureEvent> evQueue;

    // ── Frame snapshot (capture thread → main thread) ─────────────────────────
    std::mutex    frameMtx;
    std::vector<uint8_t>      framePixels;
    int                       frameW = 0, frameH = 0;
    std::array<glm::vec2, 21> frameJoints{};
    bool                      frameLandmarksValid = false;
    bool                      hasFrame            = false;

    // Delta-tracking — only touched on the serial capture queue (no lock)
    bool  havePrev  = false;
    float prevX     = 0.f, prevY = 0.f;
    float prevPinch = 0.f;

    void pushEvent(GestureEvent e) {
        std::lock_guard<std::mutex> lk(evMtx);
        evQueue.clear();
        evQueue.push_back(e);
    }
    GestureEvent popEvent() {
        std::lock_guard<std::mutex> lk(evMtx);
        if (evQueue.empty()) return {};
        auto e = evQueue.front(); evQueue.pop_front();
        return e;
    }
};

// ── Vision helper ─────────────────────────────────────────────────────────────

static std::optional<CGPoint>
getJoint(VNHumanHandPoseObservation* obs, NSString* name) {
    NSError* e = nil;
    VNRecognizedPoint* pt = [obs recognizedPointForJointName:name error:&e];
    if (!pt || pt.confidence < 0.4f) return std::nullopt;
    return pt.location;   // Vision: normalised [0,1], origin bottom-left
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

        // ── Copy camera frame ─────────────────────────────────────────────────
        // macOS front cameras deliver row 0 at the bottom of the image,
        // which matches OpenGL's texture origin — no row reversal needed.
        CVPixelBufferLockBaseAddress(pxbuf, kCVPixelBufferLock_ReadOnly);
        int    w   = (int)CVPixelBufferGetWidth(pxbuf);
        int    h   = (int)CVPixelBufferGetHeight(pxbuf);
        size_t bpr = CVPixelBufferGetBytesPerRow(pxbuf);
        auto*  src = (const uint8_t*)CVPixelBufferGetBaseAddress(pxbuf);

        std::vector<uint8_t> pixels((size_t)w * h * 4);
        for (int y = 0; y < h; ++y)
            std::memcpy(pixels.data() + (size_t)(h - 1 - y) * w * 4,
                        src + (size_t)y * bpr, (size_t)w * 4);
        CVPixelBufferUnlockBaseAddress(pxbuf, kCVPixelBufferLock_ReadOnly);

        // ── Run Vision hand-pose detection ────────────────────────────────────
        // kCGImagePropertyOrientationUpMirrored: corrects front-camera mirroring
        // so landmark x=0 is the left side of the displayed mirror image.
        VNImageRequestHandler* rh = [[VNImageRequestHandler alloc]
            initWithCVPixelBuffer:pxbuf
                      orientation:kCGImagePropertyOrientationUpMirrored
                          options:@{}];
        NSError* err = nil;
        [rh performRequests:@[self.req] error:&err];

        // ── Extract landmarks + classify gesture ──────────────────────────────
        std::array<glm::vec2, 21> joints{};
        bool landmarksValid = false;
        GestureEvent ev{};

        if (!err && self.req.results.count > 0) {
            VNHumanHandPoseObservation* obs = self.req.results.firstObject;

            // All 21 joints for the skeleton preview
            for (int i = 0; i < 21; ++i) {
                auto pt = getJoint(obs, kJointNames[i]);
                joints[i] = pt ? glm::vec2{(float)pt->x, (float)pt->y}
                                : glm::vec2{-1.f, -1.f};
            }

            // Key joints for gesture classification
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

            if (wrist && idxTip && idxMCP) {
                landmarksValid = true;

                bool idxExt = isExtended(*idxTip, *idxMCP, *wrist);
                bool midExt = midTip && midMCP && isExtended(*midTip, *midMCP, *wrist);
                bool rngExt = rngTip && rngMCP && isExtended(*rngTip, *rngMCP, *wrist);
                bool lttExt = lttTip && lttMCP && isExtended(*lttTip, *lttMCP, *wrist);
                int  extCnt = (int)idxExt + (int)midExt + (int)rngExt + (int)lttExt;
                bool pinch  = tmbTip && ptDist(*tmbTip, *idxTip) < 0.07f;

                float ancX = wrist->x, ancY = wrist->y;
                int   n    = 1;
                if (midMCP) { ancX += midMCP->x; ancY += midMCP->y; n++; }
                ancX /= n; ancY /= n;

                if (pinch) {
                    float d  = ptDist(*tmbTip, *idxTip);
                    ev.type  = GestureEvent::Type::Zoom;
                    if (self.impl->havePrev)
                        ev.scale = (d - self.impl->prevPinch) * 20.f;
                    self.impl->prevPinch = d;
                    self.impl->havePrev  = true;
                } else if (idxExt && midExt && !rngExt && !lttExt) {
                    ev.type = GestureEvent::Type::Pan;
                    if (self.impl->havePrev) {
                        ev.dx = (ancX - self.impl->prevX) *  400.f;
                        ev.dy = (ancY - self.impl->prevY) * -400.f;
                    }
                    self.impl->prevX = ancX; self.impl->prevY = ancY;
                    self.impl->havePrev = true;
                } else if (extCnt >= 1) {
                    ev.type = GestureEvent::Type::Orbit;
                    if (self.impl->havePrev) {
                        ev.dx = (ancX - self.impl->prevX) *  400.f;
                        ev.dy = (ancY - self.impl->prevY) * -400.f;
                    }
                    self.impl->prevX = ancX; self.impl->prevY = ancY;
                    self.impl->havePrev = true;
                } else {
                    self.impl->havePrev = false;
                }
            } else {
                self.impl->havePrev = false;
            }
        } else {
            self.impl->havePrev = false;
        }

        // ── Publish frame + event ─────────────────────────────────────────────
        {
            std::lock_guard<std::mutex> lk(self.impl->frameMtx);
            self.impl->framePixels        = std::move(pixels);
            self.impl->frameW             = w;
            self.impl->frameH             = h;
            self.impl->frameJoints        = joints;
            self.impl->frameLandmarksValid = landmarksValid;
            self.impl->hasFrame           = true;
        }
        self.impl->pushEvent(ev);
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
        NSLog(@"[gesture] Camera input error: %@ — disabled", err);
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

    NSLog(@"[gesture] Camera session started");
}

GestureSource::~GestureSource() {
    if (m_impl->session) [m_impl->session stopRunning];
    delete m_impl;
}

GestureEvent GestureSource::poll() { return m_impl->popEvent(); }

FrameSnapshot GestureSource::getFrame() {
    std::lock_guard<std::mutex> lk(m_impl->frameMtx);
    FrameSnapshot s;
    if (!m_impl->hasFrame) return s;
    s.bgra           = m_impl->framePixels;   // vector copy (~300KB at 640x480)
    s.width          = m_impl->frameW;
    s.height         = m_impl->frameH;
    s.joints         = m_impl->frameJoints;
    s.landmarksValid = m_impl->frameLandmarksValid;
    s.hasFrame       = true;
    return s;
}

void GestureSource::setActive(bool on) {
    if (!m_impl->session) return;
    if (on)  [m_impl->session startRunning];
    else     [m_impl->session stopRunning];
}

bool GestureSource::isRunning() const {
    return m_impl->session && [m_impl->session isRunning];
}
