#import <AppKit/AppKit.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include "platform.h"
#include "model_loader.h"
#include <filesystem>
#include <algorithm>
#include <cmath>
#include <utility>
#include <stdexcept>

std::string resourcePath(const std::string& relativePath) {
    @autoreleasepool {
        NSString* root = [NSBundle mainBundle].resourcePath;
        if (!root) throw std::runtime_error("Cannot locate Polyscope's bundled resources.");
        return (std::filesystem::path(root.fileSystemRepresentation) / relativePath).string();
    }
}

static NSString* text(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}
static NSImage* symbol(NSString* name, NSString* description) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
}

@interface ModelTabView : NSView
@property(nonatomic) BOOL selected;
@end
@implementation ModelTabView
- (void)drawRect:(NSRect)rect {
    if (self.selected) {
        [NSColor.controlBackgroundColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 3) xRadius:7 yRadius:7] fill];
    }
}
@end

@interface TabScrollView : NSScrollView
@end
@implementation TabScrollView
- (void)scrollWheel:(NSEvent*)event {
    if (fabs(event.scrollingDeltaY) > fabs(event.scrollingDeltaX)) {
        const CGFloat limit = MAX(0, self.documentView.frame.size.width - self.contentSize.width);
        NSPoint origin = self.contentView.bounds.origin;
        origin.x = MIN(limit, MAX(0, origin.x + event.scrollingDeltaY));
        [self.contentView scrollToPoint:origin];
        [self reflectScrolledClipView:self.contentView];
    } else [super scrollWheel:event];
}
@end

@interface FileDropStrip : NSView
@property(nonatomic, copy) void (^openFiles)(NSArray<NSURL*>*);
@end
@implementation FileDropStrip
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSArray<NSURL*>* urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    for (NSURL* url in urls) {
        const std::string extension = "." + std::string(url.pathExtension.lowercaseString.UTF8String);
        const auto& supported = supportedModelExtensions();
        if (std::find(supported.begin(), supported.end(), extension) != supported.end()) return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL*>* urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    if (!urls.count) return NO;
    if (self.openFiles) self.openFiles(urls);
    return YES;
}
@end

@interface PolyscopeUI : NSObject <NSToolbarDelegate, NSApplicationDelegate, NSMenuItemValidation, NSTableViewDataSource, NSTableViewDelegate> {
@public
    std::vector<PlatformEvent> events;
    PlatformState state;
}
@property(nonatomic, strong) id<NSApplicationDelegate> originalDelegate;
@property(nonatomic, weak) NSWindow* window;
@property(nonatomic) GLFWwindow* glfwWindow;
@property(nonatomic, strong) NSTitlebarAccessoryViewController* accessory;
@property(nonatomic, strong) TabScrollView* tabs;
@property(nonatomic, strong) NSTextField* hint;
@property(nonatomic, strong) NSTextField* status;
@property(nonatomic, strong) NSToolbarItem* cameraItem;
@property(nonatomic, strong) NSPanel* helpPanel;
@property(nonatomic, strong) NSTableView* shortcutsTable;
@property(nonatomic, strong) NSArray<NSArray<NSString*>*>* shortcutRows;
@property(nonatomic, strong) NSPanel* settingsPanel;
@property(nonatomic, strong) NSButton* gridSetting;
@property(nonatomic, strong) NSButton* mirrorSetting;
@property(nonatomic, strong) NSButton* previewSetting;
@property(nonatomic, strong) NSButton* cameraSetting;
@property(nonatomic) BOOL openingPanel;
@property(nonatomic) BOOL testing;
@property(nonatomic, strong) id magnifyMonitor;
- (void)installMenus;
- (void)refresh:(const PlatformState&)newState;
- (void)open:(id)sender;
@end

