//
//  GSDataAudioStream.m
//  Grooveshark
//
//  Created by Michael Cugini on 11/16/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "GSDataAudioStream.h"

@implementation GSDataAudioStream
{
    NSInputStream *stream;
    UInt64 length;
}

- (id)initWithData:(NSData *)data
{
    if ((self = [super init]))
    {
        length = [data length];
        stream = [[NSInputStream alloc] initWithData:data];
        [stream setDelegate:(id)self];
    }
    
    return self;
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

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
    if ([self delegate] && [[self delegate] respondsToSelector:@selector(stream:handleEvent:)])
    {
        [[self delegate] stream:self handleEvent:streamEvent];
    }
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    return [stream read:buffer maxLength:len];
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
    return [stream getBuffer:buffer length:len];
}

- (BOOL)hasBytesAvailable
{
    return [stream hasBytesAvailable];
}
-(UInt64)length
{
    return length;
}

@end
