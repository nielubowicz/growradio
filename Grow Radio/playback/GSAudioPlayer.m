//
//  AudioStreamer.m
//  StreamingAudioPlayer
//
//  Created by Matt Gallagher on 27/09/08.
//  Copyright 2008 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

#import "GSAudioPlayer.h"

#ifdef TARGET_OS_IPHONE			
#import <CFNetwork/CFNetwork.h>
#endif

#include <sys/mman.h>
#include <sys/stat.h> 
#include <fcntl.h>
#include <unistd.h>

#include <libkern/OSAtomic.h>

#import "GSAudioErrors.h"

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50

typedef enum
{
    AP_NO_ERROR = 0,
    AP_AUDIO_DATA_NOT_FOUND,
    AP_AUDIO_QUEUE_CREATION_FAILED,
    AP_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED,
    AP_AUDIO_QUEUE_ENQUEUE_FAILED,
    AP_AUDIO_QUEUE_ADD_LISTENER_FAILED,
    AP_AUDIO_QUEUE_REMOVE_LISTENER_FAILED,
    AP_AUDIO_QUEUE_START_FAILED,
    AP_AUDIO_QUEUE_PAUSE_FAILED,
    AP_AUDIO_QUEUE_BUFFER_MISMATCH,
    AP_AUDIO_QUEUE_DISPOSE_FAILED,
    AP_AUDIO_QUEUE_STOP_FAILED,
    AP_AUDIO_QUEUE_FLUSH_FAILED,
    AP_AUDIO_BUFFER_TOO_SMALL,
    AP_GET_AUDIO_TIME_FAILED,
    AP_AUDIO_STREAMER_FAILED,
    AP_FILE_STREAM_SEEK_FAILED,
    AP_FILE_STREAM_PARSE_BYTES_FAILED,
    AP_FILE_STREAM_OPEN_FAILED,
    AP_FILE_STREAM_CLOSE_FAILED,
    AP_FILE_STREAM_GET_PROPERTY_FAILED,
    AP_NETWORK_CONNECTION_FAILED,
    AP_FILE_ENDED_EARLY,
    AP_BUFFER_ALLOCATION_FAILED,
    AP_STREAM_OPEN_FAILED
} InternalAudioPlayerError;

NSString * const AP_NO_ERROR_STRING = @"No error.";
NSString * const AP_FILE_STREAM_GET_PROPERTY_FAILED_STRING = @"File stream get property failed.";
NSString * const AP_FILE_STREAM_SEEK_FAILED_STRING = @"File stream seek failed.";
NSString * const AP_FILE_STREAM_PARSE_BYTES_FAILED_STRING = @"Parse bytes failed.";
NSString * const AP_FILE_STREAM_OPEN_FAILED_STRING = @"Open audio file stream failed.";
NSString * const AP_FILE_STREAM_CLOSE_FAILED_STRING = @"Close audio file stream failed.";
NSString * const AP_AUDIO_QUEUE_CREATION_FAILED_STRING = @"Audio queue creation failed.";
NSString * const AP_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED_STRING = @"Audio buffer allocation failed.";
NSString * const AP_AUDIO_QUEUE_ENQUEUE_FAILED_STRING = @"Queueing of audio buffer failed.";
NSString * const AP_AUDIO_QUEUE_ADD_LISTENER_FAILED_STRING = @"Audio queue add listener failed.";
NSString * const AP_AUDIO_QUEUE_REMOVE_LISTENER_FAILED_STRING = @"Audio queue remove listener failed.";
NSString * const AP_AUDIO_QUEUE_START_FAILED_STRING = @"Audio queue start failed.";
NSString * const AP_AUDIO_QUEUE_BUFFER_MISMATCH_STRING = @"Audio queue buffers don't match.";
NSString * const AP_AUDIO_QUEUE_DISPOSE_FAILED_STRING = @"Audio queue dispose failed.";
NSString * const AP_AUDIO_QUEUE_PAUSE_FAILED_STRING = @"Audio queue pause failed.";
NSString * const AP_AUDIO_QUEUE_STOP_FAILED_STRING = @"Audio queue stop failed.";
NSString * const AP_AUDIO_DATA_NOT_FOUND_STRING = @"No audio data found.";
NSString * const AP_AUDIO_QUEUE_FLUSH_FAILED_STRING = @"Audio queue flush failed.";
NSString * const AP_GET_AUDIO_TIME_FAILED_STRING = @"Audio queue get current time failed.";
NSString * const AP_AUDIO_STREAMER_FAILED_STRING = @"Audio playback failed";
NSString * const AP_NETWORK_CONNECTION_FAILED_STRING = @"Network connection failed";
NSString * const AP_AUDIO_BUFFER_TOO_SMALL_STRING = @"Audio packets are larger than kAQDefaultBufSize.";
NSString * const AP_FILE_ENDED_EARLY_STRING = @"Did not receive Content-Length number of bytes.";
NSString * const AP_STREAM_OPEN_FAILED_STRING = @"Stream failed to open.";

@interface GSAudioPlayer ()

//not threadsafe, this is handled by stateChangeLock
@property (nonatomic, readwrite) InternalAudioPlayerState state;

- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags;

- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer;

- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID;

- (void)enqueueBuffer;
- (void)close;

@end

#pragma mark Audio Callback Function Prototypes

