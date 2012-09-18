//
//  GSStreamSource.h
//  grooveshark2
//
//  Created by Mike Cugini on 8/31/10.
//  Copyright 2010 escapemg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSAudioStream.h"
#import "AudioDataFilter.h"

@class PlaybackReporter;

@interface GSStreamSource : NSObject
{
	NSURL *streamURL;
	PlaybackReporter *reporter;
    
    NSNumber *fileID;
    
    GSAudioStream *audioStream;
    id<AudioDataFilter> audioDataFilter;
}

@property(readonly) NSURL *streamURL;
@property(readonly) PlaybackReporter *reporter;
@property(readonly) GSAudioStream *audioStream;
@property(readonly) id<AudioDataFilter> audioDataFilter;
@property(readonly) NSNumber *fileID;

-(id)initWithURL:(NSURL *)url reporter:(PlaybackReporter *)aReporter stream:(GSAudioStream *)stream fileID:(NSNumber *)aFileID;
-(id)initWithURL:(NSURL *)url reporter:(PlaybackReporter *)aReporter stream:(GSAudioStream *)stream fileID:(NSNumber *)aFileID dataFilter:(id<AudioDataFilter>)dataFilter;

@end