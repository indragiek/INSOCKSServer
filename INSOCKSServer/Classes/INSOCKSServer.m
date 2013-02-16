//
//  INSOCKSServer.m
//  INSOCKSServer
//
//  Created by Indragie Karunaratne on 2013-02-16.
//  Copyright (c) 2013 Indragie Karunaratne
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
// TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
//

#import "INSOCKSServer.h"

@interface INSOCKSConnection ()
- (id)initWithSocket:(GCDAsyncSocket *)socket;
@end

@implementation INSOCKSServer {
	NSMutableArray *_connections;
	struct {
		unsigned int didAcceptConnection : 1;
		unsigned int didDisconnectWithError : 1;
	} _delegateFlags;
}
@synthesize connections = _connections;

#pragma mark - Initialization

- (instancetype)initWithPort:(uint16_t)port error:(NSError **)error
{
	if ((self = [super init])) {
		_port = port;
		_connections = [NSMutableArray array];
		// Create a master socket to start accepting incoming connections to the proxy
		_socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		NSError *socketError = nil;
		if (![_socket acceptOnPort:port error:&socketError]) {
			if (error) *error = socketError;
			return nil;
		}
	}
	return self;
}

#pragma mark - Accessors

- (void)setDelegate:(id<INSOCKSServerDelegate>)delegate
{
	if (_delegate != delegate) {
		_delegate = delegate;
		_delegateFlags.didAcceptConnection = [delegate respondsToSelector:@selector(SOCKSServer:didAcceptConnection:)];
		_delegateFlags.didDisconnectWithError = [delegate respondsToSelector:@selector(SOCKSServer:didDisconnectWithError:)];
	}
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
	INSOCKSConnection *connection = [[INSOCKSConnection alloc] initWithSocket:newSocket];
	[_connections addObject:connection];
	if (_delegateFlags.didAcceptConnection) {
		[self.delegate SOCKSServer:self didAcceptConnection:connection];
	}
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	if (_delegateFlags.didDisconnectWithError) {
		[self.delegate SOCKSServer:self didDisconnectWithError:err];
	}
}
@end

typedef NS_ENUM(NSInteger, INSOCKS5HandshakePhase) {
	INSOCKS5HandshakePhaseVersion = 0,
	INSOCKS5HandshakePhaseNumberOfAuthenticationMethods,
	INSOCKS5HandshakePhaseAuthenticationMethod,
	INSOCKS5HandshakePhaseRequest,
	INSOCKS5HandshakePhaseProxy
};

typedef NS_ENUM(uint8_t, INSOCKS5HandshakeReply) {
	INSOCKS5HandshakeSucceeded = 0x00,
	INSOCKS5HandshakeGeneralSOCKSServerFailure = 0x01,
	INSOCKS5HandshakeConnectionNotAllowedByRuleset = 0x02,
	INSOCKS5HandshakeNetworkUnreachable = 0x03,
	INSOCKS5HandshakeHostUnreachable = 0x04,
	INSOCKS5HandshakeConnectionRefused = 0x05,
	INSOCKS5HandshakeTTLExpired = 0x06,
	INSOCKS5HandshakeCommandNotSupported = 0x07,
	INSOCKS5HandshakeAddressTypeNotSupported = 0x08
};

typedef NS_ENUM(uint8_t, INSOCKS5AuthenticationMethod) {
	INSOCKS5AuthenticationNone = 0x00,
	INSOCKS5AuthenticationGSSAPI = 0x01,
	INSOCKS5AuthenticationUsernamePassword = 0x02
};

static NSTimeInterval const INSOCKS5SocketTimeout = 15.0;
static NSString * const INSOCKS5ConnectionErrorDomain = @"INSOCKS5ConnectionErrorDomain";
static uint8_t const INSOCKS5HandshakeVersion5 = 0x05;

@implementation INSOCKSConnection {
	struct {
		unsigned int didDisconnectWithError : 1;
		unsigned int didEncounterErrorDuringSOCKS5Handshake : 1;
	} _delegateFlags;
	uint8_t _numberOfAuthenticationMethods;
}

#pragma mark - Initialization

- (id)initWithSocket:(GCDAsyncSocket *)socket
{
	if ((self = [super init])) {
		_socket = socket;
		[_socket setDelegate:self];
		// Begins the chain reaction that constitutes the SOCKS5 handshake
		[self beginSOCKS5Handshake];
	}
	return self;
}

#pragma mark - SOCKS5 Handshake Implementation

- (void)beginSOCKS5Handshake
{
	[_socket readDataToLength:1 withTimeout:INSOCKS5SocketTimeout tag:INSOCKS5HandshakePhaseVersion];
}

