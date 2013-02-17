//
//  INSAppDelegate.m
//  INSOCKSServer
//
//  Created by Indragie Karunaratne on 2013-02-16.
//  Copyright (c) 2013 indragie. All rights reserved.
//

#import "INSAppDelegate.h"

@implementation INSAppDelegate {
	INSOCKSServer *_server;
}

- (IBAction)startServer:(id)sender
{
	NSError *error = nil;
	// Start the server on a random port
	_server = [[INSOCKSServer alloc] initWithPort:0 error:&error];
	_server.delegate = self;
	if (error) {
		NSLog(@"Error starting server: %@, %@", error, error.userInfo);
	} else {
		self.statusField.stringValue = [NSString stringWithFormat:@"Listening on port %d", _server.port];
		NSLog(@"SOCKS server on host %@ listening on port %d", _server.host, _server.port);
		self.informativeTextField.stringValue = [NSString stringWithFormat:@"Connect to IP address %@ on port %d.", [self.class localIPAddress], _server.port];
	}
}

- (IBAction)stopServer:(id)sender
{
	[_server disconnectAll];
	_server = nil;
	self.statusField.stringValue = @"Not Connected";
	self.informativeTextField.stringValue = @"Click \"Start Server\" to start the SOCKS server.";
}

+ (NSString *)localIPAddress
{
	__block NSString *address = nil;
	[[[NSHost currentHost] addresses] enumerateObjectsUsingBlock:^(NSString *a, NSUInteger idx, BOOL *stop) {
		if (![a isEqual:@"127.0.0.1"] && ([a componentsSeparatedByString:@"."].count == 4)) {
			address = a;
			*stop = YES;
		}
	}];
	return address;
}
#pragma mark - INSOCKSServerDelegate

- (void)SOCKSServer:(INSOCKSServer *)server didAcceptConnection:(INSOCKSConnection *)connection
{
	NSLog(@"SOCKS server accepted connection: %@", connection);
	self.activeConnection = connection;
	connection.delegate = self;
}

- (void)SOCKSServer:(INSOCKSServer *)server didDisconnectWithError:(NSError *)error
{
	NSLog(@"SOCKS server disconnected with error: %@, %@", error, error.userInfo);
}

#pragma mark - INSOCKSConnectionDelegate

- (void)SOCKSConnection:(INSOCKSConnection *)connection didDisconnectWithError:(NSError *)error
{
	NSLog(@"SOCKS connection %@ disconnected with error: %@, %@", self, error, error.userInfo);
}

- (void)SOCKSConnection:(INSOCKSConnection *)connection TCPConnectionDidFailWithError:(NSError *)error
{
	NSLog(@"SOCKS connection %@ TCP connection did fail with error: %@, %@", connection, error, error.userInfo);
}

- (void)SOCKSConnection:(INSOCKSConnection *)connection didEncounterErrorDuringSOCKS5Handshake:(NSError *)error
{
	NSLog(@"SOCKS connection %@ did encounter error during SOCKS5 handshake: %@, %@", connection, error, error.userInfo);
}

- (void)SOCKSConnectionHandshakeSucceeded:(INSOCKSConnection *)connection
{
	NSLog(@"SOCKS connection %@ handshake succeeded", connection);
}

- (void)SOCKSConnection:(INSOCKSConnection *)connection didConnectToHost:(NSString *)host port:(uint16_t)port
{
	NSLog(@"SOCKS connection %@ connected to host %@ port %d", connection, host, port);
}
@end
