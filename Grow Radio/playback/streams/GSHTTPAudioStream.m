//
//  GSHTTPAudioStream.m
//  Grooveshark
//
//  Created by Michael Cugini on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "GSHTTPAudioStream.h"

@interface GSHTTPAudioStream ()

-(void)configureInternalStream:(BOOL)reconnect;

@end

@implementation GSHTTPAudioStream
{
    NSInputStream *stream;
    NSURL *_url;
    
    NSTimeInterval timeout;
    BOOL timedOut;
    NSTimer *timeoutTimer;
        
    UInt64 fileLength;
    UInt64 bytesDownloaded;
}

-(id)initWithURL:(NSURL *)url
{
    if ((self = [super init]))
    {
        _url = [url copy];
        [self configureInternalStream:NO];
        timeout = 15;
    }
    
    return self;
}

-(void)dealloc
{
    [stream release];
    [_url release];
    [timeoutTimer release];
    
    [super dealloc];
}

-(void)configureInternalStream:(BOOL)reconnect
{
    CFReadStreamRef readStream = NULL;
    
    CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, 
                                                          CFSTR("GET"), 
                                                          (CFURLRef) _url, 
                                                          kCFHTTPVersion1_1);
    
    if (reconnect && (fileLength > 0) && (bytesDownloaded > 0))
    {				
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"),
                                         (CFStringRef) [NSString stringWithFormat:@"bytes=%llu-%llu", bytesDownloaded, fileLength]);
    }
    else
    {
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"), CFSTR("bytes=0-"));
    }
    
    readStream = CFReadStreamCreateForHTTPRequest(NULL, message);
    CFRelease(message);
    
    //setup stream redirection
    CFReadStreamSetProperty(readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
    
    //set SSL properties
    if ([[_url absoluteString] rangeOfString:@"https"].location != NSNotFound)
    {
        NSDictionary *sslSettings =
        [NSDictionary dictionaryWithObjectsAndKeys:
         (NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL, kCFStreamSSLLevel,
         [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
         [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
         [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
         [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
         [NSNull null], kCFStreamSSLPeerName,
         nil];
        
        CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, sslSettings);
    }
    
    [stream release];
    stream = (NSInputStream *) readStream;
    
    [stream setDelegate:(id)self];
}

-(void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [stream scheduleInRunLoop:aRunLoop
                      forMode:mode];
}

-(void)open
{
    [stream open];
}

-(void)close
{
    [stream close];
}

-(NSError *)streamError
{
    return [stream streamError];
}

-(NSStreamStatus)streamStatus
{
    return [stream streamStatus];
}

-(UInt64)length
{
    if (fileLength == 0)
    {
        CFTypeRef message = CFReadStreamCopyProperty((CFReadStreamRef) stream, kCFStreamPropertyHTTPResponseHeader);
        NSDictionary *httpHeaders = [(NSDictionary *) CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef) message) autorelease];
        CFRelease(message);
        
        fileLength = [[httpHeaders objectForKey:@"Content-Length"] integerValue];
    }
    
    return fileLength;
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{ 
    //if timeout flag is set, but we recieved a non-error event
    //then our stream is back on track and we can reset the flag
    if (timedOut && streamEvent != NSStreamEventErrorOccurred)
    {
        timedOut = NO;
    }
    
    //if an error occurred, and we have not run out of retry time...
    if (streamEvent == NSStreamEventErrorOccurred && !timedOut)
    {
        NSError *error = [stream streamError];
        
        NSLog(@"Error: %@", error);
        
        if (error)
        {
            //socket disconnect, retry connection
            if ([[error domain] isEqualToString:NSPOSIXErrorDomain] &&
                [error code] == ENOTCONN)
            {
                [self reconnect];
                return;
            }
            else if ([[error domain] isEqualToString:(NSString *)kCFErrorDomainCFNetwork])
            {
                timeoutTimer = [NSTimer timerWithTimeInterval:timeout
                                                       target:self 
                                                     selector:@selector(lastRetry)
                                                     userInfo:nil
                                                      repeats:NO];
                
                return;
            }
        }
    }
    
    if (streamEvent == NSStreamEventOpenCompleted)
    {
        return;
    }
    
    if ([self delegate] && [[self delegate] respondsToSelector:@selector(stream:handleEvent:)])
    {
        [[self delegate] stream:self handleEvent:streamEvent];
    }
}

-(void)lastRetry
{
    timedOut = YES;
    [self reconnect];
}

-(void)reconnect
{
    [self configureInternalStream:YES];
    [self scheduleInRunLoop:[NSRunLoop currentRunLoop]
                    forMode:[[NSRunLoop currentRunLoop] currentMode]];
    [self open];
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSInteger bytes = [stream read:buffer maxLength:len];
    bytesDownloaded += bytes;
    
    return bytes;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
    NSUInteger internalLen = 0;
    BOOL succ = [stream getBuffer:buffer length:&internalLen];
    
    if (succ)
    {
        bytesDownloaded += internalLen;
        if (len != NULL)
        {
            *len = internalLen;
        }
    }
    
    return succ;
}

- (BOOL)hasBytesAvailable
{
    return [stream hasBytesAvailable];
}

@end
