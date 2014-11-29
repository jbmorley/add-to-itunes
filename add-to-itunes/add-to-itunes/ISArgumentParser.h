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
