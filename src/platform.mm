#import <AppKit/AppKit.h>
#include "platform.h"
#include "model_loader.h"
#include <filesystem>
#include <stdexcept>

std::string resourcePath(const std::string& relativePath) {
    @autoreleasepool {
        NSString* root = [NSBundle mainBundle].resourcePath;
        if (!root)
            throw std::runtime_error("Cannot locate Polyscope's bundled resources.");
        return (std::filesystem::path(root.fileSystemRepresentation) / relativePath).string();
    }
}

std::string chooseModelFile() {
    @autoreleasepool {
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        panel.title = @"Open a 3D model";
        panel.canChooseDirectories = NO;
        panel.allowsMultipleSelection = NO;
        NSMutableArray<NSString*>* extensions = [NSMutableArray array];
        for (const auto& extension : supportedModelExtensions())
            [extensions addObject:[NSString stringWithUTF8String:extension.c_str() + 1]];
        panel.allowedFileTypes = extensions;
        if ([panel runModal] != NSModalResponseOK) return {};
        return std::string(panel.URL.fileSystemRepresentation);
    }
}
