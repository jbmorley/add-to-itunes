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
@"\n"
@"    try\n"
@"      set f to POSIX file \"%@\"\n"
@"      set data of artwork 1 to (read f as picture)\n"
@"    end try\n"
@"\n"
@"  end tell\n"
@"end tell\n";

void runScript(NSString *script)
{
    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/bin/osascript";
    task.arguments = @[@"-e", script];
    
    NSPipe *output = [NSPipe pipe];
    [task setStandardOutput:output];
    
    [task launch];
    
    // Causes us to block on the task.
    // TODO There's probably a much cleaner way of doing this.
    [[output fileHandleForReading] readDataToEndOfFile];
    
    // TODO Check the output.
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
                        description:@"Filename of the media to be searched for."];
        [parser addArgumentWithName:@"--delete"
                    alternativeName:@"-d"
                       defaultValue:@(NO)
                             action:ISArgumentParserActionStoreTrue
                        description:@"delete the original file"];
        NSError *error = nil;
        NSDictionary *options = [parser parseArgumentsWithCount:argc vector:argv error:&error];
        if (options == nil) {
            return error ? 1 : 0;
        }
        
        // Check that the file exists and convert to an absolute path.
        NSString *filename = options[@"filename"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:filename]) {
            fprintf(stderr, "File '%s' doesn't exist.\n", [options[@"filename"] UTF8String]);
            return 1;
        } else {
            if (![filename isAbsolutePath]) {
                filename = [[fileManager currentDirectoryPath] stringByAppendingPathComponent:filename];
                filename = [filename stringByStandardizingPath];
            }
        }
        
        // Check the configuration exists.
        NSString *configurationPath = [@"~/.add-to-itunes.plist" stringByExpandingTildeInPath];
        if (![fileManager fileExistsAtPath:configurationPath]) {
            fprintf(stderr, "Configuration file not found at '%s'.\n", [configurationPath UTF8String]);
            return 1;
        }
        
        // Load the configuration.
        NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:configurationPath];
        if (configuration == nil) {
            fprintf(stderr, "Unable to load configuration file at '%s'.\n", [configurationPath UTF8String]);
            return 1;
        }
        
        // Check the tvdb-api-key exists.
        NSString *tvdbAPIKey = configuration[@"tvdb-api-key"];
        if (tvdbAPIKey == nil) {
            fprintf(stderr, "Unable to find 'tvdb-api-key' in the configuration file.\n");
            return 1;
        }
        
        // Check the mdb-api-key exists.
        NSString *mdbAPIKey = configuration[@"mdb-api-key"];
        if (mdbAPIKey == nil) {
            fprintf(stderr, "Unable to find 'mdb-api-key' in the configuration file.\n");
            return 1;
        }
        
        // Configure the database client.
        ISMKDatabaseClient *databaseClient = [ISMKDatabaseClient sharedInstance];
        [databaseClient setTVDBAPIKey:tvdbAPIKey
                            mdbAPIKey:mdbAPIKey];
        
        // Fetch the metadata.
        printf("Fetching metadata...\n");
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
        BOOL success = downloadFields(media, @[ISMKKeyMovieThumbnail, ISMKKeyShowThumbnail]);
        if (!success) {
            fprintf(stderr, "Unable to download artwork.\n");
            return 1;
        }
        
        // Add the media file to iTunes.
        ISMKType type = [media[ISMKKeyType] integerValue];
        if (type == ISMKTypeMovie) {
            
            printf("Adding movie '%s' to iTunes...\n", [media[ISMKKeyMovieTitle] UTF8String]);
            runScript([NSString stringWithFormat:
                       AddMovieScript,
                       filename,
                       media[ISMKKeyMovieTitle],
                       media[ISMKKeyMovieThumbnail]]);
            
        } else if (type == ISMKTypeShow) {
            
            printf("Adding TV show '%s' to iTunes...\n", [media[ISMKKeyShowTitle] UTF8String]);
            runScript([NSString stringWithFormat:
                       AddShowScript,
                       filename,
                       encodeEntities(media[ISMKKeyShowTitle]),
                       encodeEntities(media[ISMKKeyEpisodeTitle]),
                       [media[ISMKKeyEpisodeSeason] integerValue],
                       [media[ISMKKeyEpisodeNumber] integerValue],
                       media[ISMKKeyShowThumbnail]]);
            
        } else {
            fprintf(stderr, "Unsupported media type (%ld).\n", type);
            return 1;
        }
        
        // Delete the file if requested.
        if ([options[@"delete"] boolValue]) {
            NSError *error = nil;
            if (![fileManager removeItemAtPath:options[@"filename"] error:&error]) {
                fprintf(stderr, "Unable to delete file (%s).\n", [[error description] UTF8String]);
                return 1;
            }
        }
        
    }
    return 0;
}
