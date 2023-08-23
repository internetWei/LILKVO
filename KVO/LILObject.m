//
//  Object.m
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import "LILObject.h"

@implementation LILObject

@end


@implementation Person

+ (instancetype)fast:(NSString *)name {
    Person *p = [[self alloc] init];
    p.name = name;
    return p;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<Person: %p, name: %@>", self, _name];
}

@end
