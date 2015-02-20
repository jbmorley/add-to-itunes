//
// Copyright (c) 2013-2014 InSeven Limited.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

#import <Foundation/Foundation.h>
#import <ISMediaKit/ISMediaKit.h>
#import <ISArgumentParser/ISArgumentParser.h>

#import "ISDownloadManager.h"

BOOL downloadFields(NSMutableDictionary *dictionary, NSArray *fields)
{
    ISDownloadManager *manager = [ISDownloadManager new];
    for (NSString *field in fields) {
        
        NSString *value = dictionary[field];
        if (value) {
            printf("Downloading '%s'...\n", [value UTF8String]);
            NSURL *URL = [NSURL URLWithString:value];
            NSString *download = [manager downloadURL:URL];
            if (download == nil) {
                return NO;
            }
            dictionary[field] = download;
        }
        
    }
    return YES;
}

static NSString *const AddMovieScript =
@"tell application \"iTunes\"\n"
@"  set filename to POSIX file \"%@\"\n"
@"  set i to (add filename)\n"
@"  tell i\n"
@"    set video kind to Movie\n"
@"    set name to \"%@\"\n"
@"\n"
@"    try\n"
@"      set f to POSIX file \"%@\"\n"
@"      set data of artwork 1 to (read f as picture)\n"
@"    end try\n"
@"\n"
@"  end tell\n"
@"end tell\n";

static NSString *const AddShowScript =
@"tell application \"iTunes\"\n"
@"  set filename to POSIX file \"%@\"\n"
@"  set i to (add filename)\n"
@"  tell i\n"
@"    set video kind to TV show\n"
@"    set show to \"%@\"\n"
@"    set name to \"%@\"\n"
@"    set season number to %ld\n"
@"    set episode number to %ld\n"
@"    set track number to %ld\n"
@"\n"
@"    try\n"
@"      set f to POSIX file \"%@\"\n"
@"      set data of artwork 1 to (read f as picture)\n"
@"    end try\n"
@"\n"
@"  end tell\n"
@"end tell\n";

BOOL runScript(NSString *script, BOOL debug)
{
    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/bin/osascript";
    task.arguments = @[@"-e", script];
    
    if (debug) {
        printf("Running AppleScript:\n%s", [script UTF8String]);
    }
    
    NSPipe *output = [NSPipe pipe];
    [task setStandardOutput:output];
    NSPipe *error = [NSPipe pipe];
    [task setStandardError:error];
    
    [task launch];
    
    [task waitUntilExit];
    int status = [task terminationStatus];
    if (status) {
        return NO;
    }
    
    return YES;
}

NSString *encodeEntities(NSString *string)
{
    NSString *result = string;
    result = [result stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    result = [result stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return result;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        // Parse the command line arguments.
        ISArgumentParser *parser = [ISArgumentParser argumentParserWithDescription:
                                    @"Fetch the metadata for a video media file (movie or show)."];
        [parser addArgumentWithName:@"filename"
                             number:ISArgumentParserNumberOneOrMore
                               help:@"filename of the media to be searched for"];
        [parser addArgumentWithName:@"--delete"
                    alternativeName:@"-d"
                             action:ISArgumentParserActionStoreTrue
                       defaultValue:@NO
                               type:ISArgumentParserTypeBool
                               help:@"delete the original file"];
        [parser addArgumentWithName:@"--debug"
                    alternativeName:nil
                             action:ISArgumentParserActionStoreTrue
                       defaultValue:@NO
                               type:ISArgumentParserTypeBool
                               help:@"print debug information"];
        NSError *error = nil;
        NSDictionary *options = [parser parseArgumentsWithCount:argc vector:argv error:&error];
        if (options == nil) {
            return error ? 1 : 0;
        }
        
        for (NSString *file in options[@"filename"]) {
            
            // Check that the file exists and convert to an absolute path.
            NSString *filename = file;
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (![fileManager fileExistsAtPath:filename]) {
                fprintf(stderr, "File '%s' does not exist.\n", [file UTF8String]);
                return 1;
            } else {
                if (![filename isAbsolutePath]) {
                    filename = [[fileManager currentDirectoryPath] stringByAppendingPathComponent:filename];
                    filename = [filename stringByStandardizingPath];
                }
            }
            
            // Configure the database client.
            ISMKDatabaseClient *databaseClient = [ISMKDatabaseClient sharedInstance];

            // Load the configuration file.
            NSString *configurationPath = [@"~/.add-to-itunes.plist" stringByExpandingTildeInPath];
            NSError *error = nil;
            BOOL success = [databaseClient configureWithFileAtPath:configurationPath error:&error];
            if (!success) {
                fprintf(stderr, "%s\n", [error.userInfo[ISMediaKitFailureReasonErrorKey] UTF8String]);
                return 1;
            }
            
            // Fetch the metadata.
            printf("Fetching metadata for '%s'...\n", [[filename lastPathComponent] UTF8String]);
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block NSMutableDictionary *media = nil;
            [databaseClient searchWithFilename:filename completionBlock:^(NSDictionary *result) {
                media = [result mutableCopy];
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            if (media == nil) {
                fprintf(stderr, "Unable to find media.\n");
                return 1;
            }
            
            // Download the artwork.
            success = downloadFields(media, @[ISMKKeyMovieThumbnail, ISMKKeyShowThumbnail]);
            if (!success) {
                fprintf(stderr, "Unable to download artwork.\n");
                return 1;
            }
            
            // Add the media file to iTunes.
            ISMKType type = [media[ISMKKeyType] integerValue];
            if (type == ISMKTypeMovie) {
                
                printf("Adding movie '%s' to iTunes...\n", [media[ISMKKeyMovieTitle] UTF8String]);
                success = runScript([NSString stringWithFormat:
                                     AddMovieScript,
                                     filename,
                                     media[ISMKKeyMovieTitle],
                                     media[ISMKKeyMovieThumbnail]], [options[@"debug"] boolValue]);
                if (!success) {
                    fprintf(stderr, "Unable to add movie to iTunes.\n");
                    return 1;
                }
                
            } else if (type == ISMKTypeShow) {
                
                printf("Adding TV show '%s' to iTunes...\n", [media[ISMKKeyShowTitle] UTF8String]);
                success = runScript([NSString stringWithFormat:
                                     AddShowScript,
                                     filename,
                                     encodeEntities(media[ISMKKeyShowTitle]),
                                     encodeEntities(media[ISMKKeyEpisodeTitle]),
                                     [media[ISMKKeyEpisodeSeason] integerValue],
                                     [media[ISMKKeyEpisodeNumber] integerValue],
                                     [media[ISMKKeyEpisodeNumber] integerValue],
                                     media[ISMKKeyShowThumbnail]], [options[@"debug"] boolValue]);
                if (!success) {
                    fprintf(stderr, "Unable to add show to iTunes.\n");
                    return 1;
                }
                
            } else {
                fprintf(stderr, "Unsupported media type (%ld).\n", type);
                return 1;
            }
            
            // Delete the file if requested.
            if ([options[@"delete"] boolValue]) {
                printf("Deleting file '%s'.\n", [filename UTF8String]);
                NSError *error = nil;
                if (![fileManager removeItemAtPath:filename error:&error]) {
                    fprintf(stderr, "Unable to delete file (%s).\n", [[error description] UTF8String]);
                    return 1;
                }
            }
            
        }
        
    }
    return 0;
}