@implementation PolyscopeUI
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.originalDelegate respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    if ([self.originalDelegate respondsToSelector:selector]) return self.originalDelegate;
    return [super forwardingTargetForSelector:selector];
}
- (void)application:(NSApplication*)application openFiles:(NSArray<NSString*>*)filenames {
    PlatformEvent event{PlatformAction::OpenFiles};
    for (NSString* filename in filenames) event.paths.emplace_back(filename.fileSystemRepresentation);
    events.push_back(std::move(event));
    [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}
- (void)perform:(id)sender {
    PlatformEvent event{static_cast<PlatformAction>([sender tag])};
    if ([sender isKindOfClass:NSButton.class]) event.value = [sender state] == NSControlStateValueOn;
    events.push_back(std::move(event));
}
- (void)selectTab:(NSButton*)sender {
    events.push_back({PlatformAction::SelectTab, static_cast<uint64_t>(sender.tag)});
    [self.window makeFirstResponder:self.window.contentView];
}
- (void)closeTab:(NSButton*)sender {
    events.push_back({PlatformAction::CloseTab, static_cast<uint64_t>(sender.tag)});
    [self.window makeFirstResponder:self.window.contentView];
}
- (void)closeActive:(id)sender {
    if (NSApp.keyWindow && NSApp.keyWindow != self.window) {
        [NSApp.keyWindow performClose:sender];
        return;
    }
    if (state.tabs.empty()) [self.window performClose:sender];
    else events.push_back({PlatformAction::CloseActiveTab});
}
- (void)open:(id)sender {
    if (self.openingPanel || self.window.attachedSheet) return;
    self.openingPanel = YES;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Open 3D Models";
    panel.prompt = @"Open";
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    NSMutableArray<NSString*>* extensions = [NSMutableArray array];
    for (const auto& extension : supportedModelExtensions())
        [extensions addObject:[NSString stringWithUTF8String:extension.c_str() + 1]];
    panel.allowedFileTypes = extensions;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        self.openingPanel = NO;
        if (response == NSModalResponseOK) {
            PlatformEvent event{PlatformAction::OpenFiles};
            for (NSURL* url in panel.URLs) event.paths.emplace_back(url.fileSystemRepresentation);
            self->events.push_back(std::move(event));
        }
        [self.window makeFirstResponder:self.window.contentView];
    }];
}
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.target = self;
    if ([identifier isEqualToString:@"open"]) {
        item.label = @"Open";
        item.toolTip = @"Open models (⌘O)";
        item.image = symbol(@"folder.badge.plus", @"Open models");
        item.action = @selector(open:);
    } else if ([identifier isEqualToString:@"reset"]) {
        item.label = @"Reset View";
        item.toolTip = @"Reset view (⌘0)";
        item.image = symbol(@"arrow.counterclockwise", @"Reset view");
        item.action = @selector(perform:);
        item.tag = static_cast<NSInteger>(PlatformAction::ResetView);
    } else if ([identifier isEqualToString:@"camera"]) {
        item.label = @"Hand Controls";
        item.toolTip = @"Enable hand controls";
        item.image = symbol(@"video", @"Hand controls off");
        item.action = @selector(perform:);
        item.tag = static_cast<NSInteger>(PlatformAction::ToggleCamera);
        self.cameraItem = item;
    } else {
        item.label = @"Help";
        item.toolTip = @"Polyscope Help";
        item.image = symbol(@"questionmark.circle", @"Help");
        item.action = @selector(showHelp:);
    }
    item.autovalidates = NO;
    return item;
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    return @[@"open", NSToolbarFlexibleSpaceItemIdentifier, @"reset", @"camera", @"help"];
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}
- (NSMenuItem*)item:(NSString*)title action:(SEL)action key:(NSString*)key menu:(NSMenu*)menu {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    [menu addItem:item];
    return item;
}
- (void)installMenus {
    NSMenu* bar = [[NSMenu alloc] init];
    NSMenu* app = [[NSMenu alloc] initWithTitle:@"Polyscope"];
    NSMenuItem* root = [bar addItemWithTitle:@"Polyscope" action:nil keyEquivalent:@""];
    root.submenu = app;
    [self item:@"About Polyscope" action:@selector(about:) key:@"" menu:app];
    [app addItem:NSMenuItem.separatorItem];
    [self item:@"Settings…" action:@selector(showSettings:) key:@"," menu:app];
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem* services = [self item:@"Services" action:nil key:@"" menu:app];
    services.submenu = [[NSMenu alloc] initWithTitle:@"Services"];
    NSApp.servicesMenu = services.submenu;
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem* hide = [self item:@"Hide Polyscope" action:@selector(hide:) key:@"h" menu:app];
    hide.target = NSApp;
    NSMenuItem* hideOthers = [self item:@"Hide Others" action:@selector(hideOtherApplications:) key:@"h" menu:app];
    hideOthers.target = NSApp;
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [self item:@"Show All" action:@selector(unhideAllApplications:) key:@"" menu:app].target = NSApp;
    [app addItem:NSMenuItem.separatorItem];
    [self item:@"Quit Polyscope" action:@selector(terminate:) key:@"q" menu:app].target = NSApp;

    NSMenu* file = [[NSMenu alloc] initWithTitle:@"File"];
    [bar addItemWithTitle:@"File" action:nil keyEquivalent:@""].submenu = file;
    [self item:@"Open…" action:@selector(open:) key:@"o" menu:file];
    [file addItem:NSMenuItem.separatorItem];
    [self item:@"Close Tab" action:@selector(closeActive:) key:@"w" menu:file];
    NSMenuItem* closeWindow = [self item:@"Close Window" action:@selector(performClose:) key:@"W" menu:file];
    closeWindow.target = self.window;

    NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [bar addItemWithTitle:@"Edit" action:nil keyEquivalent:@""].submenu = edit;
    for (NSArray* entry in @[@[@"Cut", @"cut:", @"x"], @[@"Copy", @"copy:", @"c"], @[@"Paste", @"paste:", @"v"], @[@"Select All", @"selectAll:", @"a"]])
        [self item:entry[0] action:NSSelectorFromString(entry[1]) key:entry[2] menu:edit].target = nil;

    NSMenu* view = [[NSMenu alloc] initWithTitle:@"View"];
    [bar addItemWithTitle:@"View" action:nil keyEquivalent:@""].submenu = view;
    NSMenuItem* reset = [self item:@"Reset View" action:@selector(perform:) key:@"0" menu:view];
    reset.tag = static_cast<NSInteger>(PlatformAction::ResetView);
    [view addItem:NSMenuItem.separatorItem];
    for (auto entry : {std::pair<NSString*, PlatformAction>(@"Show Grid", PlatformAction::ToggleGrid),
                       {@"Wireframe", PlatformAction::ToggleWireframe}, {@"Hand Controls", PlatformAction::ToggleCamera}}) {
        NSMenuItem* item = [self item:entry.first action:@selector(perform:) key:@"" menu:view];
        item.tag = static_cast<NSInteger>(entry.second);
    }
    [view addItem:NSMenuItem.separatorItem];
    NSMenuItem* next = [self item:@"Next Tab" action:@selector(perform:) key:@"\t" menu:view];
    next.keyEquivalentModifierMask = NSEventModifierFlagControl;
    next.tag = static_cast<NSInteger>(PlatformAction::NextTab);
    NSMenuItem* previous = [self item:@"Previous Tab" action:@selector(perform:) key:@"\t" menu:view];
    previous.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagShift;
    previous.tag = static_cast<NSInteger>(PlatformAction::PreviousTab);
    [view addItem:NSMenuItem.separatorItem];
    NSMenuItem* fullscreen = [self item:@"Enter Full Screen" action:@selector(toggleFullScreen:) key:@"f" menu:view];
    fullscreen.target = self.window;
    fullscreen.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;

    NSMenu* window = [[NSMenu alloc] initWithTitle:@"Window"];
    [bar addItemWithTitle:@"Window" action:nil keyEquivalent:@""].submenu = window;
    [self item:@"Minimize" action:@selector(performMiniaturize:) key:@"m" menu:window].target = nil;
    [self item:@"Zoom" action:@selector(performZoom:) key:@"" menu:window].target = nil;
    NSApp.windowsMenu = window;
    NSMenu* help = [[NSMenu alloc] initWithTitle:@"Help"];
    [bar addItemWithTitle:@"Help" action:nil keyEquivalent:@""].submenu = help;
    [self item:@"Polyscope Help" action:@selector(showHelp:) key:@"?" menu:help];
    NSApp.helpMenu = help;
    NSApp.mainMenu = bar;
}
- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if (item.action == @selector(perform:)) {
        const auto action = static_cast<PlatformAction>(item.tag);
        bool checked = false;
        if (action == PlatformAction::ToggleGrid) checked = state.grid;
        if (action == PlatformAction::ToggleWireframe) checked = state.wireframe;
        if (action == PlatformAction::ToggleCamera) checked = state.camera || state.cameraStarting;
        item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
        if (action == PlatformAction::NextTab || action == PlatformAction::PreviousTab) return state.tabs.size() > 1;
    }
    if (item.action == @selector(closeActive:)) item.title = state.tabs.empty() ? @"Close Window" : @"Close Tab";
    return YES;
}
- (void)about:(id)sender { [NSApp orderFrontStandardAboutPanel:sender]; }
- (NSPanel*)panel:(NSString*)title width:(CGFloat)width height:(CGFloat)height {
    NSPanel* panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    panel.title = title;
    panel.releasedWhenClosed = NO;
    [panel center];
    return panel;
}
- (NSTextField*)label:(NSString*)label size:(CGFloat)size bold:(BOOL)bold {
    NSTextField* field = [NSTextField wrappingLabelWithString:label];
    field.font = [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    return field;
}
- (NSStackView*)panelStack:(NSPanel*)panel {
    NSStackView* stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-28],
        [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:26]
    ]];
    return stack;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return self.shortcutRows.count;
}
- (BOOL)tableView:(NSTableView*)tableView isGroupRow:(NSInteger)row {
    return self.shortcutRows[row][1].length == 0;
}
- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
    return [self tableView:tableView isGroupRow:row] ? 32 : 28;
}
- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row { return NO; }
- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    const BOOL shortcut = [column.identifier isEqualToString:@"shortcut"];
    const BOOL group = [self tableView:tableView isGroupRow:row];
    NSString* identifier = group ? @"section" : column.identifier;
    NSTableCellView* cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = identifier;
        NSTextField* field = [NSTextField labelWithString:@""];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:field];
        cell.textField = field;
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    cell.textField.stringValue = self.shortcutRows[row][shortcut ? 1 : 0];
    cell.textField.font = [NSFont systemFontOfSize:12 weight:(group || shortcut) ? NSFontWeightSemibold : NSFontWeightRegular];
    cell.textField.textColor = group ? NSColor.secondaryLabelColor : NSColor.labelColor;
    return cell;
}
- (NSScrollView*)shortcutTable {
    self.shortcutRows = @[
        @[@"Models", @""],
        @[@"Open models", @"⌘O"],
        @[@"Close current tab", @"⌘W"],
        @[@"Next tab", @"⌃Tab"],
        @[@"Previous tab", @"⌃⇧Tab"],
        @[@"Navigation", @""],
        @[@"Orbit", @"Drag"],
        @[@"Pan", @"Right-drag or ⇧Drag"],
        @[@"Zoom", @"Scroll or trackpad pinch"],
        @[@"Reset view", @"⌘0 or R"],
        @[@"View and app", @""],
        @[@"Toggle grid", @"G"],
        @[@"Toggle wireframe", @"W"],
        @[@"Toggle hand controls", @"C"],
        @[@"Settings", @"⌘,"],
        @[@"Help", @"⌘?"],
        @[@"Full screen", @"⌃⌘F"],
        @[@"Quit", @"⌘Q"]
    ];
    NSTableView* table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 504, 440)];
    table.headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 504, 24)];
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = 28;
    table.intercellSpacing = NSMakeSize(0, 0);
    table.usesAlternatingRowBackgroundColors = YES;
    table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    table.gridColor = NSColor.separatorColor;
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    table.focusRingType = NSFocusRingTypeNone;
    table.allowsColumnReordering = NO;
    table.allowsColumnResizing = NO;
    table.floatsGroupRows = NO;
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    table.accessibilityLabel = @"Keyboard and mouse shortcuts";
    NSTableColumn* action = [[NSTableColumn alloc] initWithIdentifier:@"action"];
    action.title = @"Action";
    action.width = 225;
    action.minWidth = 190;
    NSTableColumn* shortcut = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcut.title = @"Shortcut";
    shortcut.width = 279;
    shortcut.minWidth = 240;
    [table addTableColumn:action];
    [table addTableColumn:shortcut];
    [table reloadData];
    NSScrollView* scroll = [[NSScrollView alloc] init];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = table;
    self.shortcutsTable = table;
    return scroll;
}
- (void)showHelp:(id)sender {
    if (!self.helpPanel) {
        const CGFloat screenHeight = (self.window.screen ?: NSScreen.mainScreen).visibleFrame.size.height;
        self.helpPanel = [self panel:@"Polyscope Help" width:560 height:screenHeight > 0 ? MIN(760, screenHeight - 80) : 760];
        self.helpPanel.styleMask |= NSWindowStyleMaskResizable;
        self.helpPanel.contentMinSize = NSMakeSize(560, 560);
        NSStackView* stack = [self panelStack:self.helpPanel];
        stack.spacing = 14;
        [stack.bottomAnchor constraintEqualToAnchor:self.helpPanel.contentView.bottomAnchor constant:-26].active = YES;
        [stack addArrangedSubview:[self label:@"Explore your models" size:18 bold:YES]];
        NSTextField* intro = [self label:@"Drop models into the window to open them in tabs. Each tab keeps its own view." size:12 bold:NO];
        intro.textColor = NSColor.secondaryLabelColor;
        [stack addArrangedSubview:intro];
        [intro.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        NSScrollView* shortcuts = [self shortcutTable];
        [stack addArrangedSubview:shortcuts];
        [shortcuts.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [shortcuts.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
        [shortcuts setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
        [shortcuts setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
        [stack addArrangedSubview:[self label:@"Hand controls" size:13 bold:YES]];
        NSTextField* hands = [self label:@"Open palm: orbit. Peace sign: pan. Pinch and move closer or farther: zoom. Make a fist to pause. The camera stays off until you enable it." size:12 bold:NO];
        hands.textColor = NSColor.secondaryLabelColor;
        [stack addArrangedSubview:hands];
        [hands.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    if (!self.testing) [self.helpPanel makeKeyAndOrderFront:sender];
}
- (NSButton*)setting:(NSString*)title action:(PlatformAction)action stack:(NSStackView*)stack {
    NSButton* button = [NSButton checkboxWithTitle:title target:self action:@selector(perform:)];
    button.tag = static_cast<NSInteger>(action);
    [stack addArrangedSubview:button];
    return button;
}
- (void)showSettings:(id)sender {
    if (!self.settingsPanel) {
        self.settingsPanel = [self panel:@"Settings" width:450 height:285];
        NSStackView* stack = [self panelStack:self.settingsPanel];
        [stack addArrangedSubview:[self label:@"Viewer" size:13 bold:YES]];
        self.gridSetting = [self setting:@"Show ground grid" action:PlatformAction::SetGrid stack:stack];
        [stack addArrangedSubview:[self label:@"Hand controls" size:13 bold:YES]];
        self.mirrorSetting = [self setting:@"Mirror camera preview" action:PlatformAction::SetMirror stack:stack];
        self.previewSetting = [self setting:@"Show camera preview" action:PlatformAction::SetPreview stack:stack];
        self.cameraSetting = [NSButton buttonWithTitle:@"Enable Hand Controls" target:self action:@selector(perform:)];
        self.cameraSetting.tag = static_cast<NSInteger>(PlatformAction::ToggleCamera);
        [stack addArrangedSubview:self.cameraSetting];
        NSTextField* note = [self label:@"The camera starts off. Enabling hand controls asks for camera permission only when needed." size:11 bold:NO];
        note.textColor = NSColor.secondaryLabelColor;
        [stack addArrangedSubview:note];
        [note.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [self refresh:state];
    if (!self.testing) [self.settingsPanel makeKeyAndOrderFront:sender];
}
- (void)refresh:(const PlatformState&)newState {
    bool changedTabs = state.active != newState.active || state.tabs.size() != newState.tabs.size();
    if (!changedTabs) for (size_t i = 0; i < state.tabs.size(); ++i)
        if (state.tabs[i].id != newState.tabs[i].id) changedTabs = true;
    state = newState;
    self.hint.hidden = !state.tabs.empty();
    self.tabs.hidden = state.tabs.empty();
    if (changedTabs) {
        NSView* document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 38)];
        CGFloat x = 0;
        NSView* selectedTab = nil;
        for (const auto& tab : state.tabs) {
            NSString* name = text(std::filesystem::path(tab.path).filename().string());
            const CGFloat width = MIN(220, MAX(140, [name sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12]}].width + 52));
            ModelTabView* item = [[ModelTabView alloc] initWithFrame:NSMakeRect(x, 0, width, 38)];
            item.selected = tab.id == state.active;
            NSButton* select = [NSButton buttonWithTitle:name target:self action:@selector(selectTab:)];
            select.bordered = NO;
            select.font = [NSFont systemFontOfSize:12 weight:item.selected ? NSFontWeightMedium : NSFontWeightRegular];
            select.contentTintColor = item.selected ? NSColor.labelColor : NSColor.secondaryLabelColor;
            select.lineBreakMode = NSLineBreakByTruncatingMiddle;
            select.frame = NSMakeRect(8, 5, width - 38, 28);
            select.tag = static_cast<NSInteger>(tab.id);
            select.toolTip = text(tab.path);
            select.accessibilityLabel = [@"Model tab: " stringByAppendingString:name];
            [item addSubview:select];
            NSButton* close = [NSButton buttonWithImage:symbol(@"xmark", @"Close tab") target:self action:@selector(closeTab:)];
            close.bordered = NO;
            close.imageScaling = NSImageScaleProportionallyDown;
            close.frame = NSMakeRect(width - 29, 9, 20, 20);
            close.tag = static_cast<NSInteger>(tab.id);
            close.contentTintColor = NSColor.tertiaryLabelColor;
            close.toolTip = [@"Close " stringByAppendingString:name];
            close.accessibilityLabel = close.toolTip;
            [item addSubview:close];
            [document addSubview:item];
            if (item.selected) selectedTab = item;
            x += width + 3;
        }
        document.frame = NSMakeRect(0, 0, MAX(1, x), 38);
        self.tabs.documentView = document;
        if (selectedTab) [selectedTab scrollRectToVisible:selectedTab.bounds];
    }
    if (!state.status.empty()) self.status.stringValue = text(state.status);
    else if (state.active) {
        NSString* count = [NSNumberFormatter localizedStringFromNumber:@(state.triangles) numberStyle:NSNumberFormatterDecimalStyle];
        self.status.stringValue = [count stringByAppendingString:@" triangles"];
    } else self.status.stringValue = @"Starter cube";
    NSString* title = @"Polyscope";
    for (const auto& tab : state.tabs) if (tab.id == state.active) {
        title = text(std::filesystem::path(tab.path).filename().string());
        self.window.representedURL = [NSURL fileURLWithPath:text(tab.path)];
    }
    if (!state.active) self.window.representedURL = nil;
    self.window.title = title;
    const bool enabled = state.camera || state.cameraStarting;
    self.cameraItem.image = symbol(enabled ? @"video.fill" : @"video", enabled ? @"Hand controls on" : @"Hand controls off");
    self.cameraItem.toolTip = state.cameraStarting ? @"Starting camera… Click to cancel" : (enabled ? @"Disable hand controls" : @"Enable hand controls");
    self.gridSetting.state = state.grid ? NSControlStateValueOn : NSControlStateValueOff;
    self.mirrorSetting.state = state.mirror ? NSControlStateValueOn : NSControlStateValueOff;
    self.previewSetting.state = state.preview ? NSControlStateValueOn : NSControlStateValueOff;
    self.cameraSetting.title = enabled ? @"Disable Hand Controls" : @"Enable Hand Controls";
}
@end

static PolyscopeUI* controller;

void prepareMacApp() {
    @autoreleasepool {
        controller = [[PolyscopeUI alloc] init];
        controller.originalDelegate = NSApp.delegate;
        NSApp.delegate = controller;
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"showGrid":@NO, @"mirrorCamera":@YES, @"showPreview":@YES}];
    }
}

void installMacInterface(GLFWwindow* window) {
    @autoreleasepool {
        controller.window = glfwGetCocoaWindow(window);
        controller.glfwWindow = window;
        NSWindow* native = controller.window;
        native.title = @"Polyscope";
        native.titlebarAppearsTransparent = YES;
        native.toolbarStyle = NSWindowToolbarStyleUnified;
        native.minSize = NSMakeSize(700, 480);
        [native setFrameAutosaveName:@"PolyscopeViewer"];
        NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"PolyscopeToolbar"];
        toolbar.delegate = controller;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        toolbar.allowsUserCustomization = NO;
        native.toolbar = toolbar;
        [controller installMenus];

        const CGFloat width = native.contentView.frame.size.width;
        FileDropStrip* strip = [[FileDropStrip alloc] initWithFrame:NSMakeRect(0, 0, width, 40)];
        [strip registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        __weak PolyscopeUI* weakController = controller;
        strip.openFiles = ^(NSArray<NSURL*>* urls) {
            PolyscopeUI* ui = weakController;
            if (!ui) return;
            PlatformEvent event{PlatformAction::OpenFiles};
            for (NSURL* url in urls) event.paths.emplace_back(url.fileSystemRepresentation);
            ui->events.push_back(std::move(event));
        };
        strip.autoresizingMask = NSViewWidthSizable;
        controller.tabs = [[TabScrollView alloc] initWithFrame:NSMakeRect(10, 1, width - 192, 38)];
        controller.tabs.drawsBackground = NO;
        controller.tabs.borderType = NSNoBorder;
        controller.tabs.hasHorizontalScroller = YES;
        controller.tabs.autohidesScrollers = YES;
        controller.tabs.horizontalScrollElasticity = NSScrollElasticityNone;
        controller.tabs.autoresizingMask = NSViewWidthSizable;
        [strip addSubview:controller.tabs];
        controller.hint = [NSTextField labelWithString:@"Drop 3D models here, or choose Open…"];
        controller.hint.font = [NSFont systemFontOfSize:12];
        controller.hint.textColor = NSColor.secondaryLabelColor;
        controller.hint.frame = NSMakeRect(20, 12, width - 220, 17);
        controller.hint.autoresizingMask = NSViewWidthSizable;
        [strip addSubview:controller.hint];
        controller.status = [NSTextField labelWithString:@"Starter cube"];
        controller.status.font = [NSFont systemFontOfSize:11];
        controller.status.textColor = NSColor.secondaryLabelColor;
        controller.status.alignment = NSTextAlignmentRight;
        controller.status.frame = NSMakeRect(width - 177, 12, 157, 17);
        controller.status.autoresizingMask = NSViewMinXMargin;
        [strip addSubview:controller.status];
        controller.accessory = [[NSTitlebarAccessoryViewController alloc] init];
        controller.accessory.view = strip;
        controller.accessory.layoutAttribute = NSLayoutAttributeBottom;
        controller.accessory.fullScreenMinHeight = 40;
        [native addTitlebarAccessoryViewController:controller.accessory];
        __weak PolyscopeUI* weak = controller;
        controller.magnifyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMagnify handler:^NSEvent*(NSEvent* event) {
            PolyscopeUI* ui = weak;
            if (ui && event.window == ui.window && !ui.window.attachedSheet) {
                PlatformEvent zoom{PlatformAction::Zoom};
                zoom.amount = event.magnification;
                ui->events.push_back(std::move(zoom));
                return nil;
            }
            return event;
        }];
    }
}

PlatformPreferences macPreferences() {
    @autoreleasepool {
        return {[NSUserDefaults.standardUserDefaults boolForKey:@"showGrid"],
                [NSUserDefaults.standardUserDefaults boolForKey:@"mirrorCamera"],
                [NSUserDefaults.standardUserDefaults boolForKey:@"showPreview"]};
    }
}
std::vector<PlatformEvent> takeMacEvents() {
    auto result = std::move(controller->events);
    controller->events.clear();
    return result;
}
void updateMacInterface(const PlatformState& state) {
    @autoreleasepool {
        [controller refresh:state];
        if (!controller.testing) {
            [NSUserDefaults.standardUserDefaults setBool:state.grid forKey:@"showGrid"];
            [NSUserDefaults.standardUserDefaults setBool:state.mirror forKey:@"mirrorCamera"];
            [NSUserDefaults.standardUserDefaults setBool:state.preview forKey:@"showPreview"];
        }
    }
}
void openModelPanel() {
    @autoreleasepool { [controller open:nil]; }
}
void showModelErrors(const std::vector<std::string>& errors) {
    @autoreleasepool {
        if (errors.empty()) return;
        NSAlert* alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = errors.size() == 1 ? @"Couldn't open the model" : @"Some models couldn't be opened";
        std::string message;
        for (size_t i = 0; i < std::min<size_t>(errors.size(), 6); ++i) message += errors[i] + "\n\n";
        if (errors.size() > 6) message += "And " + std::to_string(errors.size() - 6) + " more files.";
        alert.informativeText = text(message);
        [alert beginSheetModalForWindow:controller.window completionHandler:nil];
    }
}
bool macDarkAppearance() {
    @autoreleasepool {
        return [[controller.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    }
}
void shutdownMacInterface() {
    @autoreleasepool {
        if (controller.magnifyMonitor) [NSEvent removeMonitor:controller.magnifyMonitor];
        [controller.helpPanel close];
        [controller.settingsPanel close];
        controller.window.toolbar = nil;
        if (controller.accessory) [controller.window removeTitlebarAccessoryViewControllerAtIndex:0];
        NSApp.delegate = controller.originalDelegate;
        controller = nil;
    }
}

void showCameraError(const std::string& message) {
    @autoreleasepool {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"Hand controls are unavailable";
        alert.informativeText = text(message);
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Camera Settings…"];
        [alert beginSheetModalForWindow:controller.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertSecondButtonReturn)
                [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"]];
        }];
    }
}

void verifyMacInterface() {
    @autoreleasepool {
        auto require = [](bool value, const char* message) {
            if (!value) throw std::runtime_error(message);
        };
        controller.testing = YES;
        PlatformState starter;
        updateMacInterface(starter);
        require(controller.tabs.hidden && !controller.hint.hidden, "Starter must have a hint and no tabs");
        require(controller.window.toolbar.items.count == 5, "Native toolbar is incomplete");
        require(NSApp.mainMenu.numberOfItems == 6, "Standard app menus are incomplete");

        PlatformState models;
        models.tabs = {{1, "/models/First.obj"}, {2, "/models/Second.stl"}};
        models.active = 2;
        models.triangles = 1000;
        updateMacInterface(models);
        require(!controller.tabs.hidden && controller.hint.hidden, "Models must replace the starter hint");
        require(controller.tabs.documentView.subviews.count == 2, "Every model must have its own tab");
        require([controller.window.title isEqualToString:@"Second.stl"], "Title must contain only the current filename");
        NSView* first = controller.tabs.documentView.subviews.firstObject;
        require(first.subviews.count == 2, "Tabs need independent select and close controls");
        [controller selectTab:(NSButton*)first.subviews[0]];
        [controller closeTab:(NSButton*)first.subviews[1]];
        auto events = takeMacEvents();
        require(events.size() == 2 && events[0].action == PlatformAction::SelectTab && events[0].document == 1
            && events[1].action == PlatformAction::CloseTab && events[1].document == 1, "Native tab actions must address the correct document");
        [controller showHelp:nil];
        [controller showSettings:nil];
        for (NSPanel* panel in @[controller.helpPanel, controller.settingsPanel]) {
            [panel.contentView layoutSubtreeIfNeeded];
            NSStackView* stack = (NSStackView*)panel.contentView.subviews.firstObject;
            for (NSView* view in stack.arrangedSubviews) {
                const NSRect rect = [view convertRect:view.bounds toView:panel.contentView];
                require(NSMinY(rect) >= -1 && NSMaxY(rect) <= panel.contentView.bounds.size.height + 1,
                    "Help or Settings content overflows its window");
            }
        }
        require(controller.mirrorSetting.state == NSControlStateValueOn, "Selfie mirroring must be the default");
        require([controller.cameraSetting.title isEqualToString:@"Enable Hand Controls"], "Camera must be off at launch");
        updateMacInterface(starter);
        require(controller.tabs.hidden, "Closing all documents must restore the starter");
        controller.testing = NO;
    }
}
