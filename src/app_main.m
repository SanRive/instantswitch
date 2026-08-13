//
// InstantSwitch, standalone menu bar app.
//
// Replaces the Hammerspoon half of this project: owns the mouse-button event
// tap itself, so Hammerspoon is not needed at all.
//
// Runs as an accessory app (LSUIElement), so there is no Dock icon, only the
// menu bar item, which doubles as a reminder that it is running.
//
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <ApplicationServices/ApplicationServices.h>

#include "include/ISS.h"
#include "predictions.h"

// Mouse buttons. 3 = "back" (space left), 4 = "forward" (space right).
static const int64_t kButtonBack    = 3;
static const int64_t kButtonForward = 4;

static const double kDefaultGestureSpeed = 500.0;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSStatusItem *statusItem;
@property(assign) CFMachPortRef mouseTap;
@property(assign) CFRunLoopSourceRef mouseSource;
@property(assign) BOOL enabled;
@property(assign) BOOL permitted;
@end

static AppDelegate *gDelegate = nil;

// The tap must not consume anything it does not handle, or it would break
// every other mouse button system-wide.
static CGEventRef mouseTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    AppDelegate *self = (__bridge AppDelegate *)refcon;

    // macOS disables a tap that is too slow or that user input interrupted.
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (self.mouseTap) CGEventTapEnable(self.mouseTap, true);
        return event;
    }
    if (!self.enabled || type != kCGEventOtherMouseDown) return event;

    int64_t button = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    ISSDirection dir;
    if (button == kButtonBack)         dir = ISSDirectionLeft;
    else if (button == kButtonForward) dir = ISSDirectionRight;
    else return event;   // not ours, pass it through untouched

    predictions_refresh_if_stale();
    iss_switch(dir);
    return NULL;         // swallow, so apps do not also go back/forward
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.enabled = YES;
    self.permitted = AXIsProcessTrusted();

    [self buildStatusItem];

    if (!iss_init()) {
        self.permitted = NO;
    } else {
        iss_set_gesture_speed(kDefaultGestureSpeed);
        [self installMouseTap];
    }
    [self refreshMenu];
}

- (void)buildStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"rectangle.3.group"
                             accessibilityDescription:@"InstantSwitch"];
    if (icon) {
        icon.template = YES;
        self.statusItem.button.image = icon;
    } else {
        self.statusItem.button.title = @"⇄";   // pre-SF-Symbols fallback
    }
    self.statusItem.menu = [[NSMenu alloc] init];
}

- (void)installMouseTap {
    CGEventMask mask = CGEventMaskBit(kCGEventOtherMouseDown);
    self.mouseTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault, mask,
                                     mouseTapCallback, (__bridge void *)self);
    if (!self.mouseTap) { self.permitted = NO; return; }

    self.mouseSource = CFMachPortCreateRunLoopSource(NULL, self.mouseTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), self.mouseSource, kCFRunLoopCommonModes);
    CGEventTapEnable(self.mouseTap, true);
}

- (void)refreshMenu {
    NSMenu *m = self.statusItem.menu;
    [m removeAllItems];

    NSString *status = !self.permitted ? @"⚠︎  Needs permission"
                     : (self.enabled   ? @"Active"
                                       : @"Paused");
    [[m addItemWithTitle:status action:nil keyEquivalent:@""] setEnabled:NO];
    [m addItem:[NSMenuItem separatorItem]];

    [[m addItemWithTitle:@"Button 4  →  space right" action:nil keyEquivalent:@""] setEnabled:NO];
    [[m addItemWithTitle:@"Button 3  →  space left"  action:nil keyEquivalent:@""] setEnabled:NO];
    [m addItem:[NSMenuItem separatorItem]];

    if (self.permitted) {
        NSMenuItem *toggle = [m addItemWithTitle:@"Enabled"
                                          action:@selector(toggleEnabled:)
                                   keyEquivalent:@""];
        toggle.target = self;
        toggle.state = self.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else {
        NSMenuItem *open = [m addItemWithTitle:@"Open Privacy Settings…"
                                        action:@selector(openSettings:)
                                 keyEquivalent:@""];
        open.target = self;
        [[m addItemWithTitle:@"  Privacy & Security ▸" action:nil keyEquivalent:@""] setEnabled:NO];
        [[m addItemWithTitle:@"  Device Control and Data Access" action:nil keyEquivalent:@""] setEnabled:NO];
    }

    NSMenuItem *login = [m addItemWithTitle:@"Open at Login"
                                     action:@selector(toggleOpenAtLogin:)
                              keyEquivalent:@""];
    login.target = self;
    login.state = [self opensAtLogin] ? NSControlStateValueOn : NSControlStateValueOff;

    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [m addItemWithTitle:@"Quit InstantSwitch"
                                    action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;

    self.statusItem.button.toolTip = self.permitted
        ? @"InstantSwitch: side buttons switch Spaces"
        : @"InstantSwitch: needs permission to run";
    self.statusItem.button.appearsDisabled = !self.permitted || !self.enabled;
}

- (BOOL)opensAtLogin {
    return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
}

- (void)toggleOpenAtLogin:(id)sender {
    SMAppService *svc = [SMAppService mainAppService];
    NSError *err = nil;
    BOOL ok = [self opensAtLogin] ? [svc unregisterAndReturnError:&err]
                                  : [svc registerAndReturnError:&err];
    if (!ok && err) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Could not change the login item";
        // Most commonly: the app is not in a stable location such as
        // /Applications, or the user disabled it in System Settings.
        a.informativeText = err.localizedDescription;
        [a runModal];
    }
    [self refreshMenu];
}

- (void)toggleEnabled:(id)sender {
    self.enabled = !self.enabled;
    [self refreshMenu];
}

- (void)openSettings:(id)sender {
    // Same pane on macOS 27, where it is presented as
    // "Device Control and Data Access".
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    if (self.mouseTap) CGEventTapEnable(self.mouseTap, false);
    iss_destroy();
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        // Accessory: menu bar item only, no Dock icon, no main window.
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        gDelegate = [[AppDelegate alloc] init];
        app.delegate = gDelegate;
        [app run];
    }
    return 0;
}
