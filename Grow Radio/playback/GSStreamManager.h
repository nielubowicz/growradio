//
//  GSStreamManager.h
//  Grooveshark
//
//  Created by Mike Cugini on 12/9/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Song;
@class GSStreamSource;
@class GSStreamKey;

@interface GSStreamManager : NSObject
{
    FMDatabase *database;
}

-(BOOL)canPlaySong:(Song *)song forOfflineStatus:(BOOL)offline;

-(GSStreamSource *)streamSourceForSong:(Song *)song error:(NSError **)error;
-(GSStreamSource *)streamSourceForSong:(Song *)song cached:(BOOL)cachedOnly error:(NSError **)error;
-(GSStreamSource *)streamSourceForSong:(Song *)song URL:(NSURL *)songURL streamKey:(GSStreamKey *)streamkey fileID:(NSNumber *)fileID error:(NSError **)error;
@end
