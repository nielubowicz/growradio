//
//  GSLocalAudioStream.h
//  Grooveshark
//
//  Created by Michael Cugini on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "GSAudioStream.h"
#import "AudioDataFilter.h"

@interface GSLocalAudioStream : GSAudioStream

@property(retain) id<AudioDataFilter> dataFilter;

- (id)initWithFileAtPath:(NSString *)path;

@end
