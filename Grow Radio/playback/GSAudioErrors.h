/*
 *  GSAudioErrors.h
 *  Grooveshark
 *
 *  Created by Mike Cugini on 10/11/10.
 *  Copyright 2010 escapemg. All rights reserved.
 *
 */

#define GSAudioErrorDomain @"GSAudioErrorDomain"

typedef enum
{
	NoError = 0, //AS_NO_ERROR = 0,
	AudioDataNotFound, //AS_AUDIO_DATA_NOT_FOUND,
	AudioQueueError, //
					 // AS_AUDIO_QUEUE_CREATION_FAILED,
					 // AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED,
					 // AS_AUDIO_QUEUE_ENQUEUE_FAILED,
					 // AS_AUDIO_QUEUE_ADD_LISTENER_FAILED,
					 // AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED,
					 // AS_AUDIO_QUEUE_START_FAILED,
					 // AS_AUDIO_QUEUE_PAUSE_FAILED,
					 // AS_AUDIO_QUEUE_BUFFER_MISMATCH,
					 // AS_AUDIO_QUEUE_DISPOSE_FAILED,
					 // AS_AUDIO_QUEUE_STOP_FAILED,
					 // AS_AUDIO_QUEUE_FLUSH_FAILED,
					 // AS_AUDIO_BUFFER_TOO_SMALL
					 // AS_GET_AUDIO_TIME_FAILED,
	
	AudioStreamerError, // AS_AUDIO_STREAMER_FAILED,
						// AS_FILE_STREAM_SEEK_FAILED,
						// AS_FILE_STREAM_PARSE_BYTES_FAILED,
						// AS_FILE_STREAM_OPEN_FAILED,
						// AS_FILE_STREAM_CLOSE_FAILED,
						//	AS_FILE_STREAM_GET_PROPERTY_FAILED,
	//Streaming
	NetworkError, //AS_NETWORK_CONNECTION_FAILED,
	FileSystemError,
	UnknownError,
} GSAudioError;