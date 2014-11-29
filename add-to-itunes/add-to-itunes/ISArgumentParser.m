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

#import <ISUtilities/ISUtilities.h>

#import "ISArgumentParser.h"

NSString *const ISArgumentParserActionStore = @"store";
NSString *const ISArgumentParserActionStoreTrue = @"store_true";
NSString *const ISArgumentParserActionStoreFalse = @"store_false";

@interface ISArgument : NSObject

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *alternativeName;
@property (nonatomic, readwrite, copy) id defaultValue;
@property (nonatomic, readwrite, copy) NSString *action;
@property (nonatomic, readwrite, copy) NSString *description;

@end

@implementation ISArgument

@end

@interface ISArgumentParser ()

@property (nonatomic, readonly, copy) NSString *description;
@property (nonatomic, readonly, strong) NSMutableArray *allArguments;
@property (nonatomic, readonly, strong) NSMutableArray *positionalArguments;
@property (nonatomic, readonly, strong) NSMutableDictionary *optionalArguments;

@property (nonatomic, readwrite, copy) NSString *application;
@property (nonatomic, readwrite, copy) NSString *name;

@end

@implementation ISArgumentParser

+ (NSArray *)argumentsWithCount:(int)count vector:(const char **)vector
{
    NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        const char *arg = vector[i];
        NSString *argument = [NSString stringWithUTF8String:arg];
        [arguments addObject:argument];
    }
    return arguments;
}

+ (instancetype)argumentParserWithDescription:(NSString *)description
{
    return [[ISArgumentParser alloc] initWithDescription:description];
}

- (instancetype)initWithDescription:(NSString *)description
{
    self = [super init];
    if (self) {
        _description = description;
        _allArguments = [NSMutableArray array];
        _positionalArguments = [NSMutableArray array];
        _optionalArguments = [NSMutableDictionary dictionary];
        _prefixCharacters = @"-";
        
        [self addArgumentWithName:@"--help"
                  alternativeName:@"-h"
                     defaultValue:@(NO)
                           action:ISArgumentParserActionStoreTrue
                      description:@"show this message and exit"];
    }
    return self;
}

- (void)addArgumentWithName:(NSString *)name
            alternativeName:(NSString *)alternativeName
               defaultValue:(id)defaultValue
                     action:(NSString *)action
                description:(NSString *)description
{
    // Construct the argument.
    ISArgument *argument = [[ISArgument alloc] init];
    argument.name = name;
    argument.alternativeName = alternativeName;
    argument.defaultValue = defaultValue;
    argument.action = action;
    argument.description = description;
    
    // TODO Check the validity of the argument.
    
    // TODO Check for name clashes. Especially between positional and non positional arguments.
    
    // Determine the type of the argument by checking if it begins with a prefix.
    NSArray *prefixes = [self.prefixCharacters componentsSeparatedByString:@""];
    BOOL optional = NO;
    for (NSString *prefix in prefixes) {
        NSRange prefixRange = [argument.name rangeOfString:prefix];
        if (prefixRange.location == 0) {
            optional = YES;
            break;
        }
    }
    
    [self.allArguments addObject:argument];

    // Store the argument.
    if (optional) {
        
        // TODO Check for duplicate arguments.
        
        self.optionalArguments[argument.name] = argument;
        if (argument.alternativeName) {
            self.optionalArguments[argument.alternativeName] = argument;
        }
        
    } else {
        
        [self.positionalArguments addObject:argument];
        
    }

}

- (NSArray *)characters:(NSString *)string
{
    NSMutableArray *characters = [NSMutableArray arrayWithCapacity:[string length]];
    for (NSUInteger i = 0; i < [string length]; i++) {
        unichar character = [string characterAtIndex:i];
        [characters addObject:[NSString stringWithCharacters:&character length:1]];
    }
    return characters;
}

