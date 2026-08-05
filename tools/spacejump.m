// spacejump [left|right|<spaceID>] - switch Space via SkyLight private APIs.
// No args: print current space + ordered space list for the main display.
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef int CGSConnectionID;
typedef int (*fn_conn)(void);
typedef int (*fn_activeSpace)(CGSConnectionID);
typedef CFArrayRef (*fn_displaySpaces)(CGSConnectionID);
typedef void (*fn_setSpace)(CGSConnectionID, CFStringRef, int);

int main(int argc, char **argv) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!h) { fprintf(stderr, "dlopen failed\n"); return 1; }
        fn_conn mainConn = (fn_conn)dlsym(h, "CGSMainConnectionID");
        fn_activeSpace activeSpace = (fn_activeSpace)dlsym(h, "CGSGetActiveSpace");
        fn_displaySpaces displaySpaces = (fn_displaySpaces)dlsym(h, "CGSCopyManagedDisplaySpaces");
        fn_setSpace setSpace = (fn_setSpace)dlsym(h, "CGSManagedDisplaySetCurrentSpace");
        if (!mainConn || !activeSpace || !displaySpaces) {
            fprintf(stderr, "dlsym failed: conn=%p active=%p disp=%p set=%p\n",
                    mainConn, activeSpace, displaySpaces, setSpace);
            return 1;
        }

        CGSConnectionID cid = mainConn();
        int current = activeSpace(cid);
        NSArray *displays = CFBridgingRelease(displaySpaces(cid));

        // find the display containing the current space
        NSString *displayID = nil;
        NSArray *spaceList = nil;
        for (NSDictionary *d in displays) {
            for (NSDictionary *s in d[@"Spaces"]) {
                if ([s[@"ManagedSpaceID"] intValue] == current) {
                    displayID = d[@"Display Identifier"];
                    spaceList = d[@"Spaces"];
                    break;
                }
            }
            if (displayID) break;
        }

        if (argc < 2) {
            printf("connection   : %d\n", cid);
            printf("active space : %d\n", current);
            printf("display      : %s\n", displayID.UTF8String ?: "(none)");
            printf("setSpace sym : %s\n", setSpace ? "FOUND" : "MISSING");
            printf("spaces       :");
            for (NSDictionary *s in spaceList)
                printf(" %d(type=%d)", [s[@"ManagedSpaceID"] intValue], [s[@"type"] intValue]);
            printf("\n");
            return 0;
        }

        if (!setSpace) { fprintf(stderr, "CGSManagedDisplaySetCurrentSpace unavailable\n"); return 2; }
        if (!displayID) { fprintf(stderr, "could not locate display for space %d\n", current); return 3; }

        // build user-space (type 0) list, in order
        // include fullscreen/tiled spaces (type 4) too -- native ctrl+arrow
        // moves through them, so excluding them made them unreachable
        NSMutableArray *ids = [NSMutableArray array];
        for (NSDictionary *s in spaceList)
            [ids addObject:s[@"ManagedSpaceID"]];

        int target = 0;
        NSString *arg = @(argv[1]);
        if ([arg isEqualToString:@"left"] || [arg isEqualToString:@"right"]) {
            NSUInteger idx = [ids indexOfObject:@(current)];
            if (idx == NSNotFound) { fprintf(stderr, "current space not in list\n"); return 4; }
            NSInteger next = (NSInteger)idx + ([arg isEqualToString:@"right"] ? 1 : -1);
            if (next < 0 || next >= (NSInteger)ids.count) { printf("at edge, no move\n"); return 0; }
            target = [ids[next] intValue];
        } else {
            target = arg.intValue;
        }

        setSpace(cid, (__bridge CFStringRef)displayID, target);
        usleep(400000);
        printf("requested %d -> %d ; now on %d\n", current, target, activeSpace(cid));
    }
    return 0;
}
