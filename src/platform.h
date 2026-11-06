#pragma once

#include <string>

// Resolve data from the running .app, even after it has been moved or installed.
std::string resourcePath(const std::string& relativePath);

// Returns an empty string when the user cancels the native Open panel.
std::string chooseModelFile();
