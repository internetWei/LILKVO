//
//  NSObject+LILKVO.h
//  LILKVO
//
//  Created by LL on 2023/10/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifndef LILKEYPATH
#define LILKEYPATH(objc, property) ((void)objc.property, @(#property))
#endif

@interface NSObject (LILKVO)

@property (nonatomic, readonly) BOOL lil_isKVO;

- (void)lil_addObserverForPropertyName:(NSString *)propertyName block:(void (^)(id obj, id _Nullable oldVal, id _Nullable newVal))block;

- (void)lil_removeObserverForPropertyName:(NSString *)propertyName;

- (void)lil_removeAllObserver;

@end

NS_ASSUME_NONNULL_END
