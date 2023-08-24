//
//  Object.h
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class Person;

struct Custom {
    int par1;
    double par2;
    long par3;
    float par4;
    short par5;
};

NS_ASSUME_NONNULL_BEGIN

@interface LILObject : NSObject

@property (nonatomic, assign) UIOffset offset;

@property (nonatomic, assign) struct Custom custom;

@property (nonatomic, strong) Person *person;

@property (nonatomic, assign) int age;

@property (nonatomic, assign) double weight;

@end


@interface Person : NSObject

@property (nonatomic, copy) NSString *name;

+ (instancetype)fast:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
