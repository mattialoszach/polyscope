#include "gl.h"
#include <GLFW/glfw3.h>
#include "mesh.h"
#include "renderer.h"
#include "camera.h"
#include "gesture.h"

#include <iostream>
#include <string>
#include <filesystem>
#include <memory>

// ── Application state ─────────────────────────────────────────────────────────
// All mutable state that the GLFW callbacks need to reach.
struct App {
    std::unique_ptr<Mesh>          mesh;
    std::unique_ptr<Renderer>      renderer;
    std::unique_ptr<GestureSource> gesture;
    Camera camera;

    // Mouse tracking
    double lastX = 0, lastY = 0;
    bool   firstMove  = true;
    bool   leftDown   = false;
    bool   rightDown  = false;

    // Toggles (keyboard shortcuts)
    bool showGrid   = true;
    bool wireframe  = false;
};

// ── Helpers ───────────────────────────────────────────────────────────────────

static void updateTitle(GLFWwindow* win, const std::string& path, size_t tris, bool gestureOn) {
    std::string name  = std::filesystem::path(path).filename().string();
    std::string title = "polyscope — " + name
                      + "  (" + std::to_string(tris) + " triangles)"
                      + "  [R]=reset  [G]=grid  [W]=wireframe  [Esc]=quit"
                      + (gestureOn ? "  | hand: ON" : "  | hand: OFF");
    glfwSetWindowTitle(win, title.c_str());
}

// ── GLFW callbacks ────────────────────────────────────────────────────────────
// Each callback retrieves the App pointer stored via glfwSetWindowUserPointer.

static void cbError(int id, const char* desc) {
    std::cerr << "GLFW error " << id << ": " << desc << "\n";
}

static void cbResize(GLFWwindow* win, int w, int h) {
    auto* app = static_cast<App*>(glfwGetWindowUserPointer(win));
    glViewport(0, 0, w, h);
    app->renderer->resize(w, h);
}

static void cbKey(GLFWwindow* win, int key, int /*scan*/, int action, int /*mods*/) {
    if (action != GLFW_PRESS) return;
    auto* app = static_cast<App*>(glfwGetWindowUserPointer(win));
    switch (key) {
        case GLFW_KEY_ESCAPE: glfwSetWindowShouldClose(win, GLFW_TRUE); break;
        case GLFW_KEY_R:      app->camera.reset();                       break;
        case GLFW_KEY_G:      app->showGrid  = !app->showGrid;           break;
        case GLFW_KEY_W:      app->wireframe = !app->wireframe;          break;
        default: break;
    }
}

static void cbMouseButton(GLFWwindow* win, int btn, int action, int /*mods*/) {
    auto* app = static_cast<App*>(glfwGetWindowUserPointer(win));
    if (btn == GLFW_MOUSE_BUTTON_LEFT)  app->leftDown  = (action == GLFW_PRESS);
    if (btn == GLFW_MOUSE_BUTTON_RIGHT) app->rightDown = (action == GLFW_PRESS);
    if (action == GLFW_PRESS) app->firstMove = true; // avoid jump on first drag
}

static void cbCursorPos(GLFWwindow* win, double x, double y) {
    auto* app = static_cast<App*>(glfwGetWindowUserPointer(win));
    if (app->firstMove) {
        app->lastX = x; app->lastY = y;
        app->firstMove = false;
        return;
    }
    float dx = static_cast<float>(x - app->lastX);
    float dy = static_cast<float>(y - app->lastY);
    app->lastX = x; app->lastY = y;
    app->camera.onMouseMove(dx, dy, app->leftDown, app->rightDown);
}

static void cbScroll(GLFWwindow* win, double /*dx*/, double dy) {
    static_cast<App*>(glfwGetWindowUserPointer(win))->camera.onScroll(static_cast<float>(dy));
}

static void cbDrop(GLFWwindow* win, int count, const char** paths) {
    if (count == 0) return;
    auto* app = static_cast<App*>(glfwGetWindowUserPointer(win));
    try {
        app->mesh = std::make_unique<Mesh>(paths[0]);
        app->camera.reset();
        updateTitle(win, paths[0], app->mesh->triangleCount(), app->gesture->isRunning());
        std::cout << "Loaded: " << paths[0] << "\n";
    } catch (const std::exception& e) {
        std::cerr << "Drop failed: " << e.what() << "\n";
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

int main(int argc, char** argv) {
    const std::string objPath = argc > 1 ? argv[1] : ASSET_DIR "/sample.obj";

    glfwSetErrorCallback(cbError);
    if (!glfwInit()) {
        std::cerr << "GLFW init failed\n";
        return 1;
    }

    // Request OpenGL 3.3 core profile (forward-compatible on macOS)
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE,        GLFW_OPENGL_CORE_PROFILE);
#ifdef __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
#endif
    glfwWindowHint(GLFW_SAMPLES, 4);  // 4× MSAA for smoother edges

    GLFWwindow* window = glfwCreateWindow(1280, 800, "polyscope", nullptr, nullptr);
    if (!window) {
        std::cerr << "Window creation failed\n";
        glfwTerminate();
        return 1;
    }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1); // VSync: cap at monitor refresh rate

    // ── Build app state ───────────────────────────────────────────────────────
    App app;
    try {
        // Renderer must be created AFTER the GL context is current
        app.renderer = std::make_unique<Renderer>();
        app.mesh     = std::make_unique<Mesh>(objPath);
    } catch (const std::exception& e) {
        std::cerr << "Startup error: " << e.what() << "\n";
        glfwTerminate();
        return 1;
    }

    // Start gesture source (camera capture runs on a background thread)
    app.gesture = std::make_unique<GestureSource>();
    if (app.gesture->isRunning())
        std::cout << "Hand gestures: ON  (open=orbit | peace=pan | pinch=zoom)\n";
    else
        std::cout << "Hand gestures: OFF (camera unavailable or permission denied)\n";

    updateTitle(window, objPath, app.mesh->triangleCount(), app.gesture->isRunning());

    // ── Register callbacks ────────────────────────────────────────────────────
    glfwSetWindowUserPointer(window, &app);
    glfwSetFramebufferSizeCallback(window, cbResize);
    glfwSetKeyCallback(window,         cbKey);
    glfwSetMouseButtonCallback(window, cbMouseButton);
    glfwSetCursorPosCallback(window,   cbCursorPos);
    glfwSetScrollCallback(window,      cbScroll);
    glfwSetDropCallback(window,        cbDrop);

    // Sync initial viewport with the framebuffer (may differ from window size on hidpi)
    int fw, fh;
    glfwGetFramebufferSize(window, &fw, &fh);
    glViewport(0, 0, fw, fh);
    app.renderer->resize(fw, fh);

    // ── Main loop ─────────────────────────────────────────────────────────────
    while (!glfwWindowShouldClose(window)) {
        // Apply any pending gesture event from the background capture thread
        auto ev = app.gesture->poll();
        switch (ev.type) {
            case GestureEvent::Type::Orbit:
                app.camera.onMouseMove(ev.dx, ev.dy, true,  false); break;
            case GestureEvent::Type::Pan:
                app.camera.onMouseMove(ev.dx, ev.dy, false, true);  break;
            case GestureEvent::Type::Zoom:
                app.camera.onScroll(ev.scale);                       break;
            default: break;
        }

        app.renderer->render(*app.mesh, app.camera, app.showGrid, app.wireframe);
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
