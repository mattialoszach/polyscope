#include "gl.h"
#include <GLFW/glfw3.h>
#include "mesh.h"
#include "renderer.h"
#include "camera.h"
#include "gesture.h"
#include "platform.h"
#include "model_loader.h"
#include "workspace.h"
#include "camera_frame.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <deque>
#include <filesystem>
#include <fstream>
#include <future>
#include <iostream>
#include <memory>
#include <thread>
#include <unordered_map>

struct ImportResult {
    std::string path;
    std::vector<Vertex> vertices;
    std::string error;
};
struct App {
    std::unique_ptr<Renderer> renderer;
    std::unique_ptr<Mesh> starter;
    std::unique_ptr<GestureSource> gesture;
    Workspace workspace;
    std::unordered_map<uint64_t, std::unique_ptr<Mesh>> meshes;
    Camera starterCamera;
    PlatformPreferences preferences;
    bool wireframe = false, dirtyUI = true, cameraRequested = false;
    bool lastCameraRunning = false, lastCameraStarting = false;
    double lastX = 0, lastY = 0;
    bool firstMove = true, leftDown = false, rightDown = false;
    std::deque<std::string> pending;
    std::future<ImportResult> import;
    std::string importing;
    std::vector<std::string> errors;

    Camera& camera() { return workspace.active() ? workspace.active()->camera : starterCamera; }
    Mesh& mesh() { return workspace.active() ? *meshes.at(workspace.active()->id) : *starter; }
    void resetInput() {
        leftDown = rightDown = false;
        firstMove = true;
        if (gesture) gesture->resetTracking();
        dirtyUI = true;
    }
};

