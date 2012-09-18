//
//  GSHTTPAudioStream.h
//  Grooveshark
//
//  Created by Michael Cugini on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "GSAudioStream.h"

@interface GSHTTPAudioStream : GSAudioStream

-(id)initWithURL:(NSURL *)url;
-(void)reconnect;

@end
