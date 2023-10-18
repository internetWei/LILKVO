//
//  Person.h
//  LILKVO
//
//  Created by LL on 2023/10/12.
//

#import <Foundation/Foundation.h>

@class Animal;

typedef struct {
    int par1;
    double par2;
    float par3;
    long par4;
    char par5;
    short par6;
} CustomStruct;

NS_ASSUME_NONNULL_BEGIN

@interface Person : NSObject

@property (nonatomic, assign) NSInteger age;

@property (nonatomic, assign) double weight;

@property (nonatomic, copy) NSString *name;

@property (nonatomic, strong) Animal *pet;

@property (nonatomic, assign) CustomStruct customStruct;

@end


@interface Animal : NSObject

@property (nonatomic, copy) NSString *name;

@end

NS_ASSUME_NONNULL_END
