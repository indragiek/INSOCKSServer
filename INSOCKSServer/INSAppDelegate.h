//
//  INSAppDelegate.h
//  INSOCKSServer
//
//  Created by Indragie Karunaratne on 2013-02-16.
//  Copyright (c) 2013 indragie. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "INSOCKSServer.h"

@interface INSAppDelegate : NSObject <NSApplicationDelegate, INSOCKSConnectionDelegate, INSOCKSServerDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (nonatomic, weak) IBOutlet NSTextField *sentField;
@property (nonatomic, weak) IBOutlet NSTextField *receivedField;
@property (nonatomic, weak) IBOutlet NSTextField *statusField;
@property (nonatomic, weak) IBOutlet NSTextField *informativeTextField;
- (IBAction)startServer:(id)sender;
- (IBAction)stopServer:(id)sender;
@end
