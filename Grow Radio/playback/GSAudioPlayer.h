//
//  AudioStreamer.h
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

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AudioDataFilter.h"
#import "GSAudioStream.h"

#define LOG_QUEUED_BUFFERS 0

#define kNumAQBufs 16			// Number of audio queue buffers we allocate.
								// Needs to be big enough to keep audio pipeline
								// busy (non-zero number of queued buffers) but
								// not so big that audio takes too long to begin
								// (kNumAQBufs * kAQBufSize of data must be
								// loaded before playback will start).
								//
								// Set LOG_QUEUED_BUFFERS to 1 to log how many
								// buffers are queued at any time -- if it drops
								// to zero too often, this value may need to
								// increase. Min 3, typical 8-24.
								
#define kAQDefaultBufSize 2048	// Number of bytes in each audio queue buffer
								// Needs to be big enough to hold a packet of
								// audio from the audio file. If number is too
								// large, queuing of audio before playback starts
								// will take too long.
								// Highly compressed files can use smaller
								// numbers (512 or less). 2048 should hold all
								// but the largest packets. A buffer size error
								// will occur if this number is too small.

#define kAQMaxPacketDescs 512	// Number of packet descriptions in our array

typedef enum
{
	AP_INITIALIZED = 0,
	AP_STARTING_FILE_THREAD,
	AP_WAITING_FOR_DATA,
	AP_WAITING_FOR_QUEUE_TO_START,
	AP_PLAYING,
	AP_BUFFERING,
	AP_STOPPING,
	AP_STOPPED,
	AP_PAUSED
} InternalAudioPlayerState;

typedef enum
{
	AP_NO_STOP = 0,
	AP_STOPPING_EOF,
	AP_STOPPING_USER_ACTION,
	AP_STOPPING_ERROR,
	AP_STOPPING_TEMPORARILY
} InternalAudioPlayerStopReason;

@protocol GSAudioPlayerDelegate;

@interface GSAudioPlayer : NSObject
{
    GSAudioStream *stream;
    NSThread *readDataThread;
    
	AudioQueueRef audioQueue;
	AudioFileStreamID audioFileStream;	// the audio file stream parser
	AudioStreamBasicDescription asbd;	// description of the audio
    
	AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];		        // audio queue buffers
	AudioStreamPacketDescription packetDescs[kAQMaxPacketDescs];	// packet descriptions for enqueuing audio
    
	UInt32 fillBufferIndex;	// the index of the audioQueueBuffer that is being filled
	UInt32 packetBufferSize;
    
	size_t bytesFilled;				// how many bytes have been filled
	size_t packetsFilled;			// how many packets have been filled
    
	bool inuse[kNumAQBufs];			// flags to indicate that a buffer is still in use
	NSInteger buffersUsed;
	
	InternalAudioPlayerState state;
	InternalAudioPlayerStopReason stopReason;
	OSStatus err;
	
	BOOL pausedSeek;
	
	BOOL reachedEOF;
	BOOL audioStarted;
	BOOL mappedBuffer;
	
    NSObject *stateChangeLock;                //for keeping state changes synchronized
    NSObject *streamMutationLock;             //for keeping stream change events in line with stream closing when quickly switching songs
	NSLock *readAudioDataLock;                //protects audioDataBuffer
    NSCondition *queueBufferReadyCondition;   //for handling in use flags
    
    NSError *stopError;
    
	BOOL discontinuous;			// flag to indicate middle of the stream
	
	UInt32 bitRate;				// Bits per second in the file
	UInt64 dataOffset;			// Offset of the first audio packet in the stream
	UInt64 fileLength;			// Length of the file in bytes
	UInt64 seekByteOffset;		// Seek offset within the file in bytes
	UInt64 audioDataByteCount;  // Used when the actual number of audio bytes in
								// the file is known (more accurate than assuming
								// the whole file is audio)
	
	UInt64 bytesDownloaded;

	UInt64 processedPacketsCount;		// number of packets accumulated for bitrate estimation
	UInt64 processedPacketsSizeTotal;	// byte size of accumulated estimation packets

	double seekTime;
	double sampleRate;			// Sample rate of the file (used to compare with
								// samples played by the queue for current playback
								// time)
	double packetDuration;		// sample rate times frames per packet
	double lastProgress;		// last calculated progress point

	NSString *bufferFilePath;
	
	uint8_t *audioDataBuffer;
	volatile int32_t writeOffset;
	volatile int32_t readOffset;
	
	NSUInteger downloadBackgroundTask;
	
	id<GSAudioPlayerDelegate> delegate;
    
    BOOL failed;
}

@property(assign) id<GSAudioPlayerDelegate> delegate;
@property(readonly) GSAudioStream *stream;

@property(readonly) UInt64 fileLength;

@property (readonly) UInt32 bitRate;

- (id)initWithStream:(GSAudioStream *)aStream;

-(void)start;

-(void)play;
-(void)pause;
-(void)stop;

-(BOOL)isStarted;
-(BOOL)isPlaying;
-(BOOL)isPaused;
-(BOOL)isBuffering;
-(BOOL)didFail;
-(BOOL)isFinishing;
-(BOOL)didFinish;

-(void)togglePlayback;

-(double)duration;
-(double)position;
-(double)bufferedSeconds;

-(double)calculatedBitRate;

-(void)seekTo:(double) pos;

@end

@protocol GSAudioPlayerDelegate <NSObject>

@optional
-(void)audioPlayerDidBeginPlayback:(GSAudioPlayer *)player;

-(void)audioPlayerStartedBuffering:(GSAudioPlayer *)player;
-(void)audioPlayerFinishedBuffering:(GSAudioPlayer *)player;
-(void)audioPlayerPlayStatusChanged:(BOOL)paused;

-(void)audioPlayerWillFinishPlaying:(GSAudioPlayer *)player;
-(void)audioPlayerDidFinishPlaying:(GSAudioPlayer *)player reachedEnd:(BOOL)end;

-(void)audioPlayer:(GSAudioPlayer *)player audioFileCachedAtTempPath:(NSString *)path;

-(void)audioPlayer:(GSAudioPlayer *)player playbackDidFailWithError:(NSError *)error;

-(void)audioPlayerBeginInterruption:(GSAudioPlayer *)player didPause:(BOOL)paused;
-(void)audioPlayerEndInterruption:(GSAudioPlayer *)player;

@end