void audioQueueCompletedBuffer(void* inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
void audioQueuePropertyChanged(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID);

void audioFileStreamPropertyChanged(void *							inClientData,
                                    AudioFileStreamID				inAudioFileStream,
                                    AudioFileStreamPropertyID            inPropertyID,
                                    UInt32 *						ioFlags);

void audioFileStreamHasPackets(void *							inClientData,
                               UInt32							inNumberBytes,
                               UInt32							inNumberPackets,
                               const void *                             inInputData,
                               AudioStreamPacketDescription *           inPacketDescriptions);


#pragma mark Audio Callback Function Implementations

/**
 This function is passed as a callback to the AudioFileStream and will be called when a property changes.

 This acts as a proxy and simply passes the parameters on to a method on the GSAudioPlayer object.
*/
void audioFileStreamPropertyChanged(void *							inClientData,
                                    AudioFileStreamID				inAudioFileStream,
                                    AudioFileStreamPropertyID            inPropertyID,
                                    UInt32 *						ioFlags)
{	
    GSAudioPlayer *player = (GSAudioPlayer *)inClientData;
    
    [player handlePropertyChangeForFileStream:inAudioFileStream
                         fileStreamPropertyID:inPropertyID
                                      ioFlags:ioFlags];
}

/**
 This function is passed as a callback to the AudioFileStream and will be called when the stream has usable audio data.
 
 This acts as a proxy and simply passes the parameters on to a method on the GSAudioPlayer object.
 */
void audioFileStreamHasPackets(void *							inClientData,
                               UInt32							inNumberBytes,
                               UInt32							inNumberPackets,
                               const void *                             inInputData,
                               AudioStreamPacketDescription *           inPacketDescriptions)
{
    GSAudioPlayer *player = (GSAudioPlayer *)inClientData;
    
    [player handleAudioPackets:inInputData
                   numberBytes:inNumberBytes
                 numberPackets:inNumberPackets
            packetDescriptions:inPacketDescriptions];
}


/**
 This function is passed as a callback to the AudioQueue and will be called when the queue is finished playing the returned buffer.
 
 This acts as a proxy and simply passes the parameters to a method on the GSAudioPlayer object.
 */
void audioQueueCompletedBuffer(void*					inClientData, 
                               AudioQueueRef                inAQ, 
                               AudioQueueBufferRef		inBuffer)
{
    GSAudioPlayer *player = (GSAudioPlayer *)inClientData;
    [player handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

/**
 This function is passed as a callback to the AudioQueue and will be called when the queue's "isRunning" property changes.
 
 This acts as a proxy and simply passes the parameters to a method on the GSAudioPlayer object.
 */
void audioQueuePropertyChanged(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    GSAudioPlayer *player = (GSAudioPlayer *)inUserData;
    [player handlePropertyChangeForQueue:inAQ propertyID:inID];
}

@implementation GSAudioPlayer

@synthesize delegate;
@synthesize stream;

@synthesize state;
@synthesize bitRate;
@synthesize fileLength;


- (id)initWithStream:(GSAudioStream *)aStream
{
    if ((self = [super init]))
    {
        stream = [aStream retain];
        
        lastProgress = 0.0;
        
        stateChangeLock = [[NSObject alloc] init];
        streamMutationLock = [[NSObject alloc] init];
        readAudioDataLock = [[NSLock alloc] init];
        queueBufferReadyCondition = [[NSCondition alloc] init];
        
        if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)] &&
            [[UIDevice currentDevice] isMultitaskingSupported])
        {
            downloadBackgroundTask = UIBackgroundTaskInvalid;
        }
    }
    
    return self;
}

- (void)dealloc
{
    [self stop];
    
    [stopError release];
    
    [stateChangeLock release];
    [streamMutationLock release];
    [readAudioDataLock release];
    [queueBufferReadyCondition release];
    
    [readDataThread cancel];
    [readDataThread release];
    
    [super dealloc];
}

-(BOOL)isStarted
{
    @synchronized(stateChangeLock)
    {
        return state == AP_INITIALIZED;
    }
}

-(BOOL)isPlaying
{
    @synchronized(stateChangeLock)
    {
        return state == AP_PLAYING;
    }
}

-(BOOL)isPaused
{
    @synchronized(stateChangeLock)
    {
        return state == AP_PAUSED;
    }
}

-(BOOL)isBuffering
{
    @synchronized(stateChangeLock)
    {
        return state == AP_BUFFERING;
    }
}

-(BOOL)didFail
{
    @synchronized(stateChangeLock)
    {
        return state == AP_STOPPED && stopReason == AP_STOPPING_ERROR;
    }
}

//
// isFinishing
//
// returns YES if the audio has reached a stopping condition.
//
- (BOOL)isFinishing
{
    @synchronized(stateChangeLock)
    {
        return (state == AP_STOPPING || state == AP_STOPPED) && stopReason != AP_STOPPING_TEMPORARILY;
    }
}

-(BOOL)didFinish
{    
    @synchronized(stateChangeLock)
    {
        return state == AP_STOPPED && stopReason != AP_STOPPING_ERROR;
    }
}

//
// stringForErrorCode:
//
// Converts an error code to a string that can be localized or presented
// to the user.
//
// Parameters:
//    anErrorCode - the error code to convert
//
// returns the string representation of the error code
//
+ (NSString *)stringForErrorCode:(InternalAudioPlayerError)anErrorCode
{
    switch (anErrorCode)
    {
        case AP_NO_ERROR:
            return AP_NO_ERROR_STRING;
        case AP_FILE_STREAM_GET_PROPERTY_FAILED:
            return AP_FILE_STREAM_GET_PROPERTY_FAILED_STRING;
        case AP_FILE_STREAM_SEEK_FAILED:
            return AP_FILE_STREAM_SEEK_FAILED_STRING;
        case AP_FILE_STREAM_PARSE_BYTES_FAILED:
            return AP_FILE_STREAM_PARSE_BYTES_FAILED_STRING;
        case AP_AUDIO_QUEUE_CREATION_FAILED:
            return AP_AUDIO_QUEUE_CREATION_FAILED_STRING;
        case AP_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED:
            return AP_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED_STRING;
        case AP_AUDIO_QUEUE_ENQUEUE_FAILED:
            return AP_AUDIO_QUEUE_ENQUEUE_FAILED_STRING;
        case AP_AUDIO_QUEUE_ADD_LISTENER_FAILED:
            return AP_AUDIO_QUEUE_ADD_LISTENER_FAILED_STRING;
        case AP_AUDIO_QUEUE_REMOVE_LISTENER_FAILED:
            return AP_AUDIO_QUEUE_REMOVE_LISTENER_FAILED_STRING;
        case AP_AUDIO_QUEUE_START_FAILED:
            return AP_AUDIO_QUEUE_START_FAILED_STRING;
        case AP_AUDIO_QUEUE_BUFFER_MISMATCH:
            return AP_AUDIO_QUEUE_BUFFER_MISMATCH_STRING;
        case AP_FILE_STREAM_OPEN_FAILED:
            return AP_FILE_STREAM_OPEN_FAILED_STRING;
        case AP_FILE_STREAM_CLOSE_FAILED:
            return AP_FILE_STREAM_CLOSE_FAILED_STRING;
        case AP_AUDIO_QUEUE_DISPOSE_FAILED:
            return AP_AUDIO_QUEUE_DISPOSE_FAILED_STRING;
        case AP_AUDIO_QUEUE_PAUSE_FAILED:
            return AP_AUDIO_QUEUE_DISPOSE_FAILED_STRING;
        case AP_AUDIO_QUEUE_FLUSH_FAILED:
            return AP_AUDIO_QUEUE_FLUSH_FAILED_STRING;
        case AP_AUDIO_DATA_NOT_FOUND:
            return AP_AUDIO_DATA_NOT_FOUND_STRING;
        case AP_GET_AUDIO_TIME_FAILED:
            return AP_GET_AUDIO_TIME_FAILED_STRING;
        case AP_NETWORK_CONNECTION_FAILED:
            return AP_NETWORK_CONNECTION_FAILED_STRING;
        case AP_AUDIO_QUEUE_STOP_FAILED:
            return AP_AUDIO_QUEUE_STOP_FAILED_STRING;
        case AP_AUDIO_STREAMER_FAILED:
            return AP_AUDIO_STREAMER_FAILED_STRING;
        case AP_AUDIO_BUFFER_TOO_SMALL:
            return AP_AUDIO_BUFFER_TOO_SMALL_STRING;
        case AP_FILE_ENDED_EARLY:
            return AP_FILE_ENDED_EARLY_STRING;
        case AP_STREAM_OPEN_FAILED:
            return AP_STREAM_OPEN_FAILED_STRING;
        default:
            return AP_AUDIO_STREAMER_FAILED_STRING;
    }
    
    return AP_AUDIO_STREAMER_FAILED_STRING;
}


