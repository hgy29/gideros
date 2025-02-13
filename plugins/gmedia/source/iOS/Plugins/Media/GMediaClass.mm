//
//  GMediaClass.m
//  Test
//
//  Created by Arturs Sosins on 1/17/14.
//  Copyright (c) 2014 Gideros Mobile. All rights reserved.
//
#include "gideros.h"
#include "media.h"
#import "GMediaClass.h"
#import "EAGLView.h"
#import "AppDelegate.h"
#import "ViewController.h"



@interface UIImage (fixOrientation)

- (UIImage *)fixOrientation;

@end

@implementation UIImage (fixOrientation)

- (UIImage *)fixOrientation {
    
    // No-op if the orientation is already correct
    if (self.imageOrientation == UIImageOrientationUp) return self;
    
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (self.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, self.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, self.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (self.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, self.size.width, self.size.height,
                                             CGImageGetBitsPerComponent(self.CGImage), 0,
                                             CGImageGetColorSpace(self.CGImage),
                                             CGImageGetBitmapInfo(self.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (self.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.height,self.size.width), self.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.width,self.size.height), self.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

@end



@implementation GMediaClass

-(id)init{
    CGRect  viewRect = [[UIScreen mainScreen] bounds];
    self.videoView = [[GMediaView alloc] initWithFrame:viewRect];
    [self.videoView setBackgroundColor:[UIColor blackColor]];
    return self;
}

-(void)deinit{
    [self.videoView stop];
    self.videoView = nil;
}

-(BOOL)isCameraAvailable{
    return [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
}

-(void)takePicture{
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
    {
        [imagePicker setSourceType:UIImagePickerControllerSourceTypeCamera];
    }
    [imagePicker setDelegate:self];
    [g_getRootViewController() presentViewController:imagePicker animated:YES completion:nil];
}

-(void)takeScreenshot{
    AppDelegate *delg = [[UIApplication sharedApplication] delegate];
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)delg.viewController.glView.layer;
    eaglLayer.drawableProperties = @{
                                     kEAGLDrawablePropertyRetainedBacking: [NSNumber numberWithBool:YES],
                                     kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
                                     };

    UIImage *image = [self getSnapshot];
    if(image != nil){
        NSString *path = [self saveImage:image];
        gmedia_onMediaReceive([path UTF8String]);
    }
    else
    {
        gmedia_onMediaCanceled();
    }
    
    /*eaglLayer.drawableProperties = @{
                                     kEAGLDrawablePropertyRetainedBacking: [NSNumber numberWithBool:NO],
                                     kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
                                     };*/
}

-(void)getPicture{
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    [imagePicker setSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    [imagePicker setDelegate:self];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        // iPad Code:
        //imagePicker.navigationBar.opaque = true;
        UIViewController *c = g_getRootViewController();
        
        [self removePopover];
        self.popover =
        [[UIPopoverController alloc] initWithContentViewController:imagePicker];
        self.popover.delegate = self;
        [self.popover presentPopoverFromRect:CGRectMake(0.0, 0.0, 400.0, 400.0)
                                 inView:c.view
               permittedArrowDirections:UIPopoverArrowDirectionAny
                               animated:YES];
    } else {
        // iPhone Code:
        [g_getRootViewController() presentViewController:imagePicker animated:YES completion:nil];
    }
}

-(void)addToGallery:(NSString*) path{
    UIImage* image = [UIImage imageWithContentsOfFile:path];
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
}

-(void)playVideo:(NSString *)path shouldForce:(BOOL)force{
    NSURL *videoURL=[[NSURL alloc] initFileURLWithPath:path];
    
    UIViewController *v = g_getRootViewController();
    [v.view addSubview:self.videoView];
    [self.videoView play:videoURL shouldForce:force];
}

-(void) imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [self removePopover];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
    if(image != nil){
        UIImage *fixImage = [image fixOrientation];
        NSString *path = [self saveImage:fixImage];
        gmedia_onMediaReceive([path UTF8String]);
    }
    else
    {
        gmedia_onMediaCanceled();
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [self removePopover];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];

    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    gmedia_onMediaCanceled();
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController{
    self.popover = nil;
    gmedia_onMediaCanceled();
}

- (NSString*)saveImage: (UIImage*)image
{
    NSString* path = @"";
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                             NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"yyyyMMdd_HHmmss"];
    NSString *dateString = [dateFormat stringFromDate:date];
    path = [documentsDirectory stringByAppendingPathComponent:
                          [dateString stringByAppendingString: @"_gideros.png"] ];
    NSData* data = UIImagePNGRepresentation(image);
    [data writeToFile:path atomically:YES];
    return path;
}

-(void)removePopover{
    if(self.popover != nil)
    {
        [self.popover dismissPopoverAnimated:YES];
        self.popover = nil;
    }
}

- (UIImage*) getSnapshot {
    int s = 1;
    UIScreen* screen = [UIScreen mainScreen];
    if ([screen respondsToSelector:@selector(scale)]) {
        s = (int) [screen scale];
    }
    
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    
    int x = 0;
    int y = 0;
    int width = viewport[2];
    int height = viewport[3];
    
    int myDataLength = width * height * 4;
    GLubyte *buffer = (GLubyte *) malloc(myDataLength);
    GLubyte *buffer2 = (GLubyte *) malloc(myDataLength);
    glReadPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    for(int y1 = y; y1 < height; y1++) {
        for(int x1 = x; x1 <width * 4; x1++) {
            buffer2[(height - 1 - y1) * width * 4 + x1] = buffer[y1 * 4 * width + x1];
        }
    }
    free(buffer);
    
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer2, myDataLength, NULL);
    int bitsPerComponent = 8;
    int bitsPerPixel = 32;
    int bytesPerRow = 4 * width;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    CGImageRef imageRef = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow, colorSpaceRef, bitmapInfo, provider, NULL, NO, renderingIntent);
    CGColorSpaceRelease(colorSpaceRef);
    CGDataProviderRelease(provider);
    UIImage *image = [ UIImage imageWithCGImage:imageRef scale:s orientation:UIImageOrientationUp ];
    return image;
}
@end

@implementation GMediaView

-(void)play:(NSURL*)videoURL shouldForce:(BOOL)force{
    self.force = force;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin |    UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
    UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self setContentMode:UIViewContentModeScaleAspectFit];
    AVPlayerItem* playerItem = [AVPlayerItem playerItemWithURL:videoURL];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    self.player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
    
    self.Alayer = [AVPlayerLayer layer];
    [self.Alayer setPlayer:self.player];
    if([self isPortrait])
    {
        [self.Alayer setFrame:[[UIScreen mainScreen] bounds]];
    }
    else{
        CGRect b = [[UIScreen mainScreen] bounds];
        [self.Alayer setFrame:CGRectMake(0, 0, b.size.height, b.size.width)];
    }
    [self.Alayer setBackgroundColor:[UIColor blackColor].CGColor];
    [self.Alayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    [self.layer addSublayer:self.Alayer];
    [self.player play];
}

-(void)itemDidFinishPlaying:(NSNotification *) notification {
    [self stop];
    gmedia_onMediaCompleted();
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	if(!self.force)
        [self stop];
}

-(BOOL)isPortrait{
    return ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait || [UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortraitUpsideDown);
}


-(void)stop{
    if(self.Alayer != nil)
    {
        [self.Alayer removeFromSuperlayer];
        self.Alayer = nil;
    }
    if(self.player != nil){
        [self.player pause];
        self.player = nil;
    }
    if([self superview]!=nil)
        [self removeFromSuperview];
}

@end
