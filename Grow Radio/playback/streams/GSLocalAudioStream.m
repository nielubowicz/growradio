//
//  GSLocalAudioStream.m
//  Grooveshark
//
//  Created by Michael Cugini on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "GSLocalAudioStream.h"

@implementation GSLocalAudioStream
{
    NSInputStream *stream;
    NSString *filePath;
}

@synthesize dataFilter;

- (id)initWithFileAtPath:(NSString *)path
{
    if ((self = [self init]))
    {
        filePath = [path copy];
        stream = [[NSInputStream alloc] initWithFileAtPath:filePath];
        [stream setDelegate:(id)self];
    }
    
    return self;
}

-(void)dealloc
{
    [filePath release];
    [stream release];
    [dataFilter release];
    
    [super dealloc];
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
    NSInteger bytes = [stream read:buffer maxLength:len];
    
    if (dataFilter)
    {
        [dataFilter filterData:buffer
                        length:bytes];
    }
    
    return bytes;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
    NSUInteger internalLen = 0;
    
    BOOL succ = [stream getBuffer:buffer length:&internalLen];
    
    if (succ)
    {
        if (len != NULL)
        {
            *len = internalLen;
        }
        
        if (dataFilter)
        {
            [dataFilter filterData:*buffer
                            length:internalLen];
        }
    }
    
    return succ;
}

- (BOOL)hasBytesAvailable
{
    return [stream hasBytesAvailable];
}

-(UInt64)length
{
    FILE *file = fopen([filePath UTF8String], "rb");
    
    fseek(file, 0, SEEK_END);
    UInt64 length = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    fclose(file);
    
    return length;
}

@end
