#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#include "gesture.h"
#include "gesture_tracker.h"
#include "camera_frame.h"
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
    dispatch_queue_t                   sessionQueue = dispatch_queue_create("polyscope.camera-session", DISPATCH_QUEUE_SERIAL);
    std::atomic_bool desired{false}, running{false}, starting{false}, closed{false};
    std::atomic_bool mirrored{true};
    std::mutex statusMtx;
    std::string statusText = "Hand controls are off";
    void setStatus(std::string text) {
        std::lock_guard<std::mutex> lock(statusMtx);
        statusText = std::move(text);
    }

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
    bool                      frameMirrored        = true;

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
        if (CVPixelBufferLockBaseAddress(pxbuf, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return;
        int    w   = (int)CVPixelBufferGetWidth(pxbuf);
        int    h   = (int)CVPixelBufferGetHeight(pxbuf);
        size_t bpr = CVPixelBufferGetBytesPerRow(pxbuf);
        auto*  src = (const uint8_t*)CVPixelBufferGetBaseAddress(pxbuf);
        if (!src || w <= 0 || h <= 0 || bpr < static_cast<size_t>(w) * 4) {
            CVPixelBufferUnlockBaseAddress(pxbuf, kCVPixelBufferLock_ReadOnly);
            return;
        }

        auto pixels = cameraPixelsForTexture(src, w, h, bpr);
        CVPixelBufferUnlockBaseAddress(pxbuf, kCVPixelBufferLock_ReadOnly);

        // Vision sees the same upright, unmirrored source as the texture.
        // Both preview pixels and landmarks are mirrored once for selfie mode.
        const bool mirrored = self.impl->mirrored.load();
        VNImageRequestHandler* rh = [[VNImageRequestHandler alloc]
            initWithCVPixelBuffer:pxbuf orientation:kCGImagePropertyOrientationUp options:@{}];
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

        joints = cameraJointsForPreview(joints, mirrored);
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
            self.impl->frameMirrored       = mirrored;
        }
        self.impl->pushEvent(tracking.event);
    }
}
@end

// ── GestureSource ─────────────────────────────────────────────────────────────

namespace {

void startCapture(std::shared_ptr<GestureImpl> impl) {
    dispatch_async(impl->sessionQueue, ^{
        @autoreleasepool {
            if (impl->closed || !impl->desired) { impl->starting = false; return; }
            if (!impl->session) {
                AVCaptureDevice* camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                if (!camera) {
                    impl->setStatus("No camera is available. Connect a camera and try again.");
                    impl->starting = false;
                    return;
                }
                NSError* error = nil;
                AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
                if (!input) {
                    impl->setStatus(error.localizedDescription.UTF8String ?: "Cannot open the camera.");
                    impl->starting = false;
                    return;
                }
                AVCaptureSession* session = [[AVCaptureSession alloc] init];
                AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
                output.videoSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
                output.alwaysDiscardsLateVideoFrames = YES;
                if (![session canAddInput:input] || ![session canAddOutput:output]) {
                    impl->setStatus("This camera does not support video capture.");
                    impl->starting = false;
                    return;
                }
                [session beginConfiguration];
                [session addInput:input];
                [session addOutput:output];
                if ([session canSetSessionPreset:AVCaptureSessionPreset1280x720])
                    session.sessionPreset = AVCaptureSessionPreset1280x720;
                else if ([session canSetSessionPreset:AVCaptureSessionPreset640x480])
                    session.sessionPreset = AVCaptureSessionPreset640x480;
                AVCaptureConnection* connection = [output connectionWithMediaType:AVMediaTypeVideo];
                if (connection.isVideoMirroringSupported) {
                    connection.automaticallyAdjustsVideoMirroring = NO;
                    connection.videoMirrored = NO;
                }
                [session commitConfiguration];
                impl->captureQueue = dispatch_queue_create("polyscope.gesture", DISPATCH_QUEUE_SERIAL);
                CaptureDelegate* delegate = [[CaptureDelegate alloc] initWithImpl:impl.get()];
                [output setSampleBufferDelegate:delegate queue:impl->captureQueue];
                impl->delegate = delegate;
                impl->session = session;
                impl->output = output;
            }
            [impl->session startRunning]; // never block AppKit's main thread
            impl->running = impl->session.isRunning;
            impl->setStatus(impl->running ? "Hand controls on" : "The camera could not start. It may be in use by another app.");
            impl->starting = false;
        }
    });
}

} // namespace

