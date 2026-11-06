#include "workspace.h"
#include <iostream>
#include <stdexcept>

void require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
int main() {
    Workspace workspace;
    require(!workspace.active() && workspace.documents().empty(), "Starter must not be a tab");
    const auto first = workspace.open("/models/one.obj");
    workspace.active()->camera.onScroll(2.f);
    const auto firstPosition = workspace.active()->camera.position();
    const auto second = workspace.open("/models/two.stl");
    require(workspace.active()->id == second && workspace.documents().size() == 2, "Opening later must append and activate a tab");
    require(workspace.open("/models/one.obj") == first && workspace.documents().size() == 2, "Duplicate opens must reuse a tab");
    require(workspace.active()->camera.position() == firstPosition, "Tabs must preserve individual camera positions");
    workspace.select(999);
    require(workspace.active()->id == first, "Unknown selection must leave the active tab unchanged");
    workspace.cycle(-1);
    require(workspace.active()->id == second, "Previous tab must wrap");
    workspace.cycle(1);
    require(workspace.active()->id == first, "Next tab must wrap");
    require(workspace.close(second) && workspace.active()->id == first, "Closing a background tab must preserve selection");
    const auto third = workspace.open("/models/three.ply");
    workspace.select(first);
    workspace.close(first);
    require(workspace.active()->id == third, "Closing the active tab must select its neighbor");
    workspace.close(third);
    require(!workspace.active() && workspace.documents().empty(), "Closing the last tab must return to the starter");
    require(!workspace.close(third), "Closing a stale tab must be harmless");
    workspace.cycle(1);
    require(workspace.open("/models/one.obj") > third, "Reopening must not reuse stale tab IDs");
    std::cout << "Workspace tests passed\n";
}
