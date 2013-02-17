## INSOCKSServer
### SOCKS5 Proxy Server Implementation in Objective-C

Implements a proxy server using version 5 of the SOCKS protocol as defined in [RFC 1928](http://www.ietf.org/rfc/rfc1928.txt). **Work in progress**.

### TODO

* [GSSAPI](http://tools.ietf.org/html/draft-ietf-aft-gssapi-02) Authentication
* [Username/Password](http://www.ietf.org/rfc/rfc1929.txt) Authentication
* Port binding command 
* UDP association command

### Contributions

Contributions implementing anything in **TODO** or any bug fixes/improvements are much appreciated.

### What works so far

* SOCKS5 proxy server using **anonymous authentication** and a **TCP/IP connection**
* Sample application that runs a simple SOCKS proxy

### Dependencies

* GCDAsyncSocket (submodule)

### License

Licensed under [MIT](http://opensource.org/licenses/MIT).