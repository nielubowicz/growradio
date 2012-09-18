//
//  GSAudioStream.h
//  Grooveshark
//
//  Created by Michael Cugini on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSAudioStream : NSInputStream

-(UInt64)length; //length must be valid after HasBytesAvailable is true for the first time
-(void)reconnect;

@end