+(GSAudioError)internalErrorToGSAudioError:(InternalAudioPlayerError)internalError
{
    switch (internalError)
    {
        case AP_NO_ERROR:
            return NoError;
            
        case AP_FILE_STREAM_OPEN_FAILED:
        case AP_FILE_STREAM_CLOSE_FAILED:
        case AP_FILE_STREAM_GET_PROPERTY_FAILED:
        case AP_AUDIO_STREAMER_FAILED:
        case AP_FILE_STREAM_SEEK_FAILED:
        case AP_FILE_STREAM_PARSE_BYTES_FAILED:
            return AudioStreamerError;
            
        case AP_AUDIO_QUEUE_CREATION_FAILED:
        case AP_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED:
        case AP_AUDIO_QUEUE_ENQUEUE_FAILED:
        case AP_AUDIO_QUEUE_ADD_LISTENER_FAILED:
        case AP_AUDIO_QUEUE_REMOVE_LISTENER_FAILED:
        case AP_AUDIO_QUEUE_START_FAILED:
        case AP_AUDIO_QUEUE_BUFFER_MISMATCH:
        case AP_AUDIO_QUEUE_DISPOSE_FAILED:
        case AP_AUDIO_QUEUE_PAUSE_FAILED:
        case AP_AUDIO_QUEUE_FLUSH_FAILED:
        case AP_GET_AUDIO_TIME_FAILED:
        case AP_AUDIO_QUEUE_STOP_FAILED:
        case AP_AUDIO_BUFFER_TOO_SMALL:
            return AudioQueueError;
            
        case AP_AUDIO_DATA_NOT_FOUND:
            return AudioDataNotFound;
            
        case AP_NETWORK_CONNECTION_FAILED:
            return NetworkError;
            
        default:
            return UnknownError;
    }
    
    return UnknownError;	
}

+(NSString *)stringForAudioError:(GSAudioError)error
{
    switch (error)
    {
        case NoError:
            return @"No error.";
        case AudioDataNotFound:
            return @"No audio data found in data source.";
        case AudioQueueError:
            return @"Error in AudioQueue, see underlying error.";
        case AudioStreamerError:
            return @"Error in AudioStreamer, see underlying error.";
        case NetworkError:
            return @"Error with network, see underlying error.";
        default:
            return @"Unknown Error.";
    }
}

-(void)failWithAudioError:(NSError *)error
{
    @synchronized(stateChangeLock)
    {
        stopError = [error retain];
        
        state = AP_STOPPING;
        stopReason = AP_STOPPING_ERROR;
        
        [self stop];
    }
}

- (void)failWithError:(NSError *)anError code:(GSAudioError)errCode
{
    if (errCode == NoError)
    {
        errCode = [GSAudioPlayer internalErrorToGSAudioError:[anError code]];
    }
    
    NSDictionary *userInfo = nil;
    if (anError == nil)
    {
        userInfo = [NSDictionary dictionaryWithObject:[GSAudioPlayer stringForAudioError:errCode]
                                               forKey:NSLocalizedDescriptionKey];
    }
    else
    {
        userInfo = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[GSAudioPlayer stringForAudioError:errCode], anError, nil]
                                               forKeys:[NSArray arrayWithObjects:NSLocalizedDescriptionKey, NSUnderlyingErrorKey, nil]];
    }
    
    NSError *error = [NSError errorWithDomain:GSAudioErrorDomain 
                                         code:errCode
                                     userInfo:userInfo];
    
    [self failWithAudioError:error];
}

- (void)failWithErrorCode:(InternalAudioPlayerError)anErrorCode
{
    NSString *underlyingDesc = [GSAudioPlayer stringForErrorCode:anErrorCode];
    
    if (err)
    {
        char *errChars = (char *)&err;
        underlyingDesc = 	[NSString stringWithFormat:@"%@ err: %c%c%c%c %d\n",
                               [GSAudioPlayer stringForErrorCode:anErrorCode],
                               errChars[3], errChars[2], errChars[1], errChars[0],
                               (int)err];
    }
    
    NSDictionary *underlyingInfo = [NSDictionary dictionaryWithObject:underlyingDesc
                                                               forKey:NSLocalizedDescriptionKey];
    
    NSError *underlyingError = [NSError errorWithDomain:GSAudioErrorDomain
                                                   code:(NSInteger) err
                                               userInfo:underlyingInfo];
    
    [self failWithError:underlyingError code:NoError];
}

- (void)setState:(InternalAudioPlayerState)aStatus
{
    @synchronized (stateChangeLock)
    {
        if (state != aStatus)
        {
            state = aStatus;
        }
    }
}

- (InternalAudioPlayerState)state
{
    @synchronized (stateChangeLock)
    {
        return state;
    }
}

