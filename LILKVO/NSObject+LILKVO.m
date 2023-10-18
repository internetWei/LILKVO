//
//  NSObject+LILKVO.m
//  LILKVO
//
//  Created by LL on 2023/10/12.
//

#import "NSObject+LILKVO.h"

#import <objc/runtime.h>
#import <objc/message.h>

// 必须内联，如果不内联的话，当函数返回时内部的变量会被释放，这会导致返回值是垃圾值。
static __attribute__((always_inline)) char * _getArgumentType(Method);
static void LILSetArbitraryValueAndNotify(id, SEL, ...);
static void LILKVOForwardInvocation(id, SEL, NSInvocation *);
static Class LILKVOClass(id, SEL);

struct LILTestKVO {
    CGFloat value1, value2;
};

@interface LILKVOFoarwading : NSObject
// 这里必须使用自定义结构体，只有这样才能获取 `_CF_forwarding_prep_0` 函数指针。
@property (nonatomic, assign) struct LILTestKVO value;
@end

@implementation LILKVOFoarwading
@end


@implementation NSObject (LILKVO)

- (void)lil_addObserverForPropertyName:(NSString *)propertyName block:(void (^)(id obj, id _Nullable oldVal, id _Nullable newVal))block {
    if (!block) { return; }
    if (![propertyName isKindOfClass:NSString.class] ||
        propertyName.length == 0) { return; }

    if (!class_getProperty([self class], [propertyName UTF8String])) {
        NSAssert(NO, @"对象%@没有这个属性: %@。", self, propertyName);
        return;
    }
    
    NSString *setterMethodName = [self _getPropertySetterMethodName:propertyName];
    if (!setterMethodName) {
        NSAssert(NO, @"对象%@没有属性: %@ 的setter方法，它可能是readonly类型。", self, propertyName);
        return;
    }
    
    Class kvoClass;
    
    NSLock *lock = [self _lilGetLock];
    [lock lock];
    
    if (self.lil_isKVO) {
        kvoClass = object_getClass(self);
    } else {
        const char *kvoClassName = [[NSString stringWithFormat:@"LILKVONotifying_%s", object_getClassName(self)] UTF8String];
        kvoClass = objc_getClass(kvoClassName);
        if (!kvoClass) {
            kvoClass = objc_allocateClassPair(object_getClass(self), kvoClassName, 0);
            objc_registerClassPair(kvoClass);
        }
        object_setClass(self, kvoClass);
        objc_setAssociatedObject(self, @selector(lil_isKVO), @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    NSMutableDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverForPropertyName:block:));
    if (!info) {
        info = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, @selector(lil_addObserverForPropertyName:block:), info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    NSMutableArray *blocks = info[setterMethodName];
    if (!blocks) {
        blocks = [NSMutableArray array];
        [info setValue:blocks forKey:setterMethodName];
    }
    [blocks addObject:block];
    
    [info setValue:propertyName forKey:[NSString stringWithFormat:@"%@_propertyName", setterMethodName]];
    
    NSMutableSet *observeds = info[@"observeds"];
    if (!observeds) {
        observeds = [NSMutableSet set];
        [info setValue:observeds forKey:@"observeds"];
    }
    [observeds addObject:setterMethodName];
    
    [lock unlock];
    
    SEL setterSelector = NSSelectorFromString(setterMethodName);
    Method setterMethod = class_getInstanceMethod(kvoClass, setterSelector);
    char type = *_getArgumentType(setterMethod);
    
    /*
     之所以要这样做，是因为：
     如果统一成 `class_addMethod(kvoClass, setterSelector, (IMP)LILSetArbitraryValueAndNotify, method_getTypeEncoding(setterMethod));` 这种方式的话，
     当被观察属性是 UIOffset(只要结构体内有浮点类型) 这种内部包含浮点类型的结构体时，
     并且是这样传值的话: UIOffsetMake(2, 2) (初始化时使用整数，而非2.12这种明显的浮点值)，使用 va_arg 总是无法获取到正确的值，
     所以这里修改为，如果参数类型是结构体或底下没有列出来的类型时，就采用消息转发机制处理(系统KVO也是采用的这种处理方式，暂不清楚为什么)。
     如果你知道这是为什么或者想了解更详细的问题描述，请联系我: internetwei@foxmail.com
     */
    if (type == '#' || type == '@' ||
        type == 'v' || type == 'B' ||
        type == 'c' || type == 'C' ||
        type == 's' || type == 'S' ||
        type == 'i' || type == 'I' ||
        type == 'l' || type == 'L' ||
        type == 'q' || type == 'Q' ||
        type == 'f' || type == 'd' ||
        type == 'D' || type == '*' ||
        type == '^' || type == ':') {
        class_addMethod(kvoClass, setterSelector, (IMP)LILSetArbitraryValueAndNotify, method_getTypeEncoding(setterMethod));
    } else {
        class_addMethod(kvoClass, setterSelector, [self _getForwardingIMP], method_getTypeEncoding(setterMethod));
        class_addMethod(kvoClass, @selector(forwardInvocation:), (IMP)LILKVOForwardInvocation, method_getTypeEncoding(class_getInstanceMethod(kvoClass, @selector(forwardInvocation:))));
    }
    
    class_addMethod(kvoClass, @selector(class), (IMP)LILKVOClass, method_getTypeEncoding(class_getInstanceMethod(kvoClass, @selector(class))));
}

- (void)lil_removeObserverForPropertyName:(NSString *)propertyName {
    if (![propertyName isKindOfClass:NSString.class] ||
        propertyName.length == 0) { return; }
    
    NSLock *lock = [self _lilGetLock];
    [lock lock];
    
    if (!self.lil_isKVO) {
        [lock unlock];
        return;
    }
    
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverForPropertyName:block:));
    NSMutableSet *observeds = info[@"observeds"];
    NSString *setterMethodName = [self _getPropertySetterMethodName:propertyName];
    [observeds removeObject:setterMethodName];
    
    if (observeds.count == 0) {
        object_setClass(self, class_getSuperclass(object_getClass(self)));
    }
    
    [lock unlock];
}

