//
//  GSStreamSource.m
//  grooveshark2
//
//  Created by Mike Cugini on 8/31/10.
//  Copyright 2010 escapemg. All rights reserved.
//

#import "GSStreamSource.h"

@implementation GSStreamSource

@synthesize reporter;
@synthesize streamURL;
@synthesize audioStream;
@synthesize audioDataFilter;
@synthesize fileID;

-(id)initWithURL:(NSURL *)url reporter:(PlaybackReporter *)aReporter stream:(GSAudioStream *)stream fileID:(NSNumber *)aFileID dataFilter:(id<AudioDataFilter>)dataFilter
{
	if ((self = [super init]))
	{
		streamURL = [url retain];
		reporter = [aReporter retain];
        audioStream = [stream retain];
        audioDataFilter = [dataFilter retain];
        fileID = [aFileID copy];
	}
    
    return self;
}

-(id)initWithURL:(NSURL *)url reporter:(PlaybackReporter *)aReporter stream:(GSAudioStream *)stream fileID:(NSNumber *)aFileID
{
	return [self initWithURL:url reporter:aReporter stream:stream fileID:aFileID dataFilter:nil];
}

-(void)dealloc
{
	[reporter release];
	[streamURL release];
    [audioStream release];
    [audioDataFilter release];
    [fileID release];
	
	[super dealloc];
}

@end
