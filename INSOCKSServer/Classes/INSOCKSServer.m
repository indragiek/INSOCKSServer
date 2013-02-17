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
#import <netinet/in.h>
#import <arpa/inet.h>

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
	INSOCKS5RequestPhaseDomainNameLength,
	INSOCKS5RequestPhaseDomainName,
	INSOCKS5RequestPhasePort
};

typedef NS_ENUM(uint8_t, INSOCKS5AddressType) {
	INSOCKS5AddressTypeIPv4 = 0x01,
	INSOCKS5AddressTypeIPv6 = 0x04,
	INSOCKS5AddressTypeDomainName = 0x03
};

typedef NS_ENUM(uint8_t, INSOCKS5Command) {
	INSOCKS5CommandConnect = 0x01,
	INSOCKS5CommandBind = 0x02,
	INSOCKS5UDPAssociate = 0x03
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
	uint8_t _requestCommandCode;
	NSMutableData *_addressData;
	uint8_t _domainNameLength;
	NSString *_targetHost;
	NSUInteger _targetPort;
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
	[self readDataForSOCKS5Tag:INSOCKS5HandshakePhaseVersion];
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
	NSUInteger length = [self.class dataLengthForSOCKS5Tag:tag];
	if (!length) return;
	switch (tag) {
		case INSOCKS5HandshakePhaseVersion:
			[self readSOCKS5VersionFromData:data expectedLength:length];
			break;
		case INSOCKS5HandshakePhaseNumberOfAuthenticationMethods:
			[self readSOCKS5NumberOfAuthenticationMethodsFromData:data expectedLength:length];
			break;
		case INSOCKS5HandshakePhaseAuthenticationMethod:
			[self readSOCKS5AuthenticationMethodsFromData:data];
			break;
		case INSOCKS5RequestPhaseHeaderFragment:
			[self readSOCKS5HeaderFragmentFromData:data expectedLength:length];
			break;
		case INSOCKS5RequestPhaseAddressType:
			[self readSOCKS5AddressTypeFromData:data expectedLength:length];
			break;
		case INSOCKS5RequestPhaseIPv4Address:
			[self readSOCKS5IPv4AddressFromData:data expectedLength:length];
			break;
		case INSOCKS5RequestPhaseIPv6Address:
			[self readSOCKS5IPv6AddressFromData:data expectedLength:length];
			break;
		case INSOCKS5RequestPhaseDomainNameLength:
			[self readSOCKS5DomainNameLengthFromData:data expectedLength:length];
			break;
		case INSOCKS5RequestPhaseDomainName:
			[self readSOCKS5DomainNameFromData:data];
			break;
		case INSOCKS5RequestPhasePort:
			[self readSOCKS5PortFromData:data expectedLength:length];
			break;
		default:
			break;
	}
}

- (void)readSOCKS5VersionFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	void(^failureBlock)() = ^{
		[self refuseConnectionWithErrorDescription:@"Invalid SOCKS protocol version."];
	};
	if ([data length] == length) {
		uint8_t version;
		[data getBytes:&version length:length];
		if (version == INSOCKS5HandshakeVersion5) { // SOCKS Protocol Version 5
			[self readDataForSOCKS5Tag:INSOCKS5HandshakePhaseNumberOfAuthenticationMethods];
		} else {
			failureBlock();
		}
	} else {
		failureBlock();
	}
}

- (void)readSOCKS5NumberOfAuthenticationMethodsFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		[data getBytes:&_numberOfAuthenticationMethods length:length];
		[_socket readDataToLength:_numberOfAuthenticationMethods withTimeout:INSOCKS5SocketTimeout tag:INSOCKS5HandshakePhaseAuthenticationMethod];
	} else {
		[self refuseConnectionWithErrorDescription:@"Unable to retrieve number of authentication methods."];
	}
}

- (void)readSOCKS5AuthenticationMethodsFromData:(NSData *)data
{
	uint8_t authMethods[_numberOfAuthenticationMethods];
	if ([data length] == sizeof(authMethods)) {
		BOOL hasSupportedAuthMethod = NO;
		// TODO: Add support for username/password authentication as well
		for (int i = 0; i < sizeof(authMethods); i++) {
			if (authMethods[i] == INSOCKS5AuthenticationNone) {
				hasSupportedAuthMethod = YES;
				break;
			}
		}
		if (hasSupportedAuthMethod) {
			[self readDataForSOCKS5Tag:INSOCKS5RequestPhaseHeaderFragment];
		} else {
			[self refuseConnectionWithErrorDescription:@"No supported authentication method."];
		}
		
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read authentication methods"];
	}
}

- (void)readSOCKS5HeaderFragmentFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		uint8_t header[length];
		[data getBytes:&header length:length];
		
		uint8_t version = header[0];
		if (version != INSOCKS5HandshakeVersion5) {
			[self refuseConnectionWithErrorDescription:@"Invalid SOCKS protocol version."];
			return;
		}
		
		_requestCommandCode = header[1];
		// Third byte is just a reserved paramter (0x00);
		[self readDataForSOCKS5Tag:INSOCKS5RequestPhaseAddressType];
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read request header."];
	}
}

