//
//  Object.m
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import "LILObject.h"

@implementation LILObject

- (void)dealloc {
    NSLog(@"%s, %@", __func__, self);
}

- (void)setOffset:(UIOffset)offset {
    _offset = offset;
    NSLog(@"setOffset: %@", NSStringFromUIOffset(offset));
}

- (void)setCustom:(struct Custom)custom {
    _custom = custom;
    NSLog(@"setCustom: (%d, %f, %ld, %f, %hd)", custom.par1, custom.par2, custom.par3, custom.par4, custom.par5);
}

- (void)setPerson:(Person *)person {
    _person = person;
    NSLog(@"setPerson: %@", person);
}

- (void)setAge:(int)age {
    _age = age;
    NSLog(@"setAge: %d", age);
}

- (void)setWeight:(double)weight {
    _weight = weight;
    NSLog(@"setWeight: %f", weight);
}

@end


@implementation Person

+ (instancetype)fast:(NSString *)name {
    Person *p = [[self alloc] init];
    p.name = name;
    return p;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<Person: %p, %@>", self, _name];
}

@end