//
// hintForFileExtension:
//
// Generates a first guess for the file type based on the file's extension
//
// Parameters:
//    fileExtension - the file extension
//
// returns a file type hint that can be passed to the AudioFileStream
//
+ (AudioFileTypeID)hintForFileExtension:(NSString *)fileExtension
{
    AudioFileTypeID fileTypeHint = kAudioFileMP3Type;
    if ([fileExtension isEqual:@"mp3"])
    {
        fileTypeHint = kAudioFileMP3Type;
    }
    else if ([fileExtension isEqual:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
    }
    else if ([fileExtension isEqual:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
    }
    else if ([fileExtension isEqual:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
    }
    else if ([fileExtension isEqual:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
    }
    else if ([fileExtension isEqual:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
    }
    else if ([fileExtension isEqual:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
    }
    else if ([fileExtension isEqual:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    return fileTypeHint;
}

//
// openReadStream
//
// Open the InputStream to read data from
//
- (BOOL)openReadStream
{
    @synchronized(stateChangeLock)
    {
        NSLog(@"%s", __PRETTY_FUNCTION__);
        if (stream == nil)
        {
            return NO;
        }
        
        if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)] &&
            [[UIDevice currentDevice] isMultitaskingSupported])
        {
            downloadBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:NULL];
        }
        
        // We're now ready to receive data
        state = AP_WAITING_FOR_DATA;
        
        [stream setDelegate:(id)self];
        [stream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                          forMode:NSDefaultRunLoopMode];
        
        [stream open];
    }
    
    return YES;
}

- (void)start
{
    @synchronized(stateChangeLock)
    {
        if (state == AP_PAUSED)
        {
            [self pause];
        }
        else if (state == AP_INITIALIZED)
        {
            NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]],
                     @"Playback can only be started from the main thread.");
            
            packetBufferSize = kAQDefaultBufSize;
            
            readDataThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(readAudioData)
                                                       object:nil];
            
            [readDataThread start];
            
            BOOL opened = [self openReadStream];
            if (!opened)
            {
                [self failWithErrorCode:AP_STREAM_OPEN_FAILED];
            }
        }
    }
}

//
// seekToTime:
//
// Attempts to seek to the new time. Will be ignored if the bitrate or fileLength
// are unknown.
//
// Parameters:
//    newTime - the time to seek to
//
-(void)seekTo:(double) newSeekTime
{
    if (fileLength <= 0)
    {
        return;
    }
    
    // Calculate the byte offset for seeking
    seekByteOffset = dataOffset +
    (newSeekTime / self.duration) * (fileLength - dataOffset);
    
    // Attempt to leave 1 useful packet at the end of the file (although in
    // reality, this may still seek too far if the file has a long trailer).
    if (seekByteOffset > fileLength - 2 * packetBufferSize)
    {
        seekByteOffset = fileLength - 2 * packetBufferSize;
    }
    
    // Store the old time from the audio queue and the time that we're seeking
    // to so that we'll know the correct time progress after seeking.
    seekTime = newSeekTime;
    
    if (seekByteOffset < writeOffset)
    {		
        SInt64 outBytes = 0;
        UInt32 flags = 0;
        
        AudioBytePacketTranslation byteTranslation;
        byteTranslation.mByte = seekByteOffset;
        
        UInt32 propSize = sizeof(byteTranslation);
        
        AudioFileStreamGetProperty(audioFileStream,
                                   kAudioFileStreamProperty_ByteToPacket,
                                   &propSize,
                                   &byteTranslation);
        
        OSStatus error = AudioFileStreamSeek(audioFileStream,
                                             byteTranslation.mPacket,
                                             &outBytes,
                                             &flags);
        
        //seek failed
        if (error == kAudioFileStreamError_InvalidPacketOffset)
        {
            return;
        }
        
        if (outBytes > writeOffset)
        {
            OSAtomicCompareAndSwap32Barrier(readOffset, writeOffset - (packetBufferSize * 2), &readOffset);		
        }
        else
        {
            OSAtomicCompareAndSwap32Barrier(readOffset, outBytes, &readOffset);
        }
        
        discontinuous = YES;
        
        @synchronized(stateChangeLock)
        {
            pausedSeek = (state == AP_PAUSED);
            state = AP_STOPPING;
            stopReason = AP_STOPPING_TEMPORARILY;
            
            err = AudioQueueStop(audioQueue, true);
            
            if (err)
            {
                [self failWithErrorCode:AP_AUDIO_QUEUE_STOP_FAILED];
                return;
            }
        }
    }
}

//
// progress
//
// returns the current playback progress. Will return zero if sampleRate has
// not yet been detected.
//
- (double)position
{
    @synchronized(stateChangeLock)
    {
        if (sampleRate > 0)
        {
            AudioTimeStamp queueTime;
            Boolean discontinuity;
            err = AudioQueueGetCurrentTime(audioQueue, NULL, &queueTime, &discontinuity);
            if (err)
            {
                //there is an error occurring here, but it can happen between route changes (e.g. headphones being removed/added)
                //during the transition, you can't get the current time, but once it's finished, everything is fine, so we can
                //safely ignore this error.
                NSLog(@"Ignoring Error Getting Current Time: %ld", err);
            }
            
            double progress = seekTime + queueTime.mSampleTime / sampleRate;
            if (progress < 0.0)
            {
                progress = 0.0;
            }
            
            lastProgress = progress;
            return progress;
        }
    }
    
    return lastProgress;
}

-(double)bufferedSeconds
{	
    if (fileLength <= 0.0)
        return 0.0;
    
    return ((double) bytesDownloaded / fileLength) * [self duration];
}

//
// calculatedBitRate
//
// returns the bit rate, if known. Uses packet duration times running bits per
//   packet if available, otherwise it returns the nominal bitrate. Will return
//   zero if no useful option available.
//
- (double)calculatedBitRate
{
    if (packetDuration && processedPacketsCount > BitRateEstimationMinPackets)
    {
        double averagePacketByteSize = processedPacketsSizeTotal / processedPacketsCount;
        return 8.0 * averagePacketByteSize / packetDuration;
    }
    
    if (bitRate)
    {
        return (double)bitRate;
    }
    
    return 0;
}

//
// duration
//
// Calculates the duration of available audio from the bitRate and fileLength.
//
// returns the calculated duration in seconds.
//
- (double)duration
{
    double calculatedBitRate = [self calculatedBitRate];
    
    if (calculatedBitRate == 0 || fileLength == 0)
    {
        return 0.0;
    }
    
    return (fileLength - dataOffset) / (calculatedBitRate * 0.125);
}

-(void)togglePlayback
{	
    if (state == AP_PLAYING)
    {
        [self pause];
    }
    else
    {
        [self play];
    }
}

-(void)play
{
    @synchronized(stateChangeLock)
    {
        if (state == AP_INITIALIZED)
        {
            [self start];
            return;
        }
        
        if (state == AP_PAUSED)
        {
            err = AudioQueueStart(audioQueue, NULL);			
            if (err)
            {
                [self failWithErrorCode:AP_AUDIO_QUEUE_START_FAILED];
                return;
            }
            
            state = AP_PLAYING;
        }
        
        if (delegate && [delegate respondsToSelector:@selector(audioPlayerPlayStatusChanged:)])
        {
            [delegate audioPlayerPlayStatusChanged:(state == AP_PAUSED)];
        }
    }
}

