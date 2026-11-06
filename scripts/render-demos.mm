// Documentation-only renderer: own window views + OpenGL pixels, never screen
// capture or camera input. Kept outside the installed application's executable.
#import <AppKit/AppKit.h>
#import <Vision/Vision.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#include "gl.h"
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include "renderer.h"
#include "platform.h"
#include "camera_frame.h"
#include "gesture_tracker.h"
#include <cmath>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>

static NSString* ns(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

static FrameSnapshot sampleHand(const std::string& path) {
    NSImage* image = [[NSImage alloc] initWithContentsOfFile:ns(path)];
    CGImageRef cg = [image CGImageForProposedRect:nullptr context:nil hints:nil];
    if (!cg) throw std::runtime_error("Cannot read the sample hand image");
    FrameSnapshot frame;
    frame.width = static_cast<int>(CGImageGetWidth(cg));
    frame.height = static_cast<int>(CGImageGetHeight(cg));
    std::vector<uint8_t> pixels(frame.width * frame.height * 4);
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixels.data(), frame.width, frame.height,
        8, frame.width * 4, color, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (!bitmap) throw std::runtime_error("Cannot create the sample hand bitmap");
    CGContextDrawImage(bitmap, CGRectMake(0, 0, frame.width, frame.height), cg);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(color);
    frame.bgra = cameraPixelsForTexture(pixels.data(), frame.width, frame.height, frame.width * 4);
    frame.hasFrame = true;
    frame.mirrored = true;
    frame.joints.fill({-1.f, -1.f});

    // Run the same Vision detector and temporal classifier on the public sample.
    VNDetectHumanHandPoseRequest* request = [[VNDetectHumanHandPoseRequest alloc] init];
    request.maximumHandCount = 1;
    VNImageRequestHandler* handler = [[VNImageRequestHandler alloc]
        initWithCGImage:cg orientation:kCGImagePropertyOrientationUp options:@{}];
    NSError* error = nil;
    [handler performRequests:@[request] error:&error];
    if (error || !request.results.count) throw std::runtime_error("No hand detected in sample");
    NSArray<NSString*>* names = @[
        VNHumanHandPoseObservationJointNameWrist,
        VNHumanHandPoseObservationJointNameThumbCMC, VNHumanHandPoseObservationJointNameThumbMP,
        VNHumanHandPoseObservationJointNameThumbIP, VNHumanHandPoseObservationJointNameThumbTip,
        VNHumanHandPoseObservationJointNameIndexMCP, VNHumanHandPoseObservationJointNameIndexPIP,
        VNHumanHandPoseObservationJointNameIndexDIP, VNHumanHandPoseObservationJointNameIndexTip,
        VNHumanHandPoseObservationJointNameMiddleMCP, VNHumanHandPoseObservationJointNameMiddlePIP,
        VNHumanHandPoseObservationJointNameMiddleDIP, VNHumanHandPoseObservationJointNameMiddleTip,
        VNHumanHandPoseObservationJointNameRingMCP, VNHumanHandPoseObservationJointNameRingPIP,
        VNHumanHandPoseObservationJointNameRingDIP, VNHumanHandPoseObservationJointNameRingTip,
        VNHumanHandPoseObservationJointNameLittleMCP, VNHumanHandPoseObservationJointNameLittlePIP,
        VNHumanHandPoseObservationJointNameLittleDIP, VNHumanHandPoseObservationJointNameLittleTip];
    int valid = 0;
    for (size_t i = 0; i < frame.joints.size(); ++i) {
        VNRecognizedPoint* point = [request.results.firstObject recognizedPointForJointName:names[i] error:nil];
        if (point.confidence >= .45f) {
            frame.joints[i] = {(float)point.location.x, (float)point.location.y};
            ++valid;
        }
    }
    frame.joints = cameraJointsForPreview(frame.joints, frame.mirrored);
    frame.landmarksValid = valid >= 6;
    GestureTracker tracker;
    for (int i = 0; i < 5; ++i) frame.activeGesture = tracker.update(frame.joints).activeGesture;
    if (frame.activeGesture != GestureEvent::Type::Orbit)
        throw std::runtime_error("The sample must classify as an open-palm orbit gesture");
    std::cout << "Sample hand: " << valid << " Vision joints, orbit gesture confirmed\n";
    return frame;
}

static void saveWindow(GLFWwindow* glfw, const std::string& path) {
    NSWindow* window = glfwGetCocoaWindow(glfw);
    NSView* root = window.contentView.superview;
    [root layoutSubtreeIfNeeded];
    [window displayIfNeeded];
    const CGFloat scale = window.backingScaleFactor;
    const int width = lround(root.bounds.size.width * scale);
    const int height = lround(root.bounds.size.height * scale);
    NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
        pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = root.bounds.size;
    // AppKit renders only this app's native chrome into our bitmap.
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];

    int glWidth, glHeight;
    glfwGetFramebufferSize(glfw, &glWidth, &glHeight);
    std::vector<uint8_t> pixels(glWidth * glHeight * 4);
    glFinish();
    glReadBuffer(GL_BACK);
    glReadPixels(0, 0, glWidth, glHeight, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
    if (glGetError() != GL_NO_ERROR) throw std::runtime_error("Cannot read the rendered scene");
    NSBitmapImageRep* scene = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
        pixelsWide:glWidth pixelsHigh:glHeight bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:glWidth * 4 bitsPerPixel:32];
    for (int y = 0; y < glHeight; ++y)
        memcpy(scene.bitmapData + y * scene.bytesPerRow,
            pixels.data() + (glHeight - 1 - y) * glWidth * 4, glWidth * 4);
    scene.size = window.contentView.bounds.size;
    NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    NSRect canvas = [window.contentView convertRect:window.contentView.bounds toView:root];
    [scene drawInRect:canvas];
    [NSGraphicsContext restoreGraphicsState];
    NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToFile:ns(path) atomically:YES]) throw std::runtime_error("Cannot save snapshot");
    std::cout << path << " (" << width << "x" << height << ")\n";
}