- (void)lil_removeAllObserver {
    NSLock *lock = [self _lilGetLock];
    [lock lock];
    
    if (!self.lil_isKVO) {
        [lock unlock];
        return;
    }
    
    NSMutableDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverForPropertyName:block:));
    [info removeAllObjects];
    object_setClass(self, class_getSuperclass(object_getClass(self)));
    
    [lock unlock];
}

- (BOOL)lil_isKVO {
    return [objc_getAssociatedObject(self, @selector(lil_isKVO)) boolValue];
}


#pragma mark - Private

- (NSLock *)_lilGetLock {
    NSLock *lock = objc_getAssociatedObject(self, @selector(_lilGetLock));
    if (lock) { return lock; }
    
    @synchronized (self) {
        lock = objc_getAssociatedObject(self, @selector(_lilGetLock));
        if (lock) { return lock; }
        lock = [[NSLock alloc] init];
        objc_setAssociatedObject(self, @selector(_lilGetLock), lock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return lock;
    }
}

- (nullable NSString *)_getPropertySetterMethodName:(NSString *)propertyName {
    objc_property_t property = class_getProperty([self class], [propertyName UTF8String]);
    if (!property) return nil;
    
    UInt count;
    objc_property_attribute_t *attributes = property_copyAttributeList(property, &count);
    
    for (UInt i = 0; i < count; i++) {
        const char *name = attributes[i].name;
        if (strcmp(name, "R") == 0) {// 属性是只读属性，没有setter方法，无法进行观察。
            free(attributes);
            return nil;
        }
        
        if (strcmp(name, "S") == 0) {
            NSString *methodName = [NSString stringWithUTF8String:attributes[i].value];
            free(attributes);
            return methodName;
        }
    }
    
    free(attributes);
    
    NSString *first = [propertyName substringToIndex:1];
    return [NSString stringWithFormat:@"set%@%@:", [first uppercaseString], [propertyName substringFromIndex:1]];
}

- (nullable IMP)_getForwardingIMP {
    static IMP imp;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /*
         开发者无法直接获得 _CF_forwarding_prep_0，
         这里通过 KVO 的中间类间接获取 _CF_forwarding_prep_0。
         */
        LILKVOFoarwading *obj = [[LILKVOFoarwading alloc] init];
        [obj addObserver:obj forKeyPath:@"value" options:NSKeyValueObservingOptionNew context:nil];
        Class aClass = object_getClass(obj);
        Method method = class_getInstanceMethod(aClass, @selector(setValue:));
        imp = method_getImplementation(method);
        [obj removeObserver:obj forKeyPath:@"value"];
    });
    return imp;
}

@end


char * _getArgumentType(Method method) {
    char t_type[0x100];
    method_getArgumentType(method, 0x2, t_type, 0x100);
    char *type = t_type;
    while (*type == 'r' || // const
           *type == 'n' || // in
           *type == 'N' || // inout
           *type == 'o' || // out
           *type == 'O' || // bycopy
           *type == 'R' || // byref
           *type == 'V') { // oneway
        type += 1; // 截取无用前缀
    }
    return type;
}