- (void)pause
{
    @synchronized(stateChangeLock)
    {
        if (state == AP_PLAYING)
        {
            err = AudioQueuePause(audioQueue);
            if (err)
            {
                [self failWithErrorCode:AP_AUDIO_QUEUE_PAUSE_FAILED];
                return;
            }
            
            state = AP_PAUSED;
        }
        
        if (delegate && [delegate respondsToSelector:@selector(audioPlayerPlayStatusChanged:)])
        {
            [delegate audioPlayerPlayStatusChanged:(state == AP_PAUSED)];
        }
    }
}

//
// stop
//
// This method can be called to stop downloading/playback before it completes.
// It is automatically called when an error occurs.
//
- (void)stop
{
    @synchronized(stateChangeLock)
    {
        if (audioQueue)
        {
            
            if (state != AP_STOPPING)
            {
                state = AP_STOPPING;
                stopReason = AP_STOPPING_USER_ACTION;
            }
            
            err = AudioQueueStop(audioQueue, true);
            if (err)
            {
                [self failWithErrorCode:AP_AUDIO_QUEUE_STOP_FAILED];
            }
        }
        else
        {
            state = AP_STOPPED;
            stopReason = AP_STOPPING_USER_ACTION;
        }
    }
}

- (BOOL)runLoopShouldExit
{
    @synchronized(stateChangeLock)
    {
        return state == AP_STOPPED && stopReason != AP_STOPPING_TEMPORARILY;
    }
}

-(BOOL)didReadAllData
{
    return reachedEOF && (writeOffset == readOffset);
}

-(void)readAudioData
{	
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (audioFileStream == NULL)
    {
        //TODO: eeeh?
 //       AudioFileTypeID fileTypeHint = [GSAudioPlayer hintForFileExtension:[[url path] pathExtension]];
        AudioFileTypeID fileTypeHint = [GSAudioPlayer hintForFileExtension:nil];
        
        // create an audio file stream parser
        err = AudioFileStreamOpen(self, 
                                  audioFileStreamPropertyChanged, 
                                  audioFileStreamHasPackets, 
                                  fileTypeHint, 
                                  &audioFileStream);
        if (err)
        {
            [self failWithErrorCode:AP_FILE_STREAM_OPEN_FAILED];
            [pool drain];
            return;
        }
    }
    
    while (![self didReadAllData] &&
           ![self runLoopShouldExit])
    {
        //check if we are buffering
        @synchronized(stateChangeLock)
        {
            if (buffersUsed == 0 && state == AP_PLAYING)
            {
                err = AudioQueuePause(audioQueue);
                if (err)
                {
                    [self failWithErrorCode:AP_AUDIO_QUEUE_PAUSE_FAILED];
                    return;
                }
                
                state = AP_BUFFERING;
                
                if (delegate && [delegate respondsToSelector:@selector(audioPlayerStartedBuffering:)])
                {
                    [delegate audioPlayerStartedBuffering:self];
                }
            }
        }
        
        //read the next chunk of data in the audioDataBuffer and pass it to the 
        //AudioFileStream for processing
        SInt64 length = 0;
        if ((length = writeOffset - readOffset) > 0)
        {
            length = (length > packetBufferSize * 3) ? packetBufferSize * 3: length;
            uint8_t *buffer = calloc(length, sizeof(uint8_t));
            
            [readAudioDataLock lock];
            memcpy(buffer, (audioDataBuffer + readOffset), length);
            [readAudioDataLock unlock];
            
            UInt32 flags = (discontinuous) ? kAudioFileStreamParseFlag_Discontinuity : 0;
            err = AudioFileStreamParseBytes(audioFileStream, length, buffer, flags);
            
            if (err)
            {
                [self failWithErrorCode:AP_FILE_STREAM_PARSE_BYTES_FAILED];
            }
            
            OSAtomicAdd32Barrier(length, &readOffset);
            
            free(buffer);
        }
    }
    
    [self close];
    
    [pool drain];
}

- (void)close
{
    @synchronized(streamMutationLock)
    {
        // Cleanup the read stream if it is still open
        if (stream != nil)
        {
            [stream setDelegate:nil];
            [stream close];
            [stream release];
            stream = nil;
        }
        
        //flush out any remaining bytes waiting to be enqueued
        if (reachedEOF && bytesFilled > 0)
        {
            [self enqueueBuffer];
        }
    }
    
    @synchronized(stateChangeLock)
    {        
        if (state == AP_WAITING_FOR_DATA)
        {
            [self failWithErrorCode:AP_AUDIO_DATA_NOT_FOUND];
        }
        else if (![self isFinishing])
        {
            if (audioQueue && (state == AP_PLAYING || state == AP_PAUSED))
            {
                if (delegate && [delegate respondsToSelector:@selector(audioPlayerWillFinishPlaying:)])
                {
                    [delegate audioPlayerWillFinishPlaying:self];
                }
                
                // Set the progress at the end of the stream
                err = AudioQueueFlush(audioQueue);
                if (err)
                {
                    [self failWithErrorCode:AP_AUDIO_QUEUE_FLUSH_FAILED];
                    return;
                }
                
                state = AP_STOPPING;
                stopReason = AP_STOPPING_EOF;
                
                err = AudioQueueStop(audioQueue, false);
                if (err)
                {
                    [self failWithErrorCode:AP_AUDIO_QUEUE_STOP_FAILED];
                }
            }
        }
    }

    //make sure all remaining buffers are flushed before we
    //start releasing things
    while (state != AP_STOPPED)
    {
        [NSThread sleepForTimeInterval:0.5];
    }
    
    @synchronized(streamMutationLock)
    {
        if (audioDataBuffer != NULL)
        {
            if (mappedBuffer)
            {
                munmap(audioDataBuffer, fileLength);
            }
            else
            {
                free(audioDataBuffer);
            }
            
            audioDataBuffer = NULL;
        }
    }
        
    if (bufferFilePath != nil)
    {
        [[NSFileManager defaultManager] removeItemAtPath:bufferFilePath
                                                   error:NULL];
        
        [bufferFilePath release];
        bufferFilePath = nil;
    }
    
    @synchronized(stateChangeLock)
    {
        // Dispose of the Audio Queue
        if (audioQueue)
        {
            err = AudioQueueDispose(audioQueue, true);
            audioQueue = NULL;
            if (err)
            {
                [self failWithErrorCode:AP_AUDIO_QUEUE_DISPOSE_FAILED];
            }
        }
    }
    
    if (audioFileStream != NULL)
    {
        err = AudioFileStreamClose(audioFileStream);
        audioFileStream = NULL;
        
        if (err)
        {
            [self failWithErrorCode:AP_FILE_STREAM_CLOSE_FAILED];
        }
    }
    
    if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)] &&
        [[UIDevice currentDevice] isMultitaskingSupported] &&
        downloadBackgroundTask != UIBackgroundTaskInvalid)
    {
        [[UIApplication sharedApplication] endBackgroundTask:downloadBackgroundTask];
        downloadBackgroundTask = UIBackgroundTaskInvalid;
    }
    
    if (stopReason == AP_STOPPING_ERROR)
    {
        if (delegate && [delegate respondsToSelector:@selector(audioPlayer:playbackDidFailWithError:)])
        {
            [delegate audioPlayer:self playbackDidFailWithError:stopError];
        }
    }
    else
    {
        if (delegate && [delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:reachedEnd:)])
        {
            [delegate audioPlayerDidFinishPlaying:self reachedEnd:(stopReason == AP_STOPPING_EOF)];
        }
    }
    
    @synchronized(streamMutationLock)
    {
        reachedEOF = NO;
        bytesFilled = 0;
        packetsFilled = 0;
        seekByteOffset = 0;
        packetBufferSize = 0;
        readOffset = 0;
        writeOffset = 0;
        state = AP_INITIALIZED;
    }
}

