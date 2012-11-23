//
//  JSVideoScrubber.m
//  JSVideoScrubber
//
//  Created by jaminschubert on 9/8/12.
//  Copyright (c) 2012 jaminschubert. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "JSVideoScrubber.h"

@interface JSVideoScrubber ()

@property (strong) AVAssetImageGenerator *assetImageGenerator;
@property (strong) NSMutableArray *actualOffsets;
@property (strong) NSMutableDictionary *imageStrip;
@property (assign) size_t sourceWidth;
@property (assign) size_t sourceHeight;

@property (strong) UIImage *marker;
@property (assign) CGFloat markerLocation;

@end

@implementation JSVideoScrubber

#pragma mark - Memory

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        [self initScrubber];
    }
    
    return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self initScrubber];
    }
    
    return self;
}

- (void) initScrubber
{
    self.actualOffsets = [NSMutableArray array];
    self.imageStrip = [NSMutableDictionary dictionary];
    
    self.marker = [UIImage imageNamed:@"marker"];
}

#pragma mark - UIView

- (void) drawRect:(CGRect) rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    for (int offset = 0; offset < [self.actualOffsets count]; offset++) {
        NSNumber *time = [self.actualOffsets objectAtIndex:offset];
        CGImageRef image = (__bridge CGImageRef)([self.imageStrip objectForKey:time]);
        
        size_t height = CGImageGetHeight(image);
        size_t width = CGImageGetWidth(image);
        
        CGRect forOffset = CGRectMake((rect.origin.x + (offset * width)), rect.origin.y, width, height);
        CGContextDrawImage(context, forOffset, image);
    }
    
    CGFloat shift = self.marker.size.width / 2.0;
    CGRect markerOffset = CGRectMake(self.markerLocation - shift, rect.origin.y, self.marker.size.width, self.marker.size.height);
    CGContextDrawImage(context, markerOffset, [self.marker CGImage]);
}

#pragma mark - UIControl

- (BOOL) beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGPoint touchPoint = [touch locationInView:self];
    CGFloat shift = self.marker.size.width / 2.0;
    
    if (touchPoint.x >= (self.markerLocation - shift) && touchPoint.x <= (self.markerLocation + shift)) {
        return YES;
    }
    
    return NO;
}

- (BOOL) continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGPoint touchPoint = [touch locationInView:self];
    
    if (self.markerLocation >= self.frame.size.width) {
        self.markerLocation -= 1.0f;
        return NO;
    }
    
    self.markerLocation = touchPoint.x;
    self.markerOffset = [self offsetForMarker];
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsDisplay];
    
    return YES;
}

//- (void) endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
//{
//    
//}

#pragma mark - Interface

- (void) setupControlWithAVAsset:(AVAsset *) asset
{
    self.assetImageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    
    CMTime actualTime;
    NSError *error = nil;
    
    CGImageRef image = [self.assetImageGenerator copyCGImageAtTime:CMTimeMakeWithSeconds(0.0, 1) actualTime:&actualTime error:&error];
    
    if (error) {
        NSLog(@"Error copying reference image.");
    }
    
    self.sourceWidth = CGImageGetWidth(image);
    self.sourceHeight = CGImageGetHeight(image);
    
    [self createStrip:asset indexedAt:[self generateOffsets:asset]];
}

- (void) setupControlWithAVAsset:(AVAsset *) asset indexedAt:(NSArray *) requestedTimes
{
    self.assetImageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    [self createStrip:asset indexedAt:requestedTimes];
}

#pragma mark - Internal

- (void) createStrip:(AVAsset *) asset indexedAt:(NSArray *) requestedTimes
{
    self.duration = asset.duration;
    self.markerLocation = 0.0f;
    
    for (NSNumber *number in requestedTimes)
    {
        double offset = [number doubleValue];
        
        if (offset < 0 || offset > CMTimeGetSeconds(asset.duration)) {
            continue;
        }
        
        [self updateImageStrip:CMTimeMakeWithSeconds(offset, 1)];
    }
    
    //ensure keys are sorted
    [self.actualOffsets sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        double first = [obj1 doubleValue];
        double second = [obj2 doubleValue];
        
        if (first > second) {
            return NSOrderedDescending;
        }
        
        if (first < second) {
            return NSOrderedAscending;
        }
        
        return NSOrderedSame;
    }];
    
    [self setNeedsDisplay];
}

- (NSArray *) generateOffsets:(AVAsset *) asset
{
    CGFloat aspect = (self.sourceWidth * 1.0f) / self.sourceHeight;
    
    CGFloat idealInterval = self.frame.size.height * aspect;
    CGFloat intervals = self.frame.size.width / idealInterval;
    
    double duration = CMTimeGetSeconds(asset.duration);
    double offset = duration / intervals;
    
    NSMutableArray *offsets = [NSMutableArray array];

    double time = 0.0f;
    
    while (time < duration) {
        [offsets addObject:[NSNumber numberWithDouble:time]];
        time += offset;
    }
    
    return offsets;
}

- (void) updateImageStrip:(CMTime) offset
{
    CMTime actualTime;
    NSError *error = nil;
    
    CGImageRef source = [self.assetImageGenerator copyCGImageAtTime:offset actualTime:&actualTime error:&error];
    CGImageRef scaled = [self createScaledImage:source];
    
    if (error) {
        NSLog(@"Error copying image at index %f: %@", CMTimeGetSeconds(offset), [error localizedDescription]);
    }
    
    NSNumber *key = [NSNumber numberWithDouble:CMTimeGetSeconds(actualTime)];

    [self.imageStrip setObject:CFBridgingRelease(scaled) forKey:key];  //transfer img ownership to arc
    [self.actualOffsets addObject:key];
    
    CFRelease(source);
}

- (CGImageRef) createScaledImage:(CGImageRef) source
{
    CGFloat aspect = (self.sourceWidth * 1.0f) / self.sourceHeight;
    
    size_t height = (size_t)self.frame.size.height;
    size_t width = (size_t)(self.frame.size.height * aspect);

    CGColorSpaceRef colorspace = CGImageGetColorSpace(source);
    
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 width,
                                                 height,
                                                 CGImageGetBitsPerComponent(source),
                                                 (CGImageGetBytesPerRow(source) / CGImageGetWidth(source) * width),
                                                 colorspace,
                                                 CGImageGetAlphaInfo(source));
    if(context == NULL) {
        return NULL;
    }
    
    //flip image to correct for CG coordinate system
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1.0, -1.0);
    
    CGContextDrawImage(context, CGContextGetClipBoundingBox(context), source);
    
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    
    return scaled;
}

- (CGFloat) offsetForMarker
{
    CGFloat ratio = (self.markerLocation / self.frame.size.width);
    return (ratio * CMTimeGetSeconds(self.duration));
}

@end
