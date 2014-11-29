//
//  ISDownloadManager.m
//  metadata
//
//  Created by Jason Barrie Morley on 29/11/2014.
//  Copyright (c) 2014 InSeven Limited. All rights reserved.
//

#import <AFNetworking/AFNetworking.h>
#import <ISUtilities/ISUtilities.h>

#import "ISDownloadManager.h"

@interface ISDownloadManager ()

@property (nonatomic, readonly, strong) AFHTTPSessionManager *sessionManager;

@end

@implementation ISDownloadManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        _sessionManager = [AFHTTPSessionManager manager];
        _sessionManager.completionQueue = ISDispatchQueueCreate(@"uk.co.inseven.add-to-itunes",
                                                                self,
                                                                @"operationQueue",
                                                                DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSString *)downloadURL:(NSURL *)URL
{
    __block NSString *destination = nil;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    NSProgress *p;
    NSURLSessionDownloadTask *downloadTask =
    [self.sessionManager downloadTaskWithRequest:request progress:&p destination:^NSURL *(NSURL *targetPath,
                                                                                          NSURLResponse *response) {
        
        NSString *extension = [[response suggestedFilename] pathExtension];
        NSString *filename = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:extension];
        destination = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
        return [NSURL fileURLWithPath:destination];
        
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        dispatch_semaphore_signal(sem);
    }];
    
    [downloadTask resume];
    
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    return destination;
}

@end
