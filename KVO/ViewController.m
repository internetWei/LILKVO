//
//  ViewController.m
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import "ViewController.h"

#import "LILObject.h"
#import "NSObject+LILKVOBlock.h"
#import <objc/runtime.h>

/// 返回一个随机浮点数，包含起始值和终点值
UIKIT_STATIC_INLINE CGFloat mRandomFloat(CGFloat from, CGFloat to) {
    NSInteger precision = 100;
    CGFloat subtraction = to - from;
    subtraction = ABS(subtraction);
    subtraction *= precision;
    CGFloat randomNumber = arc4random() % ((int)subtraction + 1);
    randomNumber /= precision;
    return MIN(from, to) + randomNumber;
}

void PrintMethod(Class aClass) {
    unsigned int count;
    Method *methods = class_copyMethodList(aClass, &count);
    
    for (int i = 0; i < count; i++) {
        Method method = methods[i];
        NSString *name = NSStringFromSelector(method_getName(method));
        IMP imp = method_getImplementation(method);
        NSLog(@"name: %@, imp:%p", name, (IMP)imp);
    }
    
    free(methods);
}

@interface ViewController ()

@property (nonatomic, strong) LILObject *obj;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    
    LILObject *obj = [LILObject new];
    self.obj = obj;
    obj.offset = UIOffsetMake(1, 1);
    obj.custom = (struct Custom){1, 2, 3, 4, 5};
    obj.person = [Person fast:@"name"];
    obj.age = 1;
    obj.weight = 1;
    
    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, offset) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];
        
    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, custom) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        struct Custom oldValue;
        [oldVal getValue:&oldValue];
        struct Custom newValue;
        [newVal getValue:&newValue];
        
        NSLog(@"oldVal: (%d, %f, %ld, %f, %hd)", oldValue.par1, oldValue.par2, oldValue.par3, oldValue.par4, oldValue.par5);
        NSLog(@"newVal: (%d, %f, %ld, %f, %hd)", newValue.par1, newValue.par2, newValue.par3, newValue.par4, newValue.par5);
    }];
    
    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, person) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];
    
    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, age) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];
    
    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, weight) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];
    
    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.blackColor;
    label.text = @"轻点屏幕然后观察控制台打印";
    [self.view addSubview:label];
    [label sizeToFit];
    label.center = self.view.center;
    
    NSLog(@"-----------------");
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.obj.offset = UIOffsetMake(mRandomFloat(1, 100), arc4random_uniform(100));
    self.obj.custom = (struct Custom){arc4random_uniform(100), arc4random_uniform(100), arc4random_uniform(100), mRandomFloat(1, 100), arc4random_uniform(100)};
    self.obj.person = [Person fast:[NSString stringWithFormat:@"name%d", arc4random_uniform(100)]];
    self.obj.person = [Person fast:[NSString stringWithFormat:@"name%d", arc4random_uniform(100)]];
    self.obj.age = arc4random_uniform(100);
    self.obj.weight = mRandomFloat(1, 100);
    NSLog(@"------------");
}

@end
