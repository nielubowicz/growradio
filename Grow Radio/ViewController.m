//
//  ViewController.m
//  Grow Radio
//
//  Created by chris nielubowicz on 8/20/12.
//  Copyright (c) 2012 Grow Radio. All rights reserved.
//

#import "ViewController.h"
#import "GSAudioPlayer.h"
#import "GSHTTPAudioStream.h"

#import <QuartzCore/QuartzCore.h>

@interface ViewController ()
{
    GSAudioPlayer *player;
    NSURLConnection *conn;
}
@end

@implementation ViewController

static NSString *highBitrate = @"http://stream.growradio.org:8000/high-stream";

-(void)dealloc
{
    [player release];
    [conn release];
    [super dealloc];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [[self view] setBackgroundColor:[UIColor cyanColor]];
    
    UIButton *connectButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [[connectButton layer] setBackgroundColor:[[UIColor yellowColor] CGColor]];
    [[connectButton layer] setCornerRadius:16.0];
    [[connectButton layer] setBorderColor:[[UIColor redColor] CGColor]];
    [connectButton setCenter:[[self view] center]];
    [connectButton setBounds:CGRectMake(0, 0, roundf(CGRectGetWidth([[self view] bounds])/3.0), roundf(CGRectGetWidth([[self view] bounds])/3.0))];
    
    [connectButton addTarget:self action:@selector(startStream) forControlEvents:UIControlEventTouchUpInside];
    [connectButton addTarget:self action:@selector(colorBackground:) forControlEvents:UIControlEventTouchDragInside];
    [connectButton addTarget:self action:@selector(colorBackground:) forControlEvents:UIControlEventTouchDragOutside];
    [connectButton addTarget:self action:@selector(stopStream) forControlEvents:UIControlEventTouchUpOutside];
    
    [[self view] addSubview:connectButton];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    
}

- (void)startStream
{
    NSURL *url = [NSURL URLWithString:highBitrate];
    
//    conn = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:url] delegate:self];
//    [conn start];


    GSHTTPAudioStream *s = [[[GSHTTPAudioStream alloc] initWithURL:url] autorelease];
    player = [[GSAudioPlayer alloc] initWithStream:s];
    
    [player setDelegate:self];
    [player play];
}

- (void)statusChanged:(NSNotification *)notification
{
    NSLog(@"%@, to state: %d", notification, [[notification object] state]);
}


-(void)stopStream
{
    [player stop];
    [player release];
    player = nil;
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

-(void)colorBackground:(UIEvent*)touchEvent
{
    NSLog(@"%s %@", __PRETTY_FUNCTION__, [touchEvent description]);
}

#pragma mark NSURLConnection Delegate methods
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response;
{
    NSLog(@"%@", [response allHeaderFields]);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return YES;
    }
}

@end
