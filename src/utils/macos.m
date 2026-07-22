#import <AppKit/AppKit.h>

#include "macos.h"

void macos_disable_native_close_shortcut(void) {
  @autoreleasepool {
    NSMenu *window_menu = NSApp.windowsMenu;
    for (NSMenuItem *item in window_menu.itemArray) {
      if (item.action == @selector(performClose:) &&
          [item.keyEquivalent caseInsensitiveCompare:@"w"] == NSOrderedSame) {
        item.keyEquivalent = @"";
      }
    }
  }
}
