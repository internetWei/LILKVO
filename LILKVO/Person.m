//
//  Person.m
//  LILKVO
//
//  Created by LL on 2023/10/12.
//

#import "Person.h"

@implementation Person

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"keyPath: %@, object: %@, change: %@", keyPath, object, change);
    NSLog(@"origin: %@", _name);
}

@end


@implementation Animal

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, name: %@>", NSStringFromClass(self.class), self, _name];
}

@end
