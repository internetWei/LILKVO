//
//  NSObject+LILKVOBlock.h
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import <Foundation/Foundation.h>

#ifndef LILKEYPATH
#define LILKEYPATH(objc, property) ((void)objc.property, @(#property))
#endif

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (LILKVOBlock)

@property (nonatomic, readonly) BOOL lil_isKVO;

- (void)lil_addObserverBlockForPath:(NSString *)keyPath block:(void (^)(id _Nonnull obj, id _Nullable oldVal, id _Nullable newVal))block;

- (void)lil_removeObserverBlockForPath:(NSString *)keyPath;

- (void)lil_removeObserverBlocks;

@end

NS_ASSUME_NONNULL_END
