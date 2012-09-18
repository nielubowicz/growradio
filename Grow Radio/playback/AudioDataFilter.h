//
//  AudioDataFilter.h
//  Grooveshark
//
//  Created by Mike Cugini on 12/23/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol AudioDataFilter <NSObject>

-(void)filterData:(uint8_t *)data length:(NSInteger)length;
-(void)reset;

@end