- (void)readSOCKS5AddressTypeFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		_addressData = [NSMutableData dataWithData:data];
		uint8_t addressType;
		[data getBytes:&addressType length:length];
		
		switch (addressType) {
			case INSOCKS5AddressTypeIPv4:
				[self readDataForSOCKS5Tag:INSOCKS5RequestPhaseIPv4Address];
				break;
			case INSOCKS5AddressTypeIPv6:
				[self readDataForSOCKS5Tag:INSOCKS5RequestPhaseIPv6Address];
				break;
			case INSOCKS5AddressTypeDomainName:
				[self readDataForSOCKS5Tag:INSOCKS5RequestPhaseDomainNameLength];
				break;
			default:
				break;
		}
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read address type."];
	}
}

- (void)readSOCKS5IPv4AddressFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		uint8_t address[length];
		[data getBytes:&address length:length];
		[_addressData appendBytes:address length:length];
		char ip[INET_ADDRSTRLEN];
		_targetHost = [NSString stringWithCString:inet_ntop(AF_INET, address, ip, sizeof(ip)) encoding:NSUTF8StringEncoding];
		[self readDataForSOCKS5Tag:INSOCKS5RequestPhasePort];
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read IPv4 address."];
	}
}

- (void)readSOCKS5IPv6AddressFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		uint8_t address[length];
		[data getBytes:&address length:length];
		[_addressData appendBytes:address length:length];
		char ip[INET6_ADDRSTRLEN];
		_targetHost = [NSString stringWithCString:inet_ntop(AF_INET6, address, ip, sizeof(ip)) encoding:NSUTF8StringEncoding];
		[self readDataForSOCKS5Tag:INSOCKS5RequestPhasePort];
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read IPv6 address."];
	}
}

- (void)readSOCKS5DomainNameLengthFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		[data getBytes:&_domainNameLength length:length];
		[_addressData appendBytes:(void *)_domainNameLength length:length];
		[self readDataForSOCKS5Tag:INSOCKS5RequestPhaseDomainName];
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read domain name length."];
	}
}

- (void)readSOCKS5DomainNameFromData:(NSData *)data
{
	if ([data length] == _domainNameLength) {
		uint8_t domainName[_domainNameLength];
		[data getBytes:&domainName length:_domainNameLength];
		[_addressData appendBytes:domainName length:_domainNameLength];
		_targetHost = [[NSString alloc] initWithBytes:domainName length:_domainNameLength encoding:NSUTF8StringEncoding];
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read domain name"];
	}
}

- (void)readSOCKS5PortFromData:(NSData *)data expectedLength:(NSUInteger)length
{
	if ([data length] == length) {
		uint8_t port[length];
		[data getBytes:&port length:length];
		[_addressData appendBytes:port length:length];
		_targetPort = (port[0] << 8 | port[1]);
	} else {
		[self refuseConnectionWithErrorDescription:@"Could not read port."];
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

- (void)refuseConnectionWithErrorDescription:(NSString *)description
{
	[self sendSOCKSHandshakeConnectionRefusedResponse];
	[self notifySOCKS5HandshakeErrorWithDescription:description];
}

+ (NSData *)replyDataForResponseType:(INSOCKS5HandshakeReplyType)type
{
	const unsigned char bytes[3] = {INSOCKS5HandshakeVersion5, type, 0x00}; // 0x00 is a reserved parameter
	return [NSData dataWithBytes:bytes length:3];
}

- (void)sendSOCKS5HandshakeSucceededResponse
{
	[_socket writeData:[self.class replyDataForResponseType:INSOCKS5HandshakeReplySucceeded] withTimeout:INSOCKS5SocketTimeout tag:0];
}

- (void)sendSOCKSHandshakeConnectionRefusedResponse
{
	[_socket writeData:[self.class replyDataForResponseType:INSOCKS5HandshakeReplyConnectionRefused] withTimeout:INSOCKS5SocketTimeout tag:0];
}

+ (NSUInteger)dataLengthForSOCKS5Tag:(NSUInteger)tag
{
	switch (tag) {
		case INSOCKS5HandshakePhaseVersion:
		case INSOCKS5HandshakePhaseNumberOfAuthenticationMethods:
		case INSOCKS5RequestPhaseAddressType:
		case INSOCKS5RequestPhaseDomainNameLength:
			return 1;
		case INSOCKS5RequestPhaseHeaderFragment:
			return 3;
		case INSOCKS5RequestPhaseIPv4Address:
			return 4;
		case INSOCKS5RequestPhaseIPv6Address:
			return 16;
		case INSOCKS5RequestPhasePort:
			return 2;
		default:
			return 0;
			break;
	}
}

- (void)readDataForSOCKS5Tag:(NSInteger)tag
{
	NSUInteger dataLength = [self.class dataLengthForSOCKS5Tag:tag];
	if (dataLength) {
		[_socket readDataToLength:dataLength withTimeout:INSOCKS5SocketTimeout tag:tag];
	}
}
@end