int main(int argc, char** argv) {
    if (argc != 5) {
        std::cerr << "Usage: PolyscopeDemos OUTPUT_DIR HAND_IMAGE FOLLOWER_STL WRIST_STL\n";
        return 1;
    }
    @autoreleasepool {
        glfwSetErrorCallback([](int, const char* e) { std::cerr << e << '\n'; });
        glfwInitHint(GLFW_COCOA_CHDIR_RESOURCES, GLFW_FALSE);
        if (!glfwInit()) return 1;
        prepareMacApp();
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
        glfwWindowHint(GLFW_SAMPLES, 4);
        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
        GLFWwindow* window = glfwCreateWindow(1120, 760, "Polyscope", nullptr, nullptr);
        if (!window) { shutdownMacInterface(); glfwTerminate(); return 1; }
        glfwMakeContextCurrent(window);
        int result = 0;
        try {
            std::filesystem::create_directories(argv[1]);
            installMacInterface(window);
            NSWindow* native = glfwGetCocoaWindow(window);
            // This bundle has its own defaults, so app preferences stay untouched.
            native.frameAutosaveName = @"";
            [native setContentSize:NSMakeSize(1120, 660)];
            Renderer renderer;
            Mesh follower(argv[3]), wrist(argv[4]);
            const auto hand = sampleHand(argv[2]);
            PlatformState state;
            state.tabs = {{1, std::filesystem::canonical(argv[3]).string()},
                          {2, std::filesystem::canonical(argv[4]).string()}};
            for (int mode = 0; mode < 2; ++mode) {
                const bool handMode = mode == 1;
                native.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
                state.active = handMode ? 2 : 1;
                state.camera = handMode;
                const Mesh& mesh = handMode ? wrist : follower;
                state.triangles = mesh.triangleCount();
                updateMacInterface(state);
                [native.contentView.superview layoutSubtreeIfNeeded];
                glfwPollEvents();
                int width, height, logicalWidth, logicalHeight;
                glfwGetFramebufferSize(window, &width, &height);
                glfwGetWindowSize(window, &logicalWidth, &logicalHeight);
                glViewport(0, 0, width, height);
                renderer.resize(width, height);
                renderer.setDarkAppearance(false);
                Camera camera;
                camera.onMouseMove(handMode ? -85.f : -110.f, handMode ? 30.f : 42.f, true, false);
                camera.onScroll(handMode ? 1.6f : 1.2f);
                renderer.render(mesh, camera, false, false);
                if (handMode) renderer.drawOverlay(hand, (float)width / logicalWidth);
                saveWindow(window, (std::filesystem::path(argv[1]) /
                    (handMode ? "hand-controls.png" : "model-tabs.png")).string());
            }
        } catch (const std::exception& error) {
            std::cerr << error.what() << '\n';
            result = 1;
        }
        shutdownMacInterface();
        glfwDestroyWindow(window);
        glfwTerminate();
        return result;
    }
}