/** Called from handleAudioPackets:numberBytes:numberPackets:packetDescriptions: and cleanUp.
 It enqueues filled AudioQueueBuffers on the AudioQueue.
 
 This method does not return until a buffer is idle for further filling or the AudioQueue is stopped.
 */
- (void)enqueueBuffer
{
    @synchronized(stateChangeLock)
    {
        if ([self isFinishing] || stream == nil)
        {
            return;
        }
        
        inuse[fillBufferIndex] = true;		// set in use flag
        buffersUsed++;
        
        // enqueue buffer        
        AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
        fillBuf->mAudioDataByteSize = bytesFilled;
        
        if (packetsFilled)
        {
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, packetsFilled, packetDescs);
        }
        else
        {
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, 0, NULL);
        }
        
        if (err)
        {
            [self failWithErrorCode:AP_AUDIO_QUEUE_ENQUEUE_FAILED];
            return;
        }
        
        if (state == AP_BUFFERING ||
            state == AP_WAITING_FOR_DATA ||
            (state == AP_STOPPED && stopReason == AP_STOPPING_TEMPORARILY))
        {
  
            // Fill all the buffers before starting. This ensures that the
            // AudioFileStream stays a small amount ahead of the AudioQueue to
            // avoid an audio glitch playing streaming files on iPhone SDKs < 3.0
            if (reachedEOF || buffersUsed == kNumAQBufs / 2)
            {
                if (state == AP_BUFFERING)
                {
                    err = AudioQueueStart(audioQueue, NULL);
                    if (err)
                    {
                        [self failWithErrorCode:AP_AUDIO_QUEUE_START_FAILED];
                        return;
                    }
                    
                    state = AP_PLAYING;
                    if (delegate && [delegate respondsToSelector:@selector(audioPlayerFinishedBuffering:)])
                    {
                        [delegate audioPlayerFinishedBuffering:self];
                    }
                }
                else
                {					
                    state = AP_WAITING_FOR_QUEUE_TO_START;
                    
                    err = AudioQueueStart(audioQueue, NULL);
                    if (err)
                    {
                        [self failWithErrorCode:AP_AUDIO_QUEUE_START_FAILED];
                        return;
                    }
                }
            }
        }
        
        // go to next buffer
        if (++fillBufferIndex >= kNumAQBufs) fillBufferIndex = 0;
        bytesFilled = 0;		// reset bytes filled
        packetsFilled = 0;	// reset packets filled
    }
    
    // wait until next buffer is not in use
    [queueBufferReadyCondition lock];
    while (inuse[fillBufferIndex])
    {
        [queueBufferReadyCondition wait];
    }
    
    [queueBufferReadyCondition unlock];
}

//        
// createQueue
//
// Method to create the AudioQueue from the parameters gathered by the
// AudioFileStream.
//
// Creation is deferred to the handling of the first audio packet (although
// it could be handled any time after kAudioFileStreamProperty_ReadyToProducePackets
// is true).
//
- (void)createQueue
{
    sampleRate = asbd.mSampleRate;
    packetDuration = asbd.mFramesPerPacket / sampleRate;
    
    // create the audio queue
    err = AudioQueueNewOutput(&asbd, audioQueueCompletedBuffer, self, NULL, NULL, 0, &audioQueue);
    if (err)
    {
        [self failWithErrorCode:AP_AUDIO_QUEUE_CREATION_FAILED];
        return;
    }
    
    // start the queue if it has not been started already
    // listen to the "isRunning" property
    err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, audioQueuePropertyChanged, self);
    if (err)
    {
        [self failWithErrorCode:AP_AUDIO_QUEUE_ADD_LISTENER_FAILED];
        return;
    }
    
    // get the packet size if it is available
    UInt32 sizeOfUInt32 = sizeof(UInt32);
    err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &packetBufferSize);
    if (err || packetBufferSize == 0)
    {
        err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &packetBufferSize);
        if (err || packetBufferSize == 0)
        {
            // No packet size available, just use the default
            packetBufferSize = kAQDefaultBufSize;
        }
    }
    
    // allocate audio queue buffers
    for (uint i = 0; i < kNumAQBufs; ++i)
    {
        err = AudioQueueAllocateBuffer(audioQueue, packetBufferSize, &audioQueueBuffer[i]);
        if (err)
        {
            [self failWithErrorCode:AP_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED];
            return;
        }
    }
    
    // get the cookie size
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableError;
    ignorableError = AudioFileStreamGetPropertyInfo(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (ignorableError)
    {
        return;
    }
    
    // get the cookie data
    void* cookieData = calloc(1, cookieSize);
    ignorableError = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (ignorableError)
    {
        return;
    }
    
    // set the cookie on the queue.
    ignorableError = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if (ignorableError)
    {
        return;
    }
}

