//
//  main.m
//  LILKVO
//
//  Created by LL on 2023/10/12.
//

#import <Foundation/Foundation.h>

#import "Person.h"
#import "NSObject+LILKVO.h"

int main(int argc, const char * argv[]) {

    Person *p = [[Person alloc] init];
    p.age = 10;
    p.weight = 99.85;
    p.name = @"小明";
    Animal *dog = [[Animal alloc] init];
    dog.name = @"dog";
    p.pet = dog;
    p.customStruct = (CustomStruct){1, 87.762, 3, 89, 14, 89};
    p.book = (Book){1, 2};
    
    [p lil_addObserverForPropertyName:LILKEYPATH(p, age) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldAge: %ld, newAge: %ld", [oldVal integerValue], [newVal integerValue]);
    }];
    
    [p lil_addObserverForPropertyName:LILKEYPATH(p, weight) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldWeigth: %f, newWeight: %f", [oldVal doubleValue], [newVal doubleValue]);
    }];
    
    [p lil_addObserverForPropertyName:LILKEYPATH(p, name) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldName: %@, newName: %@", oldVal, newVal);
    }];
    
    [p lil_addObserverForPropertyName:LILKEYPATH(p, pet) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldPet: %@, newPet: %@", oldVal, newVal);
    }];
    
    [p lil_addObserverForPropertyName:LILKEYPATH(p, customStruct) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        CustomStruct oldValue;
        CustomStruct newValue;
        [oldVal getValue:&oldValue];
        [newVal getValue:&newValue];
        
        NSLog(@"(oldStruct: %d, %f, %f, %ld, %c, %hd), (newStruct: %d, %f, %f, %ld, %c, %hd)", oldValue.par1, oldValue.par2, oldValue.par3, oldValue.par4, oldValue.par5, oldValue.par6, newValue.par1, newValue.par2, newValue.par3, newValue.par4, newValue.par5, newValue.par6);
    }];
    
    [p lil_addObserverForPropertyName:LILKEYPATH(p, book) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        Book oldValue;
        Book newValue;
        [oldVal getValue:&oldValue];
        [newVal getValue:&newValue];
        
        NSLog(@"(oldBook: %f, %f), (newBook: %f, %f)", oldValue.price, oldValue.score, newValue.price, newValue.score);
    }];
    
    p.age = 21;
    p.weight = 149.14159;
    p.name = @"小红";
    Animal *cat = [[Animal alloc] init];
    cat.name = @"cat";
    p.pet = cat;
    p.customStruct = (CustomStruct){9, 99.89, 12, 99, 21, 98};
    p.book = (Book){3, 4};
    
    return 0;
}