static void queueFiles(App& app, const std::vector<std::string>& paths) {
    for (const auto& input : paths) {
        try {
            const auto path = std::filesystem::canonical(input);
            std::string extension = path.extension().string();
            std::transform(extension.begin(), extension.end(), extension.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            const auto& supported = supportedModelExtensions();
            if (!std::filesystem::is_regular_file(path) ||
                std::find(supported.begin(), supported.end(), extension) == supported.end())
                throw std::runtime_error("Choose a 3MF, STL, OBJ, PLY, glTF, GLB, FBX, or Collada model.");
            const auto name = path.string();
            if (const auto existing = app.workspace.find(name)) {
                app.workspace.select(existing);
                app.resetInput();
            } else if (name != app.importing && std::find(app.pending.begin(), app.pending.end(), name) == app.pending.end()) {
                app.pending.push_back(name);
            }
        } catch (const std::exception& error) {
            app.errors.push_back(std::filesystem::path(input).filename().string() + ": " + error.what());
        }
    }
    app.dirtyUI = true;
}

static void pumpImports(App& app, bool reportErrors = true) {
    if (app.import.valid() && app.import.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
        auto result = app.import.get();
        if (result.error.empty()) {
            auto mesh = std::make_unique<Mesh>(result.vertices);
            const auto id = app.workspace.open(result.path);
            app.meshes.emplace(id, std::move(mesh));
            app.resetInput();
        } else app.errors.push_back(std::filesystem::path(result.path).filename().string() + ": " + result.error);
        app.importing.clear();
        app.dirtyUI = true;
    }
    if (!app.import.valid() && !app.pending.empty()) {
        app.importing = app.pending.front();
        app.pending.pop_front();
        // Parsing stays off the UI thread. Only GPU upload runs on the GL thread.
        app.import = std::async(std::launch::async, [path = app.importing] {
            ImportResult result;
            result.path = path;
            try { result.vertices = loadModelVertices(path); }
            catch (const std::exception& error) { result.error = error.what(); }
            return result;
        });
        app.dirtyUI = true;
    }
    if (reportErrors && !app.import.valid() && app.pending.empty() && !app.errors.empty()) {
        showModelErrors(app.errors);
        app.errors.clear();
    }
}

static void syncInterface(App& app) {
    const bool running = app.gesture->isRunning(), starting = app.gesture->isStarting();
    if (running != app.lastCameraRunning || starting != app.lastCameraStarting) app.dirtyUI = true;
    app.lastCameraRunning = running;
    app.lastCameraStarting = starting;
    if (app.cameraRequested && !running && !starting) {
        app.cameraRequested = false;
        showCameraError(app.gesture->status());
        app.dirtyUI = true;
    }
    if (!app.dirtyUI) return;
    PlatformState state;
    for (const auto& document : app.workspace.documents()) state.tabs.push_back({document.id, document.path});
    state.active = app.workspace.active() ? app.workspace.active()->id : 0;
    state.triangles = app.mesh().triangleCount();
    state.grid = app.preferences.grid;
    state.wireframe = app.wireframe;
    state.camera = running;
    state.cameraStarting = starting;
    state.mirror = app.preferences.mirror;
    state.preview = app.preferences.preview;
    const size_t loading = app.pending.size() + (app.import.valid() ? 1 : 0);
    if (loading) state.status = "Opening " + std::to_string(loading) + (loading == 1 ? " model…" : " models…");
    else if (starting) state.status = "Starting camera…";
    updateMacInterface(state);
    app.dirtyUI = false;
}

static void perform(App& app, PlatformEvent event) {
    switch (event.action) {
        case PlatformAction::OpenFiles: queueFiles(app, event.paths); break;
        case PlatformAction::SelectTab: app.workspace.select(event.document); break;
        case PlatformAction::CloseActiveTab:
            if (auto* document = app.workspace.active()) event.document = document->id;
            [[fallthrough]];
        case PlatformAction::CloseTab:
            if (app.workspace.close(event.document)) app.meshes.erase(event.document);
            break;
        case PlatformAction::NextTab: app.workspace.cycle(1); break;
        case PlatformAction::PreviousTab: app.workspace.cycle(-1); break;
        case PlatformAction::ResetView: app.camera().reset(); break;
        case PlatformAction::ToggleGrid: app.preferences.grid = !app.preferences.grid; break;
        case PlatformAction::SetGrid: app.preferences.grid = event.value; break;
        case PlatformAction::ToggleWireframe: app.wireframe = !app.wireframe; break;
        case PlatformAction::ToggleCamera:
            app.cameraRequested = !app.cameraRequested;
            app.gesture->setActive(app.cameraRequested);
            break;
        case PlatformAction::SetMirror:
            app.preferences.mirror = event.value;
            app.gesture->setMirrored(event.value);
            break;
        case PlatformAction::SetPreview: app.preferences.preview = event.value; break;
        case PlatformAction::Zoom: app.camera().onScroll(event.amount * 4.f); break;
    }
    app.resetInput();
}

static void cbError(int, const char* description) { std::cerr << "GLFW: " << description << '\n'; }
static void cbKey(GLFWwindow* window, int key, int, int action, int mods) {
    if (action != GLFW_PRESS || (mods & (GLFW_MOD_SUPER | GLFW_MOD_CONTROL | GLFW_MOD_ALT))) return;
    auto& app = *static_cast<App*>(glfwGetWindowUserPointer(window));
    switch (key) {
        case GLFW_KEY_R: perform(app, {PlatformAction::ResetView}); break;
        case GLFW_KEY_G: perform(app, {PlatformAction::ToggleGrid}); break;
        case GLFW_KEY_W: perform(app, {PlatformAction::ToggleWireframe}); break;
        case GLFW_KEY_C: perform(app, {PlatformAction::ToggleCamera}); break;
        case GLFW_KEY_ESCAPE: app.resetInput(); break;
    }
}
static void cbMouseButton(GLFWwindow* window, int button, int action, int mods) {
    auto& app = *static_cast<App*>(glfwGetWindowUserPointer(window));
    if (button == GLFW_MOUSE_BUTTON_LEFT) {
        app.leftDown = action == GLFW_PRESS && !(mods & GLFW_MOD_SHIFT);
        app.rightDown = action == GLFW_PRESS && (mods & GLFW_MOD_SHIFT);
    }
    if (button == GLFW_MOUSE_BUTTON_RIGHT) app.rightDown = action == GLFW_PRESS;
    if (action == GLFW_PRESS) app.firstMove = true;
}
static void cbCursor(GLFWwindow* window, double x, double y) {
    auto& app = *static_cast<App*>(glfwGetWindowUserPointer(window));
    if (!app.firstMove) app.camera().onMouseMove(x - app.lastX, y - app.lastY, app.leftDown, app.rightDown);
    app.firstMove = false;
    app.lastX = x;
    app.lastY = y;
}
static void cbScroll(GLFWwindow* window, double, double amount) {
    static_cast<App*>(glfwGetWindowUserPointer(window))->camera().onScroll(amount);
}
static void cbDrop(GLFWwindow* window, int count, const char** paths) {
    queueFiles(*static_cast<App*>(glfwGetWindowUserPointer(window)), {paths, paths + count});
}
static void cbFocus(GLFWwindow* window, int focused) {
    if (!focused) static_cast<App*>(glfwGetWindowUserPointer(window))->resetInput();
}

static bool renderingSmokeTest(App& app, int width, int height) {
    app.renderer->render(app.mesh(), app.camera(), false, false);
    // An asymmetric test image verifies upright, mirrored preview pixels through
    // the real shaders, not just the CPU coordinate calculations.
    FrameSnapshot frame;
    frame.width = 320; frame.height = 180; frame.hasFrame = true;
    frame.bgra.resize(frame.width * frame.height * 4);
    for (int y = 0; y < frame.height; ++y) for (int x = 0; x < frame.width; ++x) {
        const size_t index = (y * frame.width + x) * 4;
        frame.bgra[index] = 0;
        frame.bgra[index + 1] = y > frame.height / 2 ? 255 : 0;
        frame.bgra[index + 2] = x > frame.width / 2 ? 255 : 0;
        frame.bgra[index + 3] = 255;
    }
    const auto rect = cameraPreviewRect(width, height, frame.width, frame.height, 1.f);
    for (bool mirror : {false, true}) {
        frame.mirrored = mirror;
        app.renderer->drawOverlay(frame);
        unsigned char pixel[4]{};
        glReadPixels(rect.x + rect.width * .25f, rect.y + rect.height * .75f, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        if ((pixel[0] > 128) != mirror || pixel[1] < 128) return false;
    }
    glFinish();
    return glGetError() == GL_NO_ERROR;
}

static bool cameraSmokeTest(App& app) {
    if (!GestureSource::hasCameraAccess()) {
        std::cout << "Live camera check skipped: enable Hand Controls in the app to grant camera permission first.\n";
        return true;
    }
    app.gesture->setActive(true);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(12);
    bool success = false;
    while (std::chrono::steady_clock::now() < deadline) {
        glfwPollEvents();
        const auto frame = app.gesture->getFrame();
        if (frame.hasFrame) {
            success = frame.width > 0 && frame.height > 0 && frame.bgra.size() == static_cast<size_t>(frame.width) * frame.height * 4;
            app.renderer->render(app.mesh(), app.camera(), false, false);
            app.renderer->drawOverlay(frame);
            glFinish();
            success = success && glGetError() == GL_NO_ERROR;
            std::cout << "Live camera capture: " << frame.width << 'x' << frame.height
                      << (success ? ", preview rendered successfully\n" : ", invalid frame or rendering error\n");
            break;
        }
        if (!app.gesture->isStarting() && !app.gesture->isRunning()) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
    if (!success) std::cerr << "Camera check: " << app.gesture->status() << '\n';
    app.gesture->setActive(false);
    return success;
}

static void workspaceSmokeTest(App& app) {
    auto require = [](bool value, const char* message) { if (!value) throw std::runtime_error(message); };
    const auto directory = std::filesystem::canonical(std::filesystem::temp_directory_path()) /
        ("polyscope-workspace-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directory(directory);
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() { std::error_code ignored; std::filesystem::remove_all(path, ignored); }
    } cleanup{directory};
    const auto first = (directory / "First.obj").string();
    const auto second = (directory / "Second.obj").string();
    const auto later = (directory / "Later.obj").string();
    const auto broken = (directory / "Broken.obj").string();
    for (const auto& path : {first, second, later})
        std::filesystem::copy_file(resourcePath("assets/sample.obj"), path);
    std::ofstream(broken) << "This is not a model";
    auto finishImports = [&] {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        do {
            pumpImports(app, false);
            glfwPollEvents();
            if (!app.import.valid() && app.pending.empty()) return;
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        } while (std::chrono::steady_clock::now() < deadline);
        throw std::runtime_error("Model imports did not finish");
    };
    require(app.workspace.documents().empty(), "Starter cube must not appear as a tab");
    queueFiles(app, {first, second});
    finishImports();
    require(app.workspace.documents().size() == 2 && app.meshes.size() == 2,
            "A batch drop must create a tab and GPU mesh for every model");
    require(app.workspace.active()->path == second, "The newest model must be selected");
    syncInterface(app);
    queueFiles(app, {later, broken});
    finishImports();
    require(app.workspace.documents().size() == 3 && app.errors.size() == 1,
            "Later drops must append valid models and preserve existing tabs when an import fails");
    require(app.workspace.active()->path == later, "A failed model must not replace the active valid model");
    app.errors.clear();
    queueFiles(app, {first});
    require(app.workspace.documents().size() == 3 && app.workspace.active()->path == first,
            "Dropping an already open model must activate its tab without duplicating it");
    syncInterface(app);
    while (app.workspace.active()) perform(app, {PlatformAction::CloseActiveTab});
    require(app.meshes.empty() && &app.mesh() == app.starter.get(), "Closing the last tab must free document meshes and restore the starter");
    syncInterface(app);
    std::cout << "Multi-file import and tab integration tests passed\n";
}

int main(int argc, char** argv) {
    const bool checkResources = argc > 1 && std::string(argv[1]) == "--check-resources";
    const bool smokeTest = argc > 1 && std::string(argv[1]) == "--smoke-test";
    const bool uiSmokeTest = argc > 1 && std::string(argv[1]) == "--ui-smoke-test";
    const bool cameraTest = argc > 1 && std::string(argv[1]) == "--camera-smoke-test";
    try {
        if (checkResources) {
            for (const char* name : {"model.vert", "model.frag", "flat.vert", "flat.frag", "overlay.vert", "overlay.frag"}) {
                std::ifstream shader(resourcePath(std::string("shaders/") + name));
                if (!shader || shader.peek() == std::ifstream::traits_type::eof()) throw std::runtime_error(std::string("Missing shader: ") + name);
            }
            const auto vertices = loadModelVertices(resourcePath("assets/sample.obj"));
            std::cout << "Bundle resources OK (" << vertices.size() / 3 << " sample triangles)\n";
            return 0;
        }
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }

    glfwSetErrorCallback(cbError);
    if (!glfwInit()) return 1;
    prepareMacApp();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    glfwWindowHint(GLFW_SAMPLES, 4);
    if (smokeTest || uiSmokeTest || cameraTest) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    GLFWwindow* window = glfwCreateWindow(1120, 760, "Polyscope", nullptr, nullptr);
    if (!window) { shutdownMacInterface(); glfwTerminate(); return 1; }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);
    App app;
    bool success = true;
    try {
        app.renderer = std::make_unique<Renderer>();
        app.starter = std::make_unique<Mesh>(resourcePath("assets/sample.obj"));
        app.gesture = std::make_unique<GestureSource>(); // no device access at launch
        app.preferences = macPreferences();
        app.gesture->setMirrored(app.preferences.mirror);
        if (!smokeTest && !cameraTest) {
            installMacInterface(window);
            glfwSetWindowUserPointer(window, &app);
            glfwSetKeyCallback(window, cbKey);
            glfwSetMouseButtonCallback(window, cbMouseButton);
            glfwSetCursorPosCallback(window, cbCursor);
            glfwSetScrollCallback(window, cbScroll);
            glfwSetDropCallback(window, cbDrop);
            glfwSetWindowFocusCallback(window, cbFocus);
            if (uiSmokeTest) {
                verifyMacInterface();
                workspaceSmokeTest(app);
                if (app.gesture->isRunning() || app.gesture->isStarting())
                    throw std::runtime_error("Camera must remain off during startup");
                std::cout << "Native interface smoke tests passed\n";
                glfwSetWindowShouldClose(window, GLFW_TRUE);
            } else if (argc > 1) queueFiles(app, {argv + 1, argv + argc});
        }
        if (cameraTest) {
            int width, height;
            glfwGetFramebufferSize(window, &width, &height);
            glViewport(0, 0, width, height);
            app.renderer->resize(width, height);
            success = cameraSmokeTest(app);
            glfwSetWindowShouldClose(window, GLFW_TRUE);
        }
        while (!glfwWindowShouldClose(window)) {
            int width, height, logicalWidth, logicalHeight;
            glfwGetFramebufferSize(window, &width, &height);
            glfwGetWindowSize(window, &logicalWidth, &logicalHeight);
            if (width == 0 || height == 0) { glfwWaitEventsTimeout(.05); continue; }
            glViewport(0, 0, width, height);
            app.renderer->resize(width, height);
            if (smokeTest) {
                success = renderingSmokeTest(app, width, height);
                std::cout << (success ? "OpenGL and camera preview smoke tests passed\n" : "Rendering smoke test failed\n");
                break;
            }
            for (auto& event : takeMacEvents()) perform(app, std::move(event));
            pumpImports(app);
            syncInterface(app);
            app.renderer->setDarkAppearance(macDarkAppearance());
            auto event = app.gesture->poll();
            switch (event.type) {
                case GestureEvent::Type::Orbit: app.camera().onMouseMove(event.dx, event.dy, true, false); break;
                case GestureEvent::Type::Pan: app.camera().onMouseMove(event.dx, event.dy, false, true); break;
                case GestureEvent::Type::Zoom: app.camera().onScroll(event.scale); break;
                default: break;
            }
            app.renderer->render(app.mesh(), app.camera(), app.preferences.grid, app.wireframe);
            if (app.gesture->isRunning() && app.preferences.preview)
                app.renderer->drawOverlay(app.gesture->getFrame(), static_cast<float>(width) / std::max(1, logicalWidth));
            glfwSwapBuffers(window);
            glfwPollEvents();
        }
    } catch (const std::exception& error) {
        std::cerr << "Polyscope: " << error.what() << '\n';
        success = false;
    }
    app.gesture.reset();
    app.meshes.clear();
    app.starter.reset();
    app.renderer.reset();
    shutdownMacInterface();
    glfwDestroyWindow(window);
    glfwTerminate();
    return success ? 0 : 1;
}
