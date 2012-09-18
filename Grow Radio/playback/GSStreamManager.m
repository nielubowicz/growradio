
//
//  GSStreamManager.m
//  Grooveshark
//
//  Created by Mike Cugini on 12/9/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "GSStreamManager.h"
#import "GSStreamSource.h"
#import "SongCacher.h"

#import "Song.h"

#import "PlaybackReporter.h"
#import "LocalPlaybackReporter.h"
#import "StreamingPlaybackReporter.h"

#import "GSCryptorFactory.h"

#import "GSSongURL.h"
#import "GSStreamKey.h"
#import "AudioDataFilter.h"

#import "GSAudioStream.h"
#import "GSLocalAudioStream.h"

@implementation GSStreamManager

-(id)init
{
    if ((self = [super init]))
    {
        database = [[[DatabaseManager sharedManager] writableDatabase] retain];
    }
    
    return self;
}

-(void)dealloc
{
    [database close];
    [database release];
    
    [super dealloc];
}

-(NSString *)cachePathForSong:(Song *)song
{
    NSString *cachePath = [[SongCacher sharedSongCacher] cachePath];
    NSString *songFile = [NSString stringWithFormat:@"%@.mp3", [song songID]];
    return  [cachePath stringByAppendingPathComponent:songFile];
}

-(NSURL *)cachedURLForSong:(Song *)song
{
    NSString *cachePath = [self cachePathForSong:song];
    BOOL cached = [[NSFileManager defaultManager] fileExistsAtPath:cachePath];
    
    return (cached) ? [NSURL fileURLWithPath:cachePath] : nil;
}

-(BOOL)canPlaySong:(Song *)song forOfflineStatus:(BOOL)offline
{
    return (offline) ? ([self cachedURLForSong:song] != nil) : YES;
}

-(GSStreamSource *)streamSourceForSong:(Song *)song error:(NSError **)error
{
    [self streamSourceForSong:song cached:NO error:error];
}

-(GSStreamSource *)streamSourceForSong:(Song *)song cached:(BOOL)cachedOnly error:(NSError **)error
{
    NSURL *url = nil;
    PlaybackReporter *reporter = nil;
    
    //Get the offline status of this song
    static NSString * const offlineInfo = @"SELECT offlineStatus, encryptScheme, fileID FROM offline_songs WHERE songId = ? LIMIT 1";
    FMResultSet *resultSet = [database executeQuery:offlineInfo, [song songID]];
    
    OfflineStatus status = OSNotOffline;
    NSUInteger encryptScheme = 0;
    NSNumber *fileID = nil;
    
    if ([resultSet next])
    {
        status = [resultSet intForColumn:@"offlineStatus"];
        encryptScheme = [resultSet intForColumn:@"encryptScheme"];
        fileID = [resultSet objectForColumnName:@"fileID"];
    }
    
    [resultSet close];
    
    if (status == OSOffline || status == OSAutoOffline)
    {
        //if the song is supposedly cached, get its URL
        url = [self cachedURLForSong:song];
        if (url)
        {
            //url exists, get the filter and reporter and return
            id<AudioDataFilter> dataFilter = [[GSCryptorFactory cryptorFactory] filterForScheme:encryptScheme];
            reporter = [[[LocalPlaybackReporter alloc] initWithSongID:[song songID]] autorelease];
            
            GSLocalAudioStream *localStream = [[[GSLocalAudioStream alloc] initWithFileAtPath:[url path]] autorelease];
            [localStream setDataFilter:dataFilter];
            
            [[GUTSLogger sharedGUTSLogger] addValue:kGUTSStreamTypeLocal forKey:kGUTSCurrentSongStreamType];
            return [[[GSStreamSource alloc] initWithURL:url
                                               reporter:reporter
                                                 stream:localStream
                                                 fileID:fileID
                                             dataFilter:dataFilter] autorelease];
        }
        else
        {
            //if the song was marked as cached but the file could not be found, remove it
            static NSString * const deleteOfflineSong = @"DELETE FROM offline_songs WHERE songId = ?";
            [database executeUpdate:deleteOfflineSong, [song songID]];
        }
    }
    
    if (cachedOnly)
    {
        //TODO: set the error object with a message about there not being a cached file
        [[GUTSLogger sharedGUTSLogger] removeValueFromContext:kGUTSCurrentSongStreamType];
        return nil;
    }
    
    NSUserDefaults *settings = [NSUserDefaults standardUserDefaults];
    BOOL lowBitrate = [song isLowBitrateAvailable] && ![settings boolForKey:kSettingsHighBitrate];
        
    GSSongURL *songURL = [[[GSSongURL alloc] init] autorelease];
    [songURL setSynchronous:YES];
    [songURL setSongID:[song songID]];
    [songURL setCountry:[[UIDevice currentDevice] country]];
    [songURL setLowBitrate:lowBitrate];
    [songURL setPrefetch:NO];
    [songURL execute];
    
    //if url fails, try again with no lowBitrate flag
    if ([songURL results] == nil)
    {
        songURL = [[[GSSongURL alloc] init] autorelease];
        [songURL setSynchronous:YES];
        [songURL setSongID:[song songID]];
        [songURL setCountry:[[UIDevice currentDevice] country]];
        [songURL setLowBitrate:NO];
        [songURL setPrefetch:NO];
        
        [songURL execute];
    }
    
    if ([songURL results] == nil)
    {
        if (error != NULL)
        {
            *error = [songURL error];
        }
        
        [[GUTSLogger sharedGUTSLogger] removeValueFromContext:kGUTSCurrentSongStreamType];
        return nil;
    }
    
    url = [songURL url];
    fileID = [songURL fileID];
    reporter = [[[StreamingPlaybackReporter alloc] initWithSongID:[song songID]
                                                        streamKey:[songURL streamKey]] autorelease];

    GSAudioStream *audioStream = [[[GSAudioStream alloc] initWithURL:url] autorelease];
    
    [[GUTSLogger sharedGUTSLogger] addValue:kGUTSStreamTypeStreaming forKey:kGUTSCurrentSongStreamType];
    return [[[GSStreamSource alloc] initWithURL:url
                                       reporter:reporter
                                         stream:audioStream
                                         fileID:fileID] autorelease];
}

-(GSStreamSource *)streamSourceForSong:(Song *)song URL:(NSURL *)songURL streamKey:(GSStreamKey *)streamkey fileID:(NSNumber *)fileID error:(NSError **)error
{
    //check to see if there is a cached source for this song and return that
    GSStreamSource *source = [self streamSourceForSong:song cached:YES error:NULL];
    if (source)
    {
        return source;
    }
    
    //No cached file, we need to use the songURL provided
	PlaybackReporter *reporter = [[[StreamingPlaybackReporter alloc] initWithSongID:[song songID]
                                                                          streamKey:streamkey] autorelease];
	GSAudioStream *audioStream = [[[GSAudioStream alloc] initWithURL:songURL] autorelease];
    
    [[GUTSLogger sharedGUTSLogger] addValue:kGUTSStreamTypeStreaming forKey:kGUTSCurrentSongStreamType];
	return [[[GSStreamSource alloc] initWithURL:songURL
									   reporter:reporter
                                         stream:audioStream
                                         fileID:fileID] autorelease];
}

@end
