//
//  Object.h
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class Person;

NS_ASSUME_NONNULL_BEGIN

@interface LILObject : NSObject

@property (nonatomic, assign) NSRange range;

@property (nonatomic, strong) Person *person;

@property (nonatomic, copy) NSString *name;

@end


@interface Person : NSObject

@property (nonatomic, copy) NSString *name;

+ (instancetype)fast:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