#pragma mark - Accessors

- (void)setDelegate:(id<INSOCKSConnectionDelegate>)delegate
{
	if (_delegate != delegate) {
		_delegate = delegate;
		_delegateFlags.didDisconnectWithError = [delegate respondsToSelector:@selector(SOCKSConnection:didDisconnectWithError:)];
		_delegateFlags.didEncounterErrorDuringSOCKS5Handshake = [delegate respondsToSelector:@selector(SOCKSConnection:didEncounterErrorDuringSOCKS5Handshake:)];
	}
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	if (_delegateFlags.didDisconnectWithError) {
		[self.delegate SOCKSConnection:self didDisconnectWithError:err];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	switch (tag) {
		case INSOCKS5HandshakePhaseVersion: {
			[self readSOCKS5VersionFromData:data];
			break;
		}
		case INSOCKS5HandshakePhaseNumberOfAuthenticationMethods: {
			[self readSOCKS5NumberOfAuthenticationMethodsFromData:data];
			break;
		}
		case INSOCKS5HandshakePhaseAuthenticationMethod: {
			[self readSOCKS5AuthenticationMethodsFromData:data];
			break;
		}
		default:
			break;
	}
}

- (void)readSOCKS5VersionFromData:(NSData *)data
{
	uint8_t version;
	[data getBytes:&version length:1];
	if (version == INSOCKS5HandshakeVersion5) { // SOCKS Protocol Version 5
		[_socket readDataToLength:1 withTimeout:INSOCKS5SocketTimeout tag:INSOCKS5HandshakePhaseNumberOfAuthenticationMethods];
	} else {
		[self sendSOCKSHandshakeCommandNotSupportedResponse];
		[self notifySOCKS5HandshakeErrorWithDescription:@"Invalid SOCKS protocol version."];
	}
}

- (void)readSOCKS5NumberOfAuthenticationMethodsFromData:(NSData *)data
{
	[data getBytes:&_numberOfAuthenticationMethods length:1];
	[_socket readDataToLength:_numberOfAuthenticationMethods withTimeout:INSOCKS5SocketTimeout tag:INSOCKS5HandshakePhaseAuthenticationMethod];
}

- (void)readSOCKS5AuthenticationMethodsFromData:(NSData *)data
{
	uint8_t authMethods[_numberOfAuthenticationMethods];
	if (sizeof(authMethods) == [data length]) {
		BOOL hasSupportedAuthMethod = NO;
		// TODO: Add support for username/password authentication as well
		for (int i = 0; i < sizeof(authMethods); i++) {
			if (authMethods[i] == INSOCKS5AuthenticationNone) {
				hasSupportedAuthMethod = YES;
				break;
			}
		}
		if (hasSupportedAuthMethod) {
			[self sendSOCKS5HandshakeSucceededResponse];
			[_socket readDataToLength:3 withTimeout:INSOCKS5SocketTimeout tag:INSOCKS5HandshakePhaseRequest];
		} else {
			[self sendSOCKSHandshakeCommandNotSupportedResponse];
			[self notifySOCKS5HandshakeErrorWithDescription:@"No supported authentication method."];
		}
		
	} else {
		[self sendSOCKSHandshakeCommandNotSupportedResponse];
		[self notifySOCKS5HandshakeErrorWithDescription:@"Could not read authentication methods"];
	}
}

#pragma mark - Private

// Notifies delegate of an error during the SOCKS5 handshake and disconnects the socket
- (void)notifySOCKS5HandshakeErrorWithDescription:(NSString *)description
{
	if (!_delegateFlags.didEncounterErrorDuringSOCKS5Handshake || ![description length]) return;
	NSError *error = [NSError errorWithDomain:INSOCKS5ConnectionErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : description}];
	[self.delegate SOCKSConnection:self didEncounterErrorDuringSOCKS5Handshake:error];
	[_socket disconnectAfterWriting];
}

- (void)sendSOCKS5HandshakeSucceededResponse
{
	static const unsigned char bytes[1] = {INSOCKS5HandshakeSucceeded};
	[_socket writeData:[NSData dataWithBytes:bytes length:1] withTimeout:INSOCKS5SocketTimeout tag:0];
}

- (void)sendSOCKSHandshakeCommandNotSupportedResponse
{
	static const unsigned char bytes[2] = {INSOCKS5HandshakeConnectionRefused, INSOCKS5HandshakeCommandNotSupported};
	[_socket writeData:[NSData dataWithBytes:bytes length:2] withTimeout:INSOCKS5SocketTimeout tag:0];
}
@end