GestureSource::GestureSource() : m_impl(std::make_shared<GestureImpl>()) {}

GestureSource::~GestureSource() {
    auto impl = m_impl;
    impl->closed = true;
    impl->desired = false;
    // A permission completion can outlive the viewer. Its shared state remains
    // valid, but closed prevents it from starting capture after shutdown.
    dispatch_sync(impl->sessionQueue, ^{
        @autoreleasepool {
            [impl->session stopRunning];
            [impl->output setSampleBufferDelegate:nil queue:nullptr];
            if (impl->captureQueue) dispatch_sync(impl->captureQueue, ^{});
            impl->delegate = nil;
        }
    });
}

GestureEvent GestureSource::poll() { return m_impl->popEvent(); }

FrameSnapshot GestureSource::getFrame() {
    if (!m_impl->running) return {};
    std::lock_guard<std::mutex> lock(m_impl->frameMtx);
    FrameSnapshot snapshot;
    if (!m_impl->hasFrame) return snapshot;
    snapshot.bgra = m_impl->framePixels;
    snapshot.width = m_impl->frameW;
    snapshot.height = m_impl->frameH;
    snapshot.joints = m_impl->frameJoints;
    snapshot.activeGesture = m_impl->frameActiveGesture;
    snapshot.landmarksValid = m_impl->frameLandmarksValid;
    snapshot.hasFrame = true;
    snapshot.mirrored = m_impl->frameMirrored;
    return snapshot;
}

void GestureSource::resetTracking() {
    m_impl->resetRequested = true;
    std::lock_guard<std::mutex> lock(m_impl->evMtx);
    m_impl->evQueue.clear();
}

void GestureSource::setActive(bool on) {
    @autoreleasepool {
        auto impl = m_impl;
        impl->desired = on;
        resetTracking();
        if (!on) {
            impl->running = false;
            impl->starting = false;
            impl->setStatus("Hand controls are off");
            dispatch_async(impl->sessionQueue, ^{
                @autoreleasepool {
                    [impl->session stopRunning];
                    if (impl->captureQueue) dispatch_sync(impl->captureQueue, ^{});
                    std::lock_guard<std::mutex> lock(impl->frameMtx);
                    impl->hasFrame = false;
                }
            });
            return;
        }
        impl->starting = true;
        const AVAuthorizationStatus authorization = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        if (authorization == AVAuthorizationStatusDenied || authorization == AVAuthorizationStatusRestricted) {
            impl->setStatus("Camera access is disabled. Allow Polyscope in System Settings → Privacy & Security → Camera, then try again.");
            impl->starting = false;
        } else if (authorization == AVAuthorizationStatusNotDetermined) {
            impl->setStatus("Waiting for camera permission…");
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) startCapture(impl);
                else {
                    impl->setStatus("Camera access was declined. You can enable it in System Settings → Privacy & Security → Camera.");
                    impl->starting = false;
                }
            }];
        } else {
            impl->setStatus("Starting camera…");
            startCapture(impl);
        }
    }
}

void GestureSource::setMirrored(bool mirrored) {
    m_impl->mirrored = mirrored;
    resetTracking();
}

bool GestureSource::isRunning() const { return m_impl->running; }
bool GestureSource::isStarting() const { return m_impl->starting; }
bool GestureSource::hasCameraAccess() {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized;
}
std::string GestureSource::status() const {
    std::lock_guard<std::mutex> lock(m_impl->statusMtx);
    return m_impl->statusText;
}
