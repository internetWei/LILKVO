//
//  NSObject+LILKVOBlock.m
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import "NSObject+LILKVOBlock.h"

#import <objc/runtime.h>
#import <objc/message.h>

static void _property_getAttributeList(id, NSString *, NSString * _Nullable *, NSString * _Nullable *);
// 获取 _CF_forwarding_prep_0 函数指针。
static IMP _getForwardingIMP(void);
// 这里必须使用强制内联，因为当函数返回时内部的变量 type 会被释放，这会导致变量 t_type 是一个垃圾值。
static __attribute__((always_inline)) char * _getArgumentType(Method);

static void LILSetArbitraryValueAndNotify(id, SEL, ...);
static Class LILKVOClass(id, SEL);
static void LILKVOForwardInvocation(id, SEL, NSInvocation *);

@implementation NSObject (LILKVOBlock)

- (void)lil_addObserverBlockForPath:(NSString *)keyPath block:(void (^)(id _Nonnull, id _Nullable, id _Nullable))block {
    if (!block) { return; }
    if (![keyPath isKindOfClass:NSString.class] ||
        keyPath.length == 0) { return; }

    if (!class_getProperty([self class], [keyPath UTF8String])) {
        NSAssert(NO, @"对象(%@)没有该属性(%@)。", self, keyPath);
        return;
    }
    
    NSString *setterMethodString, *ivarName;
    _property_getAttributeList(self, keyPath, &setterMethodString, &ivarName);

    if (!setterMethodString) {
        NSAssert(NO, @"对象(%@)没找到该属性(%@)的setter方法实现，它可能是readonly类型。", self, keyPath);
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
    
    NSMutableDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    if (!info) {
        info = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:), info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    NSMutableArray *blocks = info[setterMethodString];
    if (!blocks) {
        blocks = [NSMutableArray array];
        [info setValue:blocks forKey:setterMethodString];
    }
    [blocks addObject:block];
    
    // 开发者可以通过 @synthesize 修改实例变量名称，这可能会导致实例变量名称不一定是 _属性名。
    [info setValue:ivarName forKey:[NSString stringWithFormat:@"%@_ivarName", setterMethodString]];
    
    NSMutableSet *observerProperties = info[@"OBSERVER_PROPERTY"];
    if (!observerProperties) {
        observerProperties = [NSMutableSet set];
        [info setValue:observerProperties forKey:@"OBSERVER_PROPERTY"];
    }
    [observerProperties addObject:setterMethodString];
    
    [lock unlock];
    
    SEL setterSelector = NSSelectorFromString(setterMethodString);
    Method method = class_getInstanceMethod(kvoClass, setterSelector);
    char type = *_getArgumentType(method);
    
    /*
     这里之所以要这样做，是有原因的：
     如果统一成 class_addMethod(kvoClass, setterSelector, (IMP)LILSetArbitraryValueAndNotify, method_getTypeEncoding(setterMethod)); 这种方式的话，
     当被观察属性的类型是 UIOffset(任意结构体，只要结构体内有浮点类型) 时，
     并且新值是这样写的话(UIOffsetMake(2, 2)，只要这里填的是一个整型)，使用 va_arg 总是无法获取到正确的值，大部分情况下获取到的都是0，
     所以这里修改为，如果参数类型是结构体或其它类型时，就采用消息转发机制处理，使用消息转发机制可以获取到正常的值。
     如果你看到了这个疑问，并且知道原因的话，请通过这个邮箱联系我：(internetwei@foxmail.com)
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
        class_addMethod(kvoClass, setterSelector, (IMP)LILSetArbitraryValueAndNotify, method_getTypeEncoding(method));
    } else {
        class_addMethod(kvoClass, setterSelector, _getForwardingIMP(), method_getTypeEncoding(class_getInstanceMethod(kvoClass, setterSelector)));
        class_addMethod(kvoClass, @selector(forwardInvocation:), (IMP)LILKVOForwardInvocation, method_getTypeEncoding(class_getInstanceMethod(kvoClass, @selector(forwardInvocation:))));
    }
    class_addMethod(kvoClass, @selector(class), (IMP)LILKVOClass, method_getTypeEncoding(class_getInstanceMethod(kvoClass, @selector(class))));
}


- (void)lil_removeObserverBlockForPath:(NSString *)keyPath {
    if (!self.lil_isKVO) { return; }
    if (![keyPath isKindOfClass:NSString.class] ||
        keyPath.length == 0) { return; }
    
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    NSMutableSet *observerPropertys = info[@"OBSERVER_PROPERTY"];
    NSString *setterMethodString = nil;
    _property_getAttributeList(self, keyPath, &setterMethodString, nil);
    [observerPropertys removeObject:setterMethodString];
    
    if (observerPropertys.count == 0) {
        object_setClass(self, class_getSuperclass(object_getClass(self)));
    }
}


- (void)lil_removeObserverBlocks {
    if (!self.lil_isKVO) { return; }
    NSMutableDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    [info removeAllObjects];
    object_setClass(self, class_getSuperclass(object_getClass(self)));
}


- (BOOL)lil_isKVO {
    return objc_getAssociatedObject(self, @selector(lil_isKVO));
}


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

@end


void LILKVOForwardInvocation(id self, SEL _cmd, NSInvocation *anInvocation) {
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    NSString *methodString = NSStringFromSelector(anInvocation.selector);
    NSString *ivarName = info[[NSString stringWithFormat:@"%@_ivarName", methodString]];
    id oldVal = [self valueForKey:ivarName];
    
    Class superClass = class_getSuperclass(object_getClass(self));
    Method method = class_getInstanceMethod(superClass, anInvocation.selector);
    char *type = _getArgumentType(method);
    id newVal = nil;
    BOOL unsupportedType = NO;
    
    switch (*type) {
        case '{': // struct
        {
            if (strcmp(type, @encode(NSRange)) == 0) {
                NSRange value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithRange:value];
            } else if (strcmp(type, @encode(CGPoint)) == 0) {
                CGPoint value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithBytes:&value objCType:type];
            } else if (strcmp(type, @encode(CGSize)) == 0) {
                CGSize value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithBytes:&value objCType:type];
            } else if (strcmp(type, @encode(CGRect)) == 0) {
                CGRect value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithBytes:&value objCType:type];
            } else if (strcmp(type, @encode(CGVector)) == 0) {
                CGVector value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithBytes:&value objCType:type];
            } else if (strcmp(type, @encode(CGAffineTransform)) == 0) {
                CGAffineTransform value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithBytes:&value objCType:type];
            } else if (strcmp(type, @encode(CGAffineTransformComponents)) == 0) {
                CGAffineTransformComponents value;
                [anInvocation getArgument:&value atIndex:0x2];
                newVal = [NSValue valueWithBytes:&value objCType:type];
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
    newVal = [NSValue valueWithBytes:&value objCType:type];\
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
    
    IMP originalImp = method_getImplementation(method);
    [anInvocation invokeUsingIMP:originalImp];
    
    NSSet *observerPropertys = info[@"OBSERVER_PROPERTY"];
    if (![observerPropertys containsObject:methodString]) { return; }
    
    NSArray *blocks = info[methodString];
    for (void (^block)(id, id, id) in blocks) {
        block(self, oldVal, newVal);
    }
}


void LILSetArbitraryValueAndNotify(id self, SEL _cmd, ...) {
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    NSString *ivarName = info[[NSString stringWithFormat:@"%@_ivarName", NSStringFromSelector(_cmd)]];
    id oldVal = [self valueForKey:ivarName];
    
    Class superClass = class_getSuperclass(object_getClass(self));
    void (*superMethod)(struct objc_super *, SEL, ...) = (void *)objc_msgSendSuper;
    struct objc_super *superObjc = &(struct objc_super){self, superClass};
    
    Method method = class_getInstanceMethod(superClass, _cmd);
    char *type = _getArgumentType(method);
    id newVal = nil;
    
    va_list args;
    va_start(args, _cmd);
    
    switch (*type) {
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
            superMethod(superObjc, _cmd, arg);
            newVal = @(arg);
        } break;
        
        case 'q': // long long
        case 'Q': // unsigned long long
        {
            long long arg = va_arg(args, long long);
            superMethod(superObjc, _cmd, arg);
            newVal = @(arg);
        } break;
        
        case 'f': // float
        { // 'float' will be promoted to 'double'.
            double arg = va_arg(args, double);
            float argf = arg;
            superMethod(superObjc, _cmd, argf);
            newVal = @(argf);
        } break;
        
        case 'd': // double
        {
            double arg = va_arg(args, double);
            superMethod(superObjc, _cmd, arg);
            newVal = @(arg);
        } break;
        
        case 'D': // long double
        {
            long double arg = va_arg(args, long double);
            superMethod(superObjc, _cmd, arg);
            newVal = [NSNumber numberWithDouble:arg];
        } break;
        
        case '*': // char *
        case '^': // pointer
        {
            void *arg = va_arg(args, void *);
            superMethod(superObjc, _cmd, arg);
            newVal = [NSValue valueWithPointer:arg];
        } break;
        
        case ':': // SEL
        {
            SEL arg = va_arg(args, SEL);
            superMethod(superObjc, _cmd, arg);
            newVal = NSStringFromSelector(arg);
        } break;
        
        case '#': // Class
        {
            Class arg = va_arg(args, Class);
            superMethod(superObjc, _cmd, arg);
            newVal = arg;
        } break;
        
        case '@': // id
        {
            id arg = va_arg(args, id);
            superMethod(superObjc, _cmd, arg);
            newVal = arg;
        } break;
        
        default: NSAssert(NO, @"参数(%s)是未知类型", type);
    }
    
    va_end(args);
    
    NSSet *observerPropertys = info[@"OBSERVER_PROPERTY"];
    if (![observerPropertys containsObject:NSStringFromSelector(_cmd)]) { return; }
    
    NSArray *blocks = info[NSStringFromSelector(_cmd)];
    for (void (^block)(id, id, id) in blocks) {
        block(self, oldVal, newVal);
    }
}


Class LILKVOClass(id self, SEL _cmd) {
    return class_getSuperclass(object_getClass(self));
}


void _property_getAttributeList(id self, NSString *propertyName, NSString * _Nullable *setterName, NSString * _Nullable *ivarName) {
    if (setterName) { *setterName = nil; }
    if (ivarName) { *ivarName = nil; }
    
    objc_property_t property = class_getProperty([self class], [propertyName UTF8String]);
    if (!property) return;
    
    unsigned int outCount;
    objc_property_attribute_t *attributes = property_copyAttributeList(property, &outCount);
    for (unsigned int i = 0; i < outCount; i++) {
        const char *name = attributes[i].name;
        if (strcmp(name, "R") == 0) {
            free(attributes);
            return;
        }
        
        if (strcmp(name, "S") == 0) {
            if (setterName) {
                *setterName = [NSString stringWithUTF8String:attributes[i].value];
            }
            continue;
        }
        
        if (strcmp(name, "V") == 0) {
            if (ivarName) {
                *ivarName = [NSString stringWithUTF8String:attributes[i].value];
            }
            continue;
        }
    }
    free(attributes);
    
    if (setterName && *setterName == nil) {
        NSString *firstChar = [propertyName substringToIndex:1];
        *setterName = [NSString stringWithFormat:@"set%@%@:", [firstChar uppercaseString], [propertyName substringFromIndex:1]];
    }
}


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

struct LILTestKVO {
    CGFloat a1;
    CGFloat a2;
};

@interface LILKVOFoarwading : NSObject
// 这里必须要使用自定义结构体，只有这样才能获取到 _CF_forwarding_prep_0 函数指针。
@property (nonatomic, assign) struct LILTestKVO value;
@end

@implementation LILKVOFoarwading
@end

IMP _getForwardingIMP(void) {
    static IMP imp;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /*
         开发者无法直接获取 _CF_forwarding_prep_0，
         这里通过 KVO 的中间类间接获取到 _CF_forwarding_prep_0 的函数指针。
         */
        LILKVOFoarwading *obj = [[LILKVOFoarwading alloc] init];
        [obj addObserver:obj forKeyPath:@"value" options:NSKeyValueObservingOptionNew context:nil];
        Class superClass = object_getClass(obj);
        Method method = class_getInstanceMethod(superClass, @selector(setValue:));
        imp = method_getImplementation(method);
        [obj removeObserver:obj forKeyPath:@"value"];
    });
    return imp;
}
