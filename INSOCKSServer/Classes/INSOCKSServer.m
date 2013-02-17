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

/* +----+----------+----------+
 |VER | NMETHODS | METHODS  |
 +----+----------+----------+
 | 1  |    1     | 1 to 255 |
 +----+----------+----------+ */

typedef NS_ENUM(NSInteger, INSOCKS5HandshakePhase) {
	INSOCKS5HandshakePhaseVersion = 0,
	INSOCKS5HandshakePhaseNumberOfAuthenticationMethods,
	INSOCKS5HandshakePhaseAuthenticationMethod,
};

/*
 +----+-----+-------+------+----------+----------+
 |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
 +----+-----+-------+------+----------+----------+
 | 1  |  1  | X'00' |  1   | Variable |    2     |
 +----+-----+-------+------+----------+----------+
 
 o  VER    protocol version: X'05'
 o  CMD
	o  CONNECT X'01'
	o  BIND X'02'
	o  UDP ASSOCIATE X'03'
 o  RSV    RESERVED
 o  ATYP   address type of following address
	o  IP V4 address: X'01'
	o  DOMAINNAME: X'03'
	o  IP V6 address: X'04'
 o  DST.ADDR       desired destination address
 o  DST.PORT desired destination port in network octet
 order 
 */

typedef NS_ENUM(NSInteger, INSOCKS5RequestPhase) {
	INSOCKS5RequestPhaseHeaderFragment = 10,
	INSOCKS5RequestPhaseAddressType,
	INSOCKS5RequestPhaseIPv4Address,
	INSOCKS5RequestPhaseIPv6Address,
	INSOCKS5RequestPhaseDomainName,
	INSOCKS5RequestPhasePort
};

/*
 +----+-----+-------+------+----------+----------+
 |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
 +----+-----+-------+------+----------+----------+
 | 1  |  1  | X'00' |  1   | Variable |    2     |
 +----+-----+-------+------+----------+----------+
 
 o  VER    protocol version: X'05'
 o  REP    Reply field:
	o  X'00' succeeded
	o  X'01' general SOCKS server failure
	o  X'02' connection not allowed by ruleset
	o  X'03' Network unreachable
	o  X'04' Host unreachable
	o  X'05' Connection refused
	o  X'06' TTL expired
	o  X'07' Command not supported
	o  X'08' Address type not supported
	o  X'09' to X'FF' unassigned
	o  RSV    RESERVED
 o  ATYP   address type of following address
	o  IP V4 address: X'01'
	o  DOMAINNAME: X'03'
	o  IP V6 address: X'04'
 o  BND.ADDR       server bound address
 o  BND.PORT       server bound port in network octet order
 */

typedef NS_ENUM(uint8_t, INSOCKS5HandshakeReplyType) {
	INSOCKS5HandshakeReplySucceeded = 0x00,
	INSOCKS5HandshakeReplyGeneralSOCKSServerFailure = 0x01,
	INSOCKS5HandshakeReplyConnectionNotAllowedByRuleset = 0x02,
	INSOCKS5HandshakeReplyNetworkUnreachable = 0x03,
	INSOCKS5HandshakeReplyHostUnreachable = 0x04,
	INSOCKS5HandshakeReplyConnectionRefused = 0x05,
	INSOCKS5HandshakeReplyTTLExpired = 0x06,
	INSOCKS5HandshakeReplyCommandNotSupported = 0x07,
	INSOCKS5HandshakeReplyAddressTypeNotSupported = 0x08
};

/*
 o  X'00' NO AUTHENTICATION REQUIRED
 o  X'01' GSSAPI
 o  X'02' USERNAME/PASSWORD
 o  X'03' to X'7F' IANA ASSIGNED
 o  X'80' to X'FE' RESERVED FOR PRIVATE METHODS
 o  X'FF' NO ACCEPTABLE METHODS
 */

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
		case INSOCKS5HandshakePhaseVersion:
			[self readSOCKS5VersionFromData:data];
			break;
		case INSOCKS5HandshakePhaseNumberOfAuthenticationMethods:
			[self readSOCKS5NumberOfAuthenticationMethodsFromData:data];
			break;
		case INSOCKS5HandshakePhaseAuthenticationMethod:
			[self readSOCKS5AuthenticationMethodsFromData:data];
			break;
		case INSOCKS5RequestPhaseHeaderFragment:
			[self readSOCKS5HeaderFragmentFromData:data];
			break;
		case INSOCKS5RequestPhaseAddressType:
			[self readSOCKS5AddressTypeFromData:data];
			break;
		case INSOCKS5RequestPhaseIPv4Address:
			[self readSOCKS5IPv4AddressFromData:data];
			break;
		case INSOCKS5RequestPhaseIPv6Address:
			[self readSOCKS5IPv6AddressFromData:data];
			break;
		case INSOCKS5RequestPhaseDomainName:
			[self readSOCKS5DomainNameFromData:data];
			break;
		case INSOCKS5RequestPhasePort:
			[self readSOCKS5PortFromData:data];
			break;
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
			[_socket readDataToLength:3 withTimeout:INSOCKS5SocketTimeout tag:INSOCKS5RequestPhaseHeaderFragment];
		} else {
			[self sendSOCKSHandshakeCommandNotSupportedResponse];
			[self notifySOCKS5HandshakeErrorWithDescription:@"No supported authentication method."];
		}
		
	} else {
		[self sendSOCKSHandshakeCommandNotSupportedResponse];
		[self notifySOCKS5HandshakeErrorWithDescription:@"Could not read authentication methods"];
	}
}

- (void)readSOCKS5HeaderFragmentFromData:(NSData *)data
{
	
}

- (void)readSOCKS5AddressTypeFromData:(NSData *)data
{
	
}

- (void)readSOCKS5IPv4AddressFromData:(NSData *)data
{
	
}

- (void)readSOCKS5IPv6AddressFromData:(NSData *)data
{
	
}

- (void)readSOCKS5DomainNameFromData:(NSData *)data
{
	
}

- (void)readSOCKS5PortFromData:(NSData *)data
{
	
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

+ (NSData *)replyDataForResponseType:(INSOCKS5HandshakeReplyType)type
{
	const unsigned char bytes[3] = {0x05, type, 0x00};
	return [NSData dataWithBytes:bytes length:3];
}

- (void)sendSOCKS5HandshakeSucceededResponse
{
	[_socket writeData:[self.class replyDataForResponseType:INSOCKS5HandshakeReplySucceeded] withTimeout:INSOCKS5SocketTimeout tag:0];
}

- (void)sendSOCKSHandshakeCommandNotSupportedResponse
{
	[_socket writeData:[self.class replyDataForResponseType:INSOCKS5HandshakeReplyConnectionRefused] withTimeout:INSOCKS5SocketTimeout tag:0];
}
@end
