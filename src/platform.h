#pragma once
#include <cstdint>
#include <string>
#include <vector>

struct GLFWwindow;
std::string resourcePath(const std::string& relativePath);

enum class PlatformAction {
    OpenFiles, SelectTab, CloseTab, CloseActiveTab, NextTab, PreviousTab,
    ResetView, ToggleGrid, ToggleWireframe, ToggleCamera, SetGrid,
    SetMirror, SetPreview, Zoom
};
struct PlatformEvent {
    PlatformAction action;
    uint64_t document = 0;
    bool value = false;
    std::vector<std::string> paths;
    float amount = 0.f;
};
struct PlatformTab { uint64_t id; std::string path; };
struct PlatformPreferences { bool grid = false, mirror = true, preview = true; };
struct PlatformState {
    std::vector<PlatformTab> tabs;
    uint64_t active = 0;
    size_t triangles = 0;
    bool grid = false, wireframe = false, camera = false, cameraStarting = false;
    bool mirror = true, preview = true;
    std::string status;
};

// AppKit owns chrome and menus; GLFW continues to own the rendering view.
void prepareMacApp();
void installMacInterface(GLFWwindow* window);
void shutdownMacInterface();
PlatformPreferences macPreferences();
std::vector<PlatformEvent> takeMacEvents();
void updateMacInterface(const PlatformState& state);
void openModelPanel();
void showModelErrors(const std::vector<std::string>& errors);
void showCameraError(const std::string& message);
bool macDarkAppearance();
// Hidden-window integration check for native controls and layout.
void verifyMacInterface();