void LILSetArbitraryValueAndNotify(id self, SEL _cmd, ...) {
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverForPropertyName:block:));
    NSString *propertyName = info[[NSString stringWithFormat:@"%@_propertyName", NSStringFromSelector(_cmd)]];
    id oldVal = [self valueForKey:propertyName];
    
    Class superClass = class_getSuperclass(object_getClass(self));
    void (*originIMP)(struct objc_super *, SEL, ...) = (void *)objc_msgSendSuper;
    struct objc_super *objcSuper = &(struct objc_super){self, superClass};
    
    char type = *_getArgumentType(class_getInstanceMethod(superClass, _cmd));
    
    va_list args;
    va_start(args, _cmd);
    
    switch (type) {
        case 'v': // void
        case 'B': // bool
        case 'c': // char / BOOL
        case 'C': // unsigned char
        case 's': // short
        case 'S': // unsigned short
        case 'i': // int
        case 'I': // unsigned int
        case 'l': // long
        case 'L': // unsigned long
        {
            int arg = va_arg(args, int);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case 'q': // long long
        case 'Q': // unsigned long long
        {
            long long arg = va_arg(args, long long);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case 'f': // float
        { // 'float' will be promoted to 'double'.
            double arg = va_arg(args, double);
            originIMP(objcSuper, _cmd, (float)arg);
        } break;
        
        case 'd': // double
        {
            double arg = va_arg(args, double);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case 'D': // long double
        {
            long double arg = va_arg(args, long double);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case '*': // char *
        case '^': // pointer
        {
            void *arg = va_arg(args, void *);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case ':': // SEL
        {
            SEL arg = va_arg(args, SEL);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case '#': // Class
        {
            Class arg = va_arg(args, Class);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        case '@': // id
        {
            id arg = va_arg(args, id);
            originIMP(objcSuper, _cmd, arg);
        } break;
        
        default: NSAssert(NO, @"参数(%c)是未知类型", type);
    }
    
    va_end(args);
    
    NSSet *observeds = info[@"observeds"];
    if (![observeds containsObject:NSStringFromSelector(_cmd)]) { return; }
    
    NSArray *blocks = info[NSStringFromSelector(_cmd)];
    id newVal = nil;
    if (blocks.count > 0) {
        newVal = [self valueForKey:propertyName];
    }
    
    for (void (^block)(id, id, id) in blocks) {
        block(self, oldVal, newVal);
    }
}

void LILKVOForwardInvocation(id self, SEL _cmd, NSInvocation *anInvocation) {
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverForPropertyName:block:));
    NSString *methodName = NSStringFromSelector(anInvocation.selector);
    NSString *propertyName = info[[NSString stringWithFormat:@"%@_propertyName", methodName]];
    id oldVal = [self valueForKey:propertyName];
    
    Class superClass = class_getSuperclass(object_getClass(self));
    Method originMethod = class_getInstanceMethod(superClass, anInvocation.selector);
    char *type = _getArgumentType(originMethod);
    BOOL unsupportedType = NO;
    
    switch (*type) {
        case '{': // struct
        {
            if (strcmp(type, @encode(NSRange)) == 0) {
                NSRange value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else if (strcmp(type, @encode(CGPoint)) == 0) {
                CGPoint value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else if (strcmp(type, @encode(CGSize)) == 0) {
                CGSize value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else if (strcmp(type, @encode(CGRect)) == 0) {
                CGRect value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else if (strcmp(type, @encode(CGVector)) == 0) {
                CGVector value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else if (strcmp(type, @encode(CGAffineTransform)) == 0) {
                CGAffineTransform value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else if (strcmp(type, @encode(CGAffineTransformComponents)) == 0) {
                CGAffineTransformComponents value;
                [anInvocation getArgument:&value atIndex:0x2];
            } else {
                unsupportedType = YES;
            }
        } break;
        default: unsupportedType = YES; // '(': union, '[': array, ...
    }
    
    if (unsupportedType) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(type, &size, NULL);
        
#define case_size(_size_) \
else if (size <= 4 * _size_ ) { \
    struct dummy { char tmp[4 * _size_]; }; \
    struct dummy value;\
    [anInvocation getArgument:&value atIndex:0x2];\
}
            if (size == 0) { }
            case_size( 1) case_size( 2) case_size( 3) case_size( 4)
            case_size( 5) case_size( 6) case_size( 7) case_size( 8)
            case_size( 9) case_size(10) case_size(11) case_size(12)
            case_size(13) case_size(14) case_size(15) case_size(16)
            case_size(17) case_size(18) case_size(19) case_size(20)
            case_size(21) case_size(22) case_size(23) case_size(24)
            case_size(25) case_size(26) case_size(27) case_size(28)
            case_size(29) case_size(30) case_size(31) case_size(32)
            case_size(33) case_size(34) case_size(35) case_size(36)
            case_size(37) case_size(38) case_size(39) case_size(40)
            case_size(41) case_size(42) case_size(43) case_size(44)
            case_size(45) case_size(46) case_size(47) case_size(48)
            case_size(49) case_size(50) case_size(51) case_size(52)
            case_size(53) case_size(54) case_size(55) case_size(56)
            case_size(57) case_size(58) case_size(59) case_size(60)
            case_size(61) case_size(62) case_size(63) case_size(64)
            else {
                NSAssert(NO, @"参数(%s)是未知类型", type);
            }
#undef case_size
    }
    
    IMP originIMP = method_getImplementation(originMethod);
    [anInvocation invokeUsingIMP:originIMP];
    
    NSSet *observeds = info[@"observeds"];
    if (![observeds containsObject:methodName]) { return; }
    
    NSArray *blocks = info[methodName];
    id newVal = nil;
    if (blocks.count > 0) {
        newVal = [self valueForKey:propertyName];
    }
    for (void (^block)(id, id, id) in blocks) {
        block(self, oldVal, newVal);
    }
}

Class LILKVOClass(id self, SEL _cmd) {
    return class_getSuperclass(object_getClass(self));
}
