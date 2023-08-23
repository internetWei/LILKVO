//
//  ViewController.m
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import "ViewController.h"

#import "LILObject.h"
#import "NSObject+LILKVOBlock.h"

@interface ViewController ()

@property (nonatomic, strong) LILObject *obj;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    
    LILObject *obj = [LILObject new];
    self.obj = obj;
    obj.range = NSMakeRange(1, 1);
    obj.person = [Person fast:@"name"];
    obj.name = @"name";
    
    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, range) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];

    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, person) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];

    [obj lil_addObserverBlockForPath:LILKEYPATH(obj, name) block:^(id  _Nonnull obj, id  _Nullable oldVal, id  _Nullable newVal) {
        NSLog(@"oldVal: %@, newVal: %@", oldVal, newVal);
    }];
    
    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.blackColor;
    label.text = @"轻点屏幕观察控制台打印";
    [self.view addSubview:label];
    [label sizeToFit];
    label.center = self.view.center;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.obj.person = [Person fast:[NSString stringWithFormat:@"name%d", arc4random_uniform(100)]];
    self.obj.name = [NSString stringWithFormat:@"name%d", arc4random_uniform(100)];
    self.obj.range = NSMakeRange(arc4random_uniform(100), arc4random_uniform(100));
    NSLog(@"------------");
}

@end
