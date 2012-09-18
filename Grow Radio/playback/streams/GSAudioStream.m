//
//  GSAudioStream.m
//  Grooveshark
//
//  Created by Michael Cugini on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "GSAudioStream.h"

#import "GSHTTPAudioStream.h"
#import "GSLocalAudioStream.h"

@implementation GSAudioStream
{
    id<NSStreamDelegate> delegate;
}

- (id)initWithData:(NSData *)data
{
    NSZone *zone = [self zone];
    [self release];
    self = [[GSLocalAudioStream allocWithZone:zone] initWithData:data];
    
    return self;
}

- (id)initWithFileAtPath:(NSString *)path
{
    NSZone *zone = [self zone];
    [self release];
    self = [[GSLocalAudioStream allocWithZone:zone] initWithFileAtPath:path];
    
    return self;
}

- (id)initWithURL:(NSURL *)url
{
    if ([url isFileURL])
    {
        return [self initWithFileAtPath:[url path]];
    }
    
    NSZone *zone = [self zone];
    [self release];
    self = [[GSHTTPAudioStream allocWithZone:zone] initWithURL:url];
    
    return self;
}

- (id<NSStreamDelegate>)delegate
{
    return delegate;
}

-(void)setDelegate:(id<NSStreamDelegate>)aDelegate
{
    delegate = aDelegate;
}

-(void)reconnect
{
    //implement in subclasses if possible
}

-(UInt64)length
{
    return 0;
}

@end
