//
//  INSOCKSServer.h
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

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"

@class INSOCKSConnection;
@protocol INSOCKSServerDelegate;
/**
 Objective-C implementation of a SOCKS5 proxy server as defined in RFC1928 <http://www.ietf.org/rfc/rfc1928.txt>
 */
@interface INSOCKSServer : NSObject <GCDAsyncSocketDelegate>
@property (nonatomic, assign) id<INSOCKSServerDelegate> delegate;
/**
 The listening port.
 */
@property (nonatomic, readonly) uint16_t port;
/**
 Array of INSOCKSConnection objects representing active connections to the proxy.
 */
@property (nonatomic, strong, readonly) NSArray *connections;
/**
 Starts a SOCKS server on the specified port
 @param port The port to listen for incoming connections on
 @param error Error pointer to set an error in case of a connection failure
 @return An instance of INSOCKSServer if the socket was successfully created or nil if there was an error
 */
- (instancetype)initWithPort:(uint16_t)port error:(NSError **)error;
@end

@protocol INSOCKSServerDelegate <NSObject>
@optional
- (void)SOCKSServer:(INSOCKSServer *)server didAcceptConnection:(INSOCKSConnection *)connection;
- (void)SOCKSServer:(INSOCKSServer *)server didDisconnectWithError:(NSError *)error;
@end

/**
 Notification posted when the connection disconnects. userInfo contains error information where availalble.
 */
extern NSString* const INSOCKSConnectionDisconnectedNotification;

/**
 Represents a single connection to the SOCKS5 server
 */
@protocol INSOCKSConnectionDelegate;
@interface INSOCKSConnection : NSObject <GCDAsyncSocketDelegate>
@property (nonatomic, assign) id<INSOCKSConnectionDelegate> delegate;
/**
 The number of bytes sent from client to target over the connection's lifetime. KVO observable
 */
@property (nonatomic, assign, readonly) unsigned long long bytesSent;
/**
 The number of bytes received from target to client over the connection's lifetime. KVO observable
 */
@property (nonatomic, assign, readonly) unsigned long long bytesReceived;
@end

@protocol INSOCKSConnectionDelegate <NSObject>
@optional
- (void)SOCKSConnection:(INSOCKSConnection *)connection didDisconnectWithError:(NSError *)error;
- (void)SOCKSConnection:(INSOCKSConnection *)connection TCPConnectionDidFailWithError:(NSError *)error;
- (void)SOCKSConnection:(INSOCKSConnection *)connection didEncounterErrorDuringSOCKS5Handshake:(NSError *)error;
@end