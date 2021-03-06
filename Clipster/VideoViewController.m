//
//  ClipDetailsViewController.m
//  Clipster
//
//  Created by Nathan Speller on 4/11/14.
//  Copyright (c) 2014 Nathan Speller. All rights reserved.
//

#import "VideoViewController.h"
#import "Clip.h"
#import "SmallClipCell.h"
#import "ProfileViewController.h"
#import "VideoPlayerViewController.h"
#import "ClippingViewController.h"
#import "YouTubeVideo.h"
#import "VideoControlView.h"
#import "YouTubeParser.h"
#import "ClipsterColors.h"
#import <MBProgressHUD/MBProgressHUD.h>

static const CGFloat MIN_VIDEO_CONTROL_SIZE = 5;
static const CGFloat MAX_VIDEO_CONTROL_SIZE = 44;

@interface VideoViewController ()
@property (weak, nonatomic) IBOutlet PFImageView *thumbnailImage;
@property (weak, nonatomic) IBOutlet UIView *videoPlayerContainer;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet VideoControlView *videoControlView;

@property (nonatomic, assign) CGPoint panStartPosition;
@property (nonatomic, strong) NSMutableArray *clips;
@property (nonatomic, strong) Clip *activeClip;
@property (nonatomic, strong) SmallClipCell *prototype;

@property (nonatomic, strong) NSString *videoId;
@property (nonatomic, strong) NSString *videoTitle;
@property (nonatomic, assign) CGFloat lastTableViewScrollPosition;

@property (nonatomic, strong) VideoPlayerViewController *playerController;
@property (nonatomic, assign) NSInteger hudCounter;

@property (nonatomic, strong) UIButton *backButton;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *clipButton;


@property (nonatomic, assign) BOOL isVideoPlaying;
@property (nonatomic, assign) CGFloat currentPlaybackPosition;
@property (nonatomic, assign) NSTimeInterval currentPlaybackTime;
@property (nonatomic, strong) NSTimer *playbackMonitorTimer;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, assign) BOOL wasVideoPlayingBeforeScrub;
@property (nonatomic, assign) BOOL isVideoControlMinimized;
@property (nonatomic, assign) NSInteger numberTimerEventsSinceVideoInteraction;
@property (nonatomic, assign) CGFloat videoControlHeight;
@property (nonatomic, assign) CGFloat videoControlYOffset;
@property (nonatomic, strong) NSMutableArray *popularityHistogram;
@property (nonatomic, strong) id timeObserverHandle;
@property (weak, nonatomic) IBOutlet UIView *currentPlaybackLineView;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *videoHeightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *videoControlVerticalOffsetConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *videoControlHeightConstraint;

@end

@implementation VideoViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _clips = [[NSMutableArray alloc] init];
    }
    return self;
}

- (id)initWithClip:(Clip *)clip {
    self = [self initWithVideoId:clip.videoId andTitle:clip.videoTitle];
    if (self) {
        _activeClip = clip;
    }
    return self;
}

- (void)onBackButton:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (id)initWithVideoId:(NSString *)videoId andTitle:(NSString *)videoTitle
{
    self = [super init];
    if (self) {
        _hudCounter = 0;
        _videoId = videoId;
        _videoTitle = videoTitle;
        _playerController = [[VideoPlayerViewController alloc] init];
    }
    return self;
}

- (void)setActiveClip:(Clip *)activeClip
{
    _activeClip = activeClip;
    [self updatePlayerToActiveClip];
}

#pragma mark - Custom Video Control
static const int NUMBER_HISTOGRAM_BINS = 100;


- (void)setupCustomVideoControl
{
    UIView *movieView = self.playerController.view;
    
    UITapGestureRecognizer *tapVideoGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapVideo:)];
    tapVideoGesture.delegate = self;
    [movieView addGestureRecognizer:tapVideoGesture];
    
    // play/pause button
    self.playButton.alpha = 1.0;
    self.playButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.playButton addTarget:self action:@selector(onPlayButtonClicked) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playButton];
    
    // clip button
    self.clipButton.alpha = 1.0;
    self.clipButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.clipButton setImage:[UIImage imageNamed:@"clip_btn.png"] forState:UIControlStateNormal];
    [self.clipButton addTarget:self action:@selector(clipAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.clipButton];

    // scrubbing/vis region

    self.videoControlView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    self.videoControlView.color = [ClipsterColors green];
    
    // Initialize popularity histogram
    self.popularityHistogram = [[NSMutableArray alloc] init];
    for (int i=0; i<NUMBER_HISTOGRAM_BINS; i++) {
        [self.popularityHistogram addObject:@0.0];
    }
    self.videoControlView.popularityHistogram = self.popularityHistogram;
    
    UIPanGestureRecognizer *panScrub = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panScrubber:)];
    [self.videoControlView addGestureRecognizer:panScrub];
    UITapGestureRecognizer *tapScrub = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapScrubber:)];
    [self.videoControlView addGestureRecognizer:tapScrub];
    
    // Setting the current playback position will set playback time and progress
    self.currentPlaybackLineView.hidden = NO;
    if (self.activeClip) {
        [self setCurrentPlaybackPositionWithTime:self.activeClip.timeStart];
        [self updateCurrentPlaybackLineViewWithPosition:self.currentPlaybackPosition];
    }
}

- (void)addAllClipsToHistogram
{
    for (int i=0; i<self.popularityHistogram.count; i++) {
        self.popularityHistogram[i] = @0;
    }
    for (Clip *clip in self.clips) {
        [self addClipToHistogram:clip];
    }
    // reload table simply because this is called once we have the timeline for clips
    [self.tableView reloadData];
}

- (void)addClipToHistogram:(Clip *)clip
{
    NSArray *timeBins = [self timeBinsForClip:clip];
    int startBin = [timeBins[0] integerValue];
    int endBin = [timeBins[1] integerValue];
    for (int i=startBin; i<endBin; i++) {
        self.popularityHistogram[i] = @([self.popularityHistogram[i] floatValue] + 0.2);
    }
    [self.videoControlView setNeedsDisplay];
}

- (NSArray *)timeBinsForClip:(Clip *)clip
{
    float durationMS = self.playerController.duration * 1000.0f;
    int startBin = floor(clip.timeStart*NUMBER_HISTOGRAM_BINS/durationMS);
    int endBin = ceil(clip.timeEnd*NUMBER_HISTOGRAM_BINS/durationMS);
    startBin = startBin < 0 ? 0 : startBin;
    endBin = endBin > (NUMBER_HISTOGRAM_BINS-1) ? (NUMBER_HISTOGRAM_BINS-1) : endBin;
    return @[@(startBin), @(endBin)];
}

- (CGRect)rectForClip:(Clip *)clip cell:(SmallClipCell *)cell
{
    NSArray *timeBins = [self timeBinsForClip:clip];
    // offset to midpoint of bins
    float startBin = [timeBins[0] floatValue];
    float endBin = [timeBins[1] floatValue];
    float sizeBin = cell.frame.size.width / NUMBER_HISTOGRAM_BINS;
    float width = (endBin - startBin) * sizeBin;
    float x = startBin * sizeBin;
    return CGRectMake(x, 0, width, cell.frame.size.height);
}

- (void)updateCurrentPlaybackLineViewWithPosition:(CGFloat)position
{
    CGRect frame = self.currentPlaybackLineView.frame;
    self.currentPlaybackLineView.frame = CGRectMake(self.currentPlaybackPosition, frame.origin.y, frame.size.width, frame.size.height);
}

- (void)setLandscapeVideoControlOffset
{
    if (self.isVideoControlMinimized) {
        self.videoControlVerticalOffsetConstraint.constant = -5;
    } else {
        self.videoControlVerticalOffsetConstraint.constant = -40;
    }
}

- (void)setIsVideoControlMinimized:(BOOL)isVideoControlMinimized
{
    _isVideoControlMinimized = isVideoControlMinimized;
    
    // show/hide buttons
    self.playButton.hidden = isVideoControlMinimized;
    self.backButton.hidden = isVideoControlMinimized;
    self.clipButton.hidden = isVideoControlMinimized;
    // set past frame resizes automatically
    self.currentPlaybackPosition = self.currentPlaybackPosition;
    
    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
        [self setLandscapeVideoControlOffset];
    }
}

- (void)setIsVideoPlaying:(BOOL)isVideoPlaying
{
    if (isVideoPlaying) {
        [self.playButton setImage:[UIImage imageNamed:@"pause_btn.png"] forState:UIControlStateNormal];
        [self.playerController play];
        [self startMonitorPlaybackTimer];
    } else if (!isVideoPlaying) {
        [self.playButton setImage:[UIImage imageNamed:@"play_btn.png"] forState:UIControlStateNormal];
        [self.playerController pause];
        [self stopMonitorPlaybackTimer];
    }
    self.numberTimerEventsSinceVideoInteraction = 0;
    _isVideoPlaying = isVideoPlaying;
}

- (void)startMonitorPlaybackTimer
{
    __weak typeof(self) weakSelf = self;
    self.timeObserverHandle = [self.playerController addTimeObserverWithBlock:^(float time) {
        [weakSelf monitorPlayback:time];
    }];
}

- (void)stopMonitorPlaybackTimer
{
    [self.playerController removeTimeObserver:self.timeObserverHandle];
}

- (void)setCurrentPlaybackPosition:(CGFloat)currentPlaybackPosition
{
    // Change width of scrub depending on new playback position
    self.videoControlView.currentPlaybackPosition = currentPlaybackPosition;
    [self.videoControlView setNeedsDisplay];
    
    // Change position of current line view
    [self updateCurrentPlaybackLineViewWithPosition:_currentPlaybackPosition];
    
    _currentPlaybackPosition = currentPlaybackPosition;
}

- (void)monitorPlayback:(float)currentPlaybackTime
{
    // Set the playback position feedback
    CGFloat percentPlayed = currentPlaybackTime / self.playerController.duration;
    self.currentPlaybackPosition = self.videoControlView.frame.size.width * percentPlayed;
}

- (void)tapVideo:(UITapGestureRecognizer *)tapGesture
{
    // toggle video controls minimize
    self.numberTimerEventsSinceVideoInteraction = 0;
    self.isVideoControlMinimized = !self.isVideoControlMinimized;
}

- (void)tapScrubber:(UITapGestureRecognizer *)tapGesture
{
    CGPoint point = [tapGesture locationInView:self.videoControlView];
    self.currentPlaybackPosition = point.x;
    CGFloat percentPlayed = self.currentPlaybackPosition / self.videoControlView.bounds.size.width;
    [self.playerController seekToTime:(self.playerController.duration * percentPlayed) done:nil];
    self.numberTimerEventsSinceVideoInteraction = 0;
}

- (void)panScrubber:(UIPanGestureRecognizer *)panGesture
{
    if (panGesture.state == UIGestureRecognizerStateBegan) {
        // might want to only start scrubbing if we are close to the current playback position
        self.isScrubbing = YES;
        self.numberTimerEventsSinceVideoInteraction = 0;
    } else if (panGesture.state == UIGestureRecognizerStateChanged && self.isScrubbing) {
        // change current playback time based on position
        CGPoint point = [panGesture locationInView:self.videoControlView];
        self.currentPlaybackPosition = point.x;
        CGFloat percentPlayed = self.currentPlaybackPosition / self.videoControlView.bounds.size.width;
        [self.playerController seekToTime:(self.playerController.duration * percentPlayed) done:nil];
        self.numberTimerEventsSinceVideoInteraction = 0;
    } else if (panGesture.state == UIGestureRecognizerStateEnded) {
        self.isScrubbing = NO;
    } else if (panGesture.state == UIGestureRecognizerStateFailed) {
        self.isScrubbing = NO;
    }
}

- (void)setIsScrubbing:(BOOL)isScrubbing
{
    if (!_isScrubbing && isScrubbing) {
        // Going from not scrubbing to scrubbing capture video play state
        self.wasVideoPlayingBeforeScrub = self.isVideoPlaying;
        self.isVideoPlaying = NO;
    } else if (_isScrubbing && !isScrubbing) {
        // Going from scrubbing to not scrubbing
        self.isVideoPlaying = self.wasVideoPlayingBeforeScrub;
    }
    _isScrubbing = isScrubbing;
}

- (void)onPlayButtonClicked
{
    self.isVideoPlaying = !self.isVideoPlaying;
}

#pragma mark - UIView

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{

    if (self.playerController.isReady) {
        NSTimeInterval time = (NSTimeInterval) self.playerController.currentTimeInSeconds;
        [self setCurrentPlaybackPositionWithTime:time];
        [self updateCurrentPlaybackLineViewWithPosition:self.currentPlaybackPosition];
    } else {
        [self updateCurrentPlaybackLineViewWithPosition:0];
    }
    
    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
        self.videoHeightConstraint.constant = self.view.frame.size.height;
        self.videoControlHeightConstraint.constant = MAX_VIDEO_CONTROL_SIZE;
        [self setLandscapeVideoControlOffset];
        [self.view bringSubviewToFront:self.videoControlView];
    } else {
        [self.view bringSubviewToFront:self.videoPlayerContainer];
        self.videoHeightConstraint.constant = 180;
        self.videoControlVerticalOffsetConstraint.constant = 0;
    }
    
    [self.view bringSubviewToFront:self.clipButton];
    [self.view bringSubviewToFront:self.playButton];
    [self.view bringSubviewToFront:self.backButton];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if ([self respondsToSelector:@selector(edgesForExtendedLayout)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    // TODO: move this to nib
    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.backButton setImage:[UIImage imageNamed:@"back_btn.png"] forState:UIControlStateNormal];
    self.backButton.alpha = 1.0;
    self.backButton.frame = CGRectMake(10, 10, 40, 40);
    [self.backButton addTarget:self action:@selector(onBackButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];
    [self.view bringSubviewToFront:self.backButton];
    
    // hide line view until we have the video data
    self.currentPlaybackLineView.hidden = YES;

    [self addPlayerViewToContainer];
    
    if (self.activeClip && self.activeClip.thumbnail) {
        self.thumbnailImage.file = self.activeClip.thumbnail;
        [self.thumbnailImage loadInBackground];
    }
    
    [self pendingNetworkRequest];
    
    [YouTubeParser videoURLWithYoutubeID:self.videoId done:^(NSURL *videoURL, NSError *error) {
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
            [alert show];
        } else {
            // TODO: come up with a better way to call addAllClipsToHistogram without blocking the hud from disappearing
            // it has to wait three things to finish: clips to load, the video url parsing to finish, and the video to load
            [self pendingNetworkRequest];
            [self.playerController loadVideoWithURL:videoURL ready:^{
                [self updatePlayerToActiveClip];
                [self setupCustomVideoControl];
                [self pendingNetworkRequestDone];
                self.isVideoPlaying = TRUE;
            }];
        }
        [self pendingNetworkRequestDone];
    }];
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    UINib *clipCellNib = [UINib nibWithNibName:@"SmallClipCell" bundle:nil];
    self.prototype = [clipCellNib instantiateWithOwner:self options:nil][0];
    [self.tableView registerNib:clipCellNib forCellReuseIdentifier:@"ClipCell"];
    [self fetchClips];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [[self navigationController] setNavigationBarHidden:YES animated:YES];
    [[UIApplication sharedApplication] setStatusBarHidden:YES
                                            withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self stopMonitorPlaybackTimer];
    [super viewWillDisappear:animated];
    [[self navigationController] setNavigationBarHidden:NO animated:YES];
    [[UIApplication sharedApplication] setStatusBarHidden:NO
                                            withAnimation:UIStatusBarAnimationFade];
}

- (void)setCurrentPlaybackPositionWithTime:(NSTimeInterval)time
{
    if (self.playerController.duration) {
        // update the line immediately or we get some lag
        CGFloat percentPlayed = time / self.playerController.duration;
        self.currentPlaybackPosition = percentPlayed * self.videoControlView.bounds.size.width;
    }
}

- (void)updatePlayerToActiveClip
{
    [self setCurrentPlaybackPositionWithTime:self.activeClip.timeStart];
    [self.playerController seekToTime:self.activeClip.timeStart/1000.0f done:nil];
}

- (void)addPlayerViewToContainer
{
    if (![self.playerController.view isDescendantOfView:self.videoPlayerContainer]) {
        [self.playerController.view setFrame: self.videoPlayerContainer.frame];
        [self.videoPlayerContainer addSubview: self.playerController.view];
    }
}

#pragma mark - Network fetching

- (void)fetchClips
{
    [self pendingNetworkRequest];
    PFQuery *query = [PFQuery queryWithClassName:@"Clip"];
    [query whereKey:@"videoId" equalTo:self.videoId];
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        if (!error) {
            // The find succeeded.
            NSLog(@"Successfully retrieved %d clips.", objects.count);
            self.clips = [objects mutableCopy];
            
            NSInteger row = [self.clips indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                return [self.activeClip.objectId isEqualToString:((Clip *)obj).objectId];
            }];
            
            [self.tableView reloadData];
            
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] animated:YES scrollPosition:UITableViewScrollPositionMiddle];
            [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] animated:YES];
            
        } else {
            // Log details of the failure
            NSLog(@"Error: %@ %@", error, [error userInfo]);
        }
        [self pendingNetworkRequestDone];
    }];
}

#pragma mark - ClipCreationDelegate

- (void)creationDone:(Clip *)clip
{
    [self dismissViewControllerAnimated:YES completion:nil];
    
    // Do we need this save if we are already saving after thumbnail?
    [clip saveInBackground];
    
    [self.playerController frameAtTimeWithSeconds:self.playerController.currentTimeInSeconds done:^(NSError *error, CGImageRef imageRef) {
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        clip.thumbnail = [PFFile fileWithData:UIImageJPEGRepresentation(image, 0.05f)];
        [clip saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
            [self.tableView reloadData];
        }];
    }];
    
    // We need to add the clip to the histogram
    [self addClipToHistogram:clip];
    
    [self.clips addObject:clip];
    [self.tableView reloadData];
    
    // TODO: When we finish adding clip we need to sort correctly
    NSInteger row = [self.clips indexOfObject:clip];
    [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] animated:YES scrollPosition:UITableViewScrollPositionTop];
    [self addPlayerViewToContainer];
    [self updatePlayerToActiveClip];
    self.isVideoPlaying = YES;
    
    // Dirty the stream when we've created a new clip
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SetStreamDirty" object:nil];
}

- (void)creationCanceled
{
    [self dismissViewControllerAnimated:YES completion:nil];
    [self addPlayerViewToContainer];
    [self updatePlayerToActiveClip];
    self.isVideoPlaying = YES;
}

#pragma mark - ClipCellDelegate

- (void)didClickUsername:(NSString *)username
{
    ProfileViewController *profileVC = [[ProfileViewController alloc] initWithUsername:username];
    [self.navigationController pushViewController:profileVC animated:YES];
}

#pragma mark - UITableViewDelegate and UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SmallClipCell *cell = (SmallClipCell *)[self.tableView dequeueReusableCellWithIdentifier:@"ClipCell" forIndexPath:indexPath];
    
    Clip *clip = (Clip *)self.clips[indexPath.row];
    cell.clip = clip;
    if (self.playerController.duration > 0) {
        cell.timelineRect = [self rectForClip:clip cell:cell];
    }
    cell.clipCellDelegate = self;
    
    // add a delete button for author's and flag button otherwise
    NSMutableArray *rightUtilityButtons = [NSMutableArray new];
    NSString *utilityButtonTitle = @"Flag";
    UIColor *utilityButtonColor = [UIColor darkGrayColor];
    if ([clip.user.objectId isEqualToString:[User currentUser].objectId]) {
        utilityButtonTitle = @"Delete";
        utilityButtonColor = [ClipsterColors red];
    }
    [rightUtilityButtons sw_addUtilityButtonWithColor: utilityButtonColor
                                                title: utilityButtonTitle];
    cell.rightUtilityButtons = rightUtilityButtons;
    cell.delegate = self;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Clip *clip = self.clips[indexPath.row];
    self.activeClip = clip;
    // show the green flash
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.clips.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    return [SmallClipCell heightForClip:[self.clips objectAtIndex:indexPath.row] cell:self.prototype];
}

#pragma mark - SWTableViewCellDelegate
- (void)swipeableTableViewCell:(SWTableViewCell *)cell didTriggerRightUtilityButtonWithIndex:(NSInteger)index
{
    switch (index) {
        case 0:
        {
            // First utility button was pressed
            NSIndexPath *cellIndexPath = [self.tableView indexPathForCell:cell];
            Clip *clip = self.clips[cellIndexPath.row];
            
            if ([clip.user.objectId isEqualToString:[User currentUser].objectId]) {
                // Author is deleting the clip
                [clip deleteInBackground];
                [self.clips removeObjectAtIndex:cellIndexPath.row];
                [self.tableView deleteRowsAtIndexPaths:@[cellIndexPath] withRowAnimation:UITableViewRowAnimationLeft];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SetStreamDirty" object:nil];
            } else {
                // Flag the clip as inappropriate, this will notify Clipster team and user/clip will be removed
                clip.eulaFlag = true;
                [clip saveInBackground];
                [cell hideUtilityButtonsAnimated:YES];
            }
            
            break;
        }
        default:
            break;
    }
}

# pragma mark - Clip Button
    
- (IBAction)clipAction:(id)sender
{
    int currentTime = self.playerController.currentTimeInSeconds * 1000;
    
    Clip *clip = [[Clip alloc] init];
    clip.timeStart = currentTime;
    clip.timeEnd = currentTime + 10000;
    clip.videoId = self.videoId;
    clip.videoTitle = self.videoTitle;
    clip.user = (User *)[PFUser currentUser];
    
    ClippingViewController *clippingVC = [[ClippingViewController alloc] initWithClip:clip playerController:self.playerController];
    clippingVC.delegate = self;
    [self presentViewController:clippingVC animated:YES completion:nil];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.lastTableViewScrollPosition = self.tableView.contentOffset.y;
}

-(void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (self.tableView.isDragging) {
        CGFloat tableViewScrollDelta = self.lastTableViewScrollPosition - self.tableView.contentOffset.y;
        
        CGFloat newSize = self.videoControlHeightConstraint.constant + tableViewScrollDelta;
        
        if (tableViewScrollDelta < 0) { // dragging content up
            newSize = MAX(newSize, MIN_VIDEO_CONTROL_SIZE);
        } else { // dragging content down
            newSize = MIN(newSize, MAX_VIDEO_CONTROL_SIZE);
        }

        // make sure the size is always enough to cover the the part of the dummy header cell that is showing
        // fixes a bad state that can occur if the user starts scrolling up and then back down
        newSize = MAX(MAX_VIDEO_CONTROL_SIZE- MAX(self.tableView.contentOffset.y, 0), newSize);
        
        self.videoControlHeightConstraint.constant = newSize;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

# pragma mark - MBProgressHUD helpers
- (void)pendingNetworkRequest
{
    @synchronized(self) {
        if (self.hudCounter == 0) {
            [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        }
        self.hudCounter++;
    }
}

- (void)pendingNetworkRequestDone
{
    @synchronized(self) {
        self.hudCounter--;
        if (self.hudCounter == 0) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [self updateAfterAllNetworkRequests];
        }
    }
}

- (void) updateAfterAllNetworkRequests
{
    // update histogram with clips
    [self addAllClipsToHistogram];
}

@end