-(void)reportFileDownloaded
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (delegate && [delegate respondsToSelector:@selector(audioPlayer:audioFileCachedAtTempPath:)])
    {
        [delegate audioPlayer:self audioFileCachedAtTempPath:[[bufferFilePath copy] autorelease]];
    }
    
    [pool drain];
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
    @synchronized(streamMutationLock)
    {
        if (theStream != stream)
        {
            // Ignore old streams
            return;
        }
            
        switch (streamEvent)
        {
            case NSStreamEventErrorOccurred:
            {
                //TODO: make more generic code, or have stream return a code?
                [self failWithError:[stream streamError] code:NetworkError];
                break;
            }
                
            case NSStreamEventEndEncountered:
            {
                reachedEOF = YES;
                
                if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)] &&
                    [[UIDevice currentDevice] isMultitaskingSupported])
                {
                    [[UIApplication sharedApplication] endBackgroundTask:downloadBackgroundTask];
                    downloadBackgroundTask = UIBackgroundTaskInvalid;
                }
                
                [self performSelectorInBackground:@selector(reportFileDownloaded)
                                       withObject:nil];
                
                break;
            }
                
            case NSStreamEventHasBytesAvailable:
            {
                if (fileLength == 0)
                {
                    fileLength = [stream length];
                }
                
                uint8_t bytes[kAQDefaultBufSize];
                CFIndex length;
                    
                // Read the bytes from the stream
                length = [stream read:bytes maxLength:kAQDefaultBufSize];
                
                if (length == -1)
                {
                    [self failWithError:[stream streamError] code:NetworkError];
                    return;
                }
                
                if (length == 0)
                {
                    return;
                }
                
                bytesDownloaded += length;
                
                if (audioDataBuffer == NULL)
                {
                    bufferFilePath = [[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%f.dat", [NSDate timeIntervalSinceReferenceDate]]] retain];
                    
                    int fd = open([bufferFilePath UTF8String], O_RDWR | O_CREAT, S_IRWXU);
                    
                    //extend the file to the needed size
                    lseek(fd, fileLength, SEEK_SET);
                    write(fd, "", 1);
                    
                    mappedBuffer = YES;
                    audioDataBuffer = mmap(0, fileLength, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                    
                    //mem mapping failed
                    if (audioDataBuffer == MAP_FAILED)
                    {
                        mappedBuffer = NO;
                        audioDataBuffer = calloc(fileLength, sizeof(uint8_t));
                        
                        //memory allocation failed
                        if (audioDataBuffer == NULL)
                        {
                            [self failWithErrorCode:AP_BUFFER_ALLOCATION_FAILED];
                            return;
                        }
                    }
                }
                
                memcpy((audioDataBuffer + writeOffset), bytes, length);
                OSAtomicAdd32Barrier(length, &writeOffset);
            }
        }
    }
}

/**  Handles property changes on the AudioFileStream
 
 @param inAudioFileStream The AudioFileStream that had a property change.
 @param inPropertyID The property that changed.
 @param ioFlags Flags passed from the AudioFileStream.
 */
- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags
{
    @synchronized(stateChangeLock)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        switch (inPropertyID)
        {
            case kAudioFileStreamProperty_ReadyToProducePackets:
            {
                discontinuous = YES;
                break;
            }
                
            case kAudioFileStreamProperty_AverageBytesPerPacket:
            case kAudioFileStreamProperty_PacketSizeUpperBound:
            case kAudioFileStreamProperty_MaximumPacketSize:
            {
                UInt32 tempBufferSize = 0;
                UInt32 sizeOfUInt32 = sizeof(tempBufferSize);
                
                err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &tempBufferSize);
                
                if (tempBufferSize > packetBufferSize)
                {
                    packetBufferSize = tempBufferSize;
                }
                
                tempBufferSize = 0;
                
                err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &tempBufferSize);
                if (tempBufferSize > packetBufferSize)
                {
                    packetBufferSize = tempBufferSize;
                }
                
                Float64 avgBytes = 0;
                UInt32 sizeOfAvg = sizeof(avgBytes);
                
                err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfAvg, &avgBytes);
                if ((avgBytes * 2) > packetBufferSize)
                {
                    packetBufferSize = (UInt32) avgBytes * 2;
                }
                
                if (packetBufferSize == 0)
                {
                    // No packet size available, just use the default
                    packetBufferSize = kAQDefaultBufSize;
                }
                
                break;
            }
                
            case kAudioFileStreamProperty_DataOffset:
            {
                SInt64 offset;
                UInt32 offsetSize = sizeof(offset);
                err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
                if (err)
                {
                    [self failWithErrorCode:AP_FILE_STREAM_GET_PROPERTY_FAILED];
                    return;
                }
                dataOffset = offset;
                
                if (audioDataByteCount)
                {
                    fileLength = dataOffset + audioDataByteCount;
                }
                
                break;
            }
                
            case kAudioFileStreamProperty_AudioDataByteCount:
            {
                UInt32 byteCountSize = sizeof(UInt64);
                err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
                if (err)
                {
                    [self failWithErrorCode:AP_FILE_STREAM_GET_PROPERTY_FAILED];
                    return;
                }
                
                if (audioDataByteCount)
                {
                    fileLength = dataOffset + audioDataByteCount;
                }
                
                break;
            }
                
            case kAudioFileStreamProperty_DataFormat:
            {
                if (asbd.mSampleRate == 0)
                {
                    UInt32 asbdSize = sizeof(asbd);
                    
                    // get the stream format.
                    err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &asbd);
                    if (err)
                    {
                        [self failWithErrorCode:AP_FILE_STREAM_GET_PROPERTY_FAILED];
                        return;
                    }
                }
                
                break;
            }
                
            case kAudioFileStreamProperty_FormatList:
            {
                Boolean outWriteable;
                UInt32 formatListSize;
                err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
                if (err)
                {
                    [self failWithErrorCode:AP_FILE_STREAM_GET_PROPERTY_FAILED];
                    return;
                }
                
                AudioFormatListItem *formatList = malloc(formatListSize);
                err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
                if (err)
                {
                    [self failWithErrorCode:AP_FILE_STREAM_GET_PROPERTY_FAILED];
                    free(formatList);
                    formatList = NULL;
                    return;
                }
                
                for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem))
                {
                    AudioStreamBasicDescription pasbd = formatList[i].mASBD;
                    
                    if (pasbd.mFormatID == kAudioFormatMPEG4AAC_HE)
                    {
                        // We've found HE-AAC, remember this to tell the audio queue
                        // when we construct it.
#if !TARGET_IPHONE_SIMULATOR
                        asbd = pasbd;
#endif
                        break;
                    }                                
                }
                
                free(formatList);				
                formatList = NULL;
                break;
            }
                
            case kAudioFileStreamProperty_BitRate:
            {
                UInt32 tempBitRate = 0;
                UInt32 asbdSize = sizeof(tempBitRate);
                
                // get the stream format.
                AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &tempBitRate);
                
                if (tempBitRate != 0)
                {
                    bitRate = tempBitRate;
                }
                
                break;
            }
        }
    }
}

