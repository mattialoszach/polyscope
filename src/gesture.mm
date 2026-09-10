#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#include "gesture.h"
#include "gesture_tracker.h"
#include <atomic>
#include <mutex>
#include <deque>
#include <cstring>
#include <optional>

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
    AVCaptureSession*         __strong session  = nil;
    AVCaptureVideoDataOutput* __strong output   = nil;
    id                        __strong delegate = nil; // CaptureDelegate*
    dispatch_queue_t                   captureQueue = nullptr;

    // ── Event queue (capture thread → main thread) ────────────────────────────
    std::mutex               evMtx;
    std::deque<GestureEvent> evQueue;

    // ── Frame snapshot (capture thread → main thread) ─────────────────────────
    std::mutex    frameMtx;
    std::vector<uint8_t>      framePixels;
    int                       frameW = 0, frameH = 0;
    std::array<glm::vec2, 21> frameJoints{};
    GestureEvent::Type        frameActiveGesture = GestureEvent::Type::None;
    bool                      frameLandmarksValid = false;
    bool                      hasFrame            = false;

    // Only the serial capture queue touches the tracker. The main thread asks
    // it to reset through this flag when camera capture is toggled.
    GestureTracker   tracker;
    std::atomic_bool resetRequested{false};

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
    if (!pt || pt.confidence < 0.45f) return std::nullopt;
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
        if (self.impl->resetRequested.exchange(false))
            self.impl->tracker.reset();

        CVPixelBufferRef pxbuf = CMSampleBufferGetImageBuffer(buf);
        if (!pxbuf) return;

        // ── Copy camera frame ─────────────────────────────────────────────────
        // Pixel-buffer rows are top-to-bottom while our OpenGL texture data is
        // bottom-to-top, so reverse the rows during the copy.
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
        joints.fill(glm::vec2{-1.f, -1.f});
        bool landmarksValid = false;

        if (!err && self.req.results.count > 0) {
            VNHumanHandPoseObservation* obs = self.req.results.firstObject;

            // All 21 joints for the skeleton preview
            int validJointCount = 0;
            for (int i = 0; i < 21; ++i) {
                auto pt = getJoint(obs, kJointNames[i]);
                joints[i] = pt ? glm::vec2{(float)pt->x, (float)pt->y}
                                : glm::vec2{-1.f, -1.f};
                if (pt) ++validJointCount;
            }
            // A partial skeleton is still useful feedback even if there are not
            // enough high-confidence joints to classify it safely.
            landmarksValid = validJointCount >= 6;
        }

        const GestureTrackingResult tracking = self.impl->tracker.update(joints);

        // ── Publish frame + event ─────────────────────────────────────────────
        {
            std::lock_guard<std::mutex> lk(self.impl->frameMtx);
            self.impl->framePixels        = std::move(pixels);
            self.impl->frameW             = w;
            self.impl->frameH             = h;
            self.impl->frameJoints        = joints;
            self.impl->frameActiveGesture = tracking.activeGesture;
            self.impl->frameLandmarksValid = landmarksValid;
            self.impl->hasFrame           = true;
        }
        self.impl->pushEvent(tracking.event);
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

    m_impl->output = [[AVCaptureVideoDataOutput alloc] init];
    m_impl->output.videoSettings = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
    m_impl->output.alwaysDiscardsLateVideoFrames = YES;
    m_impl->captureQueue =
        dispatch_queue_create("polyscope.gesture", DISPATCH_QUEUE_SERIAL);
    [m_impl->output setSampleBufferDelegate:del queue:m_impl->captureQueue];

    m_impl->session = [[AVCaptureSession alloc] init];
    m_impl->session.sessionPreset = AVCaptureSessionPreset640x480;
    if ([m_impl->session canAddInput:input])  [m_impl->session addInput:input];
    if ([m_impl->session canAddOutput:m_impl->output])
        [m_impl->session addOutput:m_impl->output];
    [m_impl->session startRunning];

    NSLog(@"[gesture] Camera session started");
}

GestureSource::~GestureSource() {
    if (m_impl->session) [m_impl->session stopRunning];
    [m_impl->output setSampleBufferDelegate:nil queue:nullptr];
    // Drain a callback already executing before freeing the C++ state it uses.
    if (m_impl->captureQueue)
        dispatch_sync(m_impl->captureQueue, ^{});
    m_impl->delegate = nil;
    delete m_impl;
}

GestureEvent GestureSource::poll() { return m_impl->popEvent(); }

FrameSnapshot GestureSource::getFrame() {
    std::lock_guard<std::mutex> lk(m_impl->frameMtx);
    FrameSnapshot s;
    if (!m_impl->hasFrame) return s;
    s.bgra           = m_impl->framePixels;   // vector copy (~1.2 MB at 640x480)
    s.width          = m_impl->frameW;
    s.height         = m_impl->frameH;
    s.joints         = m_impl->frameJoints;
    s.activeGesture  = m_impl->frameActiveGesture;
    s.landmarksValid = m_impl->frameLandmarksValid;
    s.hasFrame       = true;
    return s;
}

void GestureSource::setActive(bool on) {
    if (!m_impl->session) return;
    m_impl->resetRequested = true;
    if (on)  [m_impl->session startRunning];
    else     [m_impl->session stopRunning];
}

bool GestureSource::isRunning() const {
    return m_impl->session && [m_impl->session isRunning];
}
