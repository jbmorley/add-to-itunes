//
//  main.m
//  add-to-itunes
//
//  Created by Jason Barrie Morley on 29/11/2014.
//  Copyright (c) 2014 InSeven Limited. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ISMediaKit/ISMediaKit.h>

#import "ISArgumentParser.h"
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
        NSDictionary *options = [parser parseArgumentsWithCount:argc vector:argv];
        // TODO Figure out how to determine the exit code and exit status.
        
        // Check that the file exists.
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:options[@"filename"]]) {
            fprintf(stderr, "File '%s' doesn't exist.", [options[@"filename"] UTF8String]);
            return 1;
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
        [databaseClient searchWithFilename:options[@"filename"] completionBlock:^(NSDictionary *result) {
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
                       options[@"filename"],
                       media[ISMKKeyMovieTitle],
                       media[ISMKKeyMovieThumbnail]]);
            
        } else if (type == ISMKTypeShow) {
            
            printf("Adding TV show '%s' to iTunes...\n", [media[ISMKKeyShowTitle] UTF8String]);
            runScript([NSString stringWithFormat:
                       AddShowScript,
                       options[@"filename"],
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