/**  Handles packaging up audio packets into queue buffers and enqeueing them.
 
 @param inInputData The audio packet data.
 @param inNumberBytes The size (in bytes) of the data.
 @param inNumberPackets Number of audio packets found within inInputData.
 @param inPacketDescriptions Descriptions of the packets found in inInputData (only present if the audio data is VBR).
 */
- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;
{
    @synchronized(stateChangeLock)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        if (bitRate == 0)
        {
            // m4a and a few other formats refuse to parse the bitrate so
            // we need to set an "unparseable" condition here. If you know
            // the bitrate (parsed it another way) you can set it on the
            // class if needed.
            bitRate = ~0;
        }
        
        // we have successfully read the first packets from the audio stream, so
        // clear the "discontinuous" flag
        if (discontinuous)
        {
            discontinuous = NO;
        }
        
        if (!audioQueue)
        {
            [self createQueue];
        }
    }
    
    // the following code assumes we're streaming VBR data. for CBR data, the second branch is used.
    if (inPacketDescriptions)
    {
        for (int i = 0; i < inNumberPackets; ++i)
        {
            SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
            SInt64 packetSize   = inPacketDescriptions[i].mDataByteSize;
            size_t bufSpaceRemaining;
            
            if (processedPacketsCount < BitRateEstimationMaxPackets)
            {
                processedPacketsSizeTotal += packetSize;
                processedPacketsCount += 1;
            }
            
            @synchronized(stateChangeLock)
            {
                // If the audio was terminated before this point, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                if (packetSize > packetBufferSize)
                {
                    [self failWithErrorCode:AP_AUDIO_BUFFER_TOO_SMALL];
                }
                
                bufSpaceRemaining = packetBufferSize - bytesFilled;
            }
            
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            if (bufSpaceRemaining < packetSize)
            {
                [self enqueueBuffer];
            }
            
            @synchronized(stateChangeLock)
            {
                // If the audio was terminated while waiting for a buffer, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                // If there was some kind of issue with enqueueBuffer and we didn't
                // make space for the new audio data then back out
                if (bytesFilled + packetSize >= packetBufferSize)
                {
                    return;
                }
                
                // copy data to the audio queue buffer
                AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
                memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inInputData + packetOffset, packetSize);
                
                // fill out packet description
                packetDescs[packetsFilled] = inPacketDescriptions[i];
                packetDescs[packetsFilled].mStartOffset = bytesFilled;
                
                // keep track of bytes filled and packets filled
                bytesFilled += packetSize;
                packetsFilled += 1;
            }
            
            // if that was the last free packet description, then enqueue the buffer.
            size_t packetsDescsRemaining = kAQMaxPacketDescs - packetsFilled;
            if (packetsDescsRemaining == 0)
            {
                [self enqueueBuffer];
            }
        }	
    }
    else
    {
        size_t offset = 0;
        while (inNumberBytes)
        {
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            size_t bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
            if (bufSpaceRemaining < inNumberBytes)
            {
                [self enqueueBuffer];
            }
            
            @synchronized(stateChangeLock)
            {
                // If the audio was terminated while waiting for a buffer, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
                size_t copySize;
                if (bufSpaceRemaining < inNumberBytes)
                {
                    copySize = bufSpaceRemaining;
                }
                else
                {
                    copySize = inNumberBytes;
                }
                
                // If there was some kind of issue with enqueueBuffer and we didn't
                // make space for the new audio data then back out
                if (bytesFilled >= packetBufferSize)
                {
                    return;
                }
                
                // copy data to the audio queue buffer
                AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
                memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inInputData + offset, copySize);
                
                
                // keep track of bytes filled and packets filled
                bytesFilled += copySize;
                packetsFilled = 0;
                inNumberBytes -= copySize;
                offset += copySize;
            }
        }
    }
}

/**  Handles recycling the completed AudioQueueBuffers
 
 @param inAudioQueue The audio queue returning a buffer.
 @param inBuffer The completed AudioQueueBuffer.
 */
- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAudioQueue
                              buffer:(AudioQueueBufferRef)inBuffer
{    
    unsigned int bufIndex = -1;
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        if (inBuffer == audioQueueBuffer[i])
        {
            bufIndex = i;
            break;
        }
    }
    
    if (bufIndex == -1)
    {
        [self failWithErrorCode:AP_AUDIO_QUEUE_BUFFER_MISMATCH];
        [queueBufferReadyCondition lock];
        [queueBufferReadyCondition signal];
        [queueBufferReadyCondition unlock];
        return;
    }
    
    // signal waiting thread that the buffer is free.
    [queueBufferReadyCondition lock];
    inuse[bufIndex] = false;
    buffersUsed--;
    
    
    //  Enable this logging to measure how many buffers are queued at any time.
#if LOG_QUEUED_BUFFERS
    NSLog(@"Queued buffers: %ld", buffersUsed);
#endif
    
    [queueBufferReadyCondition signal];
    [queueBufferReadyCondition unlock];
}

/**  Handles property changes on the Audio Queue
 
 @param inAudioQueue The Audio Queue with a changed property.
 @param inPropertyID The property that changed.
 */
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAudioQueue
                          propertyID:(AudioQueuePropertyID)inID
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    @synchronized(stateChangeLock)
    {
        if (inID == kAudioQueueProperty_IsRunning)
        {
            if (state == AP_STOPPING)
            {
                state = AP_STOPPED;
            }
            else if (state == AP_WAITING_FOR_QUEUE_TO_START)
            {
                //
                // Note about this bug avoidance quirk:
                //
                // On cleanup of the AudioQueue thread, on rare occasions, there would
                // be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
                // removed from the CFRunLoop.
                //
                // After lots of testing, it appeared that the audio thread was
                // attempting to remove CFRunLoop observers from the CFRunLoop after the
                // thread had already deallocated the run loop.
                //
                // By creating an NSRunLoop for the AudioQueue thread, it changes the
                // thread destruction order and seems to avoid this crash bug -- or
                // at least I haven't had it since (nasty hard to reproduce error!)
                //
                [NSRunLoop currentRunLoop];
                
                state = AP_PLAYING;                
                if (!audioStarted && delegate && [delegate respondsToSelector:@selector(audioPlayerDidBeginPlayback:)])
                {
                    [delegate audioPlayerDidBeginPlayback:self];
                }
                
                audioStarted = YES;
                
                if (pausedSeek)
                {
                    pausedSeek = NO;
                    [self pause];
                }
            }
            else
            {
                NSLog(@"AudioQueue changed state in unexpected way.");
            }
        }
    }
    
    [pool release];
}

@end
