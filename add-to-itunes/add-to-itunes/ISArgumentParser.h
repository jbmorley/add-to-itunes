//
//  ISArgumentParser.h
//  metadata
//
//  Created by Jason Barrie Morley on 27/11/2014.
//  Copyright (c) 2014 InSeven Limited. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const ISArgumentParserActionStore;
extern NSString *const ISArgumentParserActionStoreTrue;
extern NSString *const ISArgumentParserActionStoreFalse;

@interface ISArgumentParser : NSObject

@property (nonatomic, readwrite, copy) NSString *prefixCharacters;

+ (NSArray *)argumentsWithCount:(int)count vector:(const char **)vector;

+ (instancetype)argumentParserWithDescription:(NSString *)description;
- (instancetype)initWithDescription:(NSString *)description;

- (void)addArgumentWithName:(NSString *)name
            alternativeName:(NSString *)alternativeName
               defaultValue:(id)defaultValue
                     action:(NSString *)action
                description:(NSString *)description;
- (void)addArgumentWithName:(NSString *)name
                description:(NSString *)description;

- (NSDictionary *)parseArguments:(NSArray *)arguments;
- (NSDictionary *)parseArgumentsWithCount:(int)count vector:(const char **)vector;

@end
