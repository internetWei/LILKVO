//
//  Person.m
//  LILKVO
//
//  Created by LL on 2023/10/12.
//

#import "Person.h"

@implementation Person

@end


@implementation Animal

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, name: %@>", NSStringFromClass(self.class), self, _name];
}

@end