- (NSString *)removePrefixesFromOptionWithName:(NSString *)name
{
    NSSet *prefixes = [NSSet setWithArray:[self.prefixCharacters componentsSeparatedByString:@""]];
    NSMutableArray *characters = [[self characters:name] mutableCopy];
    while ([characters count] > 0) {
        NSString *character = [characters objectAtIndex:0];
        if (![prefixes containsObject:character]) {
            break;
        }
        [characters removeObjectAtIndex:0];
    }
    return [characters componentsJoinedByString:@""];
}

- (void)addArgumentWithName:(NSString *)name
                description:(NSString *)description
{
    [self addArgumentWithName:name
              alternativeName:nil
                 defaultValue:nil
                       action:ISArgumentParserActionStore
                  description:description];
}

- (NSDictionary *)parseArguments:(NSArray *)arguments
{
    // TODO Check the minimum argument length and terminate the application correctly.
    
    self.application = arguments[0];
    self.name = [[self.application lastPathComponent] stringByDeletingPathExtension];
    
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    
    // Pre-seed the options with any default values.
    // These will be replaced when we parse the arguments themselves.
    for (ISArgument *argument in self.allArguments) {
        if (argument.defaultValue != nil) {
            options[[self removePrefixesFromOptionWithName:argument.name]] = argument.defaultValue;
        }
    }
    
    // Reverse the arguments to allow us to use the removeLastObject selector.
    NSMutableArray *remainingArguments = [arguments mutableCopy];
    NSMutableArray *positionalArguments = [NSMutableArray array];
    
    // Remove the application name from the arguments.
    [remainingArguments removeObjectAtIndex:0];
    
    const int StateScanning = 0;
    const int StateExpectSingle = 1;
    
    ISArgument *activeOption = nil;
    NSString *activeName = nil;
    
    int state = StateScanning;

    while ([remainingArguments count] > 0) {
        
        // Pop an argument.
        NSString *argument = [remainingArguments firstObject];
        [remainingArguments removeObjectAtIndex:0];
        
        switch (state) {
                
            case StateScanning: {
                
                ISArgument *option = self.optionalArguments[argument];
                if (option) {
                    
                    NSString *name = [self removePrefixesFromOptionWithName:option.name];
                    
                    if ([option.action isEqualToString:ISArgumentParserActionStore]) {
                        
                        activeOption = option;
                        activeName = name;
                        state = StateExpectSingle;
                        
                    } else if ([option.action isEqualToString:ISArgumentParserActionStoreTrue]) {
                        
                        options[name] = @(YES);
                        state = StateScanning;
                        
                    } else if ([option.action isEqualToString:ISArgumentParserActionStoreFalse]) {
                        
                        options[name] = @(NO);
                        state = StateScanning;
                        
                    } else {
                        
                        ISAssertUnreached(@"Unsupported option type.");
                        
                    }
                    
                } else {
                    
                    [positionalArguments addObject:argument];
                    state = StateScanning;
                    
                }
                
                break;
            }
            case StateExpectSingle: {
                
                options[activeName] = argument;
                activeOption = nil;
                activeName = nil;
                state = StateScanning;
                
                break;
            }
                
        }
        
        // TODO Check that the invariants hold at the end of the loop.
        
    }
    
    ISAssert(state == StateScanning, @"Expecting more arguments :(");
    
    // Process the remaining positional arguments.
    
    // TODO Support optional positional arguments.
    
    ISAssert([self.positionalArguments count] == [positionalArguments count],
             @"Unexpected length of positional arguments");
    
    NSUInteger index = 0;
    while ([positionalArguments count] > 0) {
        
        NSString *argument = [positionalArguments firstObject];
        [positionalArguments removeObjectAtIndex:0];
        
        ISArgument *positionalArgument = self.positionalArguments[index];
        
        // TODO Support argument types.
        options[positionalArgument.name] = argument;
        
        index++;
    }
    
    return options;
}

- (NSDictionary *)parseArgumentsWithCount:(int)count vector:(const char **)vector
{
    NSArray *arguments = [ISArgumentParser argumentsWithCount:count vector:vector];
    return [self parseArguments:arguments];
}

@end
