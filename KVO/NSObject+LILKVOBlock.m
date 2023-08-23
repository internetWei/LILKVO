//
//  NSObject+LILKVOBlock.m
//  KVO
//
//  Created by LL on 2023/8/18.
//

#import "NSObject+LILKVOBlock.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>

static void _property_getAttributeList(id, NSString *, NSString * _Nullable *, NSString * _Nullable *);
static void _lilSetImplementation(id, SEL, ...);
static Class _lilClass(id, SEL);

@implementation NSObject (LILKVOBlock)

- (void)lil_addObserverBlockForPath:(NSString *)keyPath block:(void (^)(id _Nonnull, id _Nullable, id _Nullable))block {
    if (!block) { return; }
    if (![keyPath isKindOfClass:NSString.class]) { return; }
    if (keyPath.length == 0) { return; }
    
    if (!class_getProperty([self class], [keyPath UTF8String])) {
        NSAssert(NO, @"对象(%@)没有该属性(%@)。", self, keyPath);
        return;
    }
    
    NSString *setterMethodString, *ivarName;
    _property_getAttributeList(self, keyPath, &setterMethodString, &ivarName);

    SEL setterSelector = NSSelectorFromString(setterMethodString);
    if (![self respondsToSelector:setterSelector]) {
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
    
    // 开发者可以通过 @dynamic 修改实例变量名称，所以变量名称不一定是 _属性名。
    [info setValue:ivarName forKey:[NSString stringWithFormat:@"%@_ivarName", setterMethodString]];
    
    NSMutableSet *observerPropertys = info[@"OBSERVER_PROPERTY"];
    if (!observerPropertys) {
        observerPropertys = [NSMutableSet set];
        [info setValue:observerPropertys forKey:@"OBSERVER_PROPERTY"];
    }
    [observerPropertys addObject:setterMethodString];
    
    [lock unlock];
    
    class_addMethod(kvoClass, setterSelector, (IMP)_lilSetImplementation, method_getTypeEncoding(class_getInstanceMethod(kvoClass, setterSelector)));
    class_addMethod(kvoClass, @selector(class), (IMP)_lilClass, method_getTypeEncoding(class_getInstanceMethod(kvoClass, @selector(class))));
    class_addMethod(kvoClass, NSSelectorFromString(@"_isKVOA"), imp_implementationWithBlock(^ bool (id obj) { return true; }), method_getTypeEncoding(class_getInstanceMethod(kvoClass, NSSelectorFromString(@"_isKVOA"))));    
}


- (void)lil_removeObserverBlockForPath:(NSString *)keyPath {
    if (!self.lil_isKVO) { return; }
    if (![keyPath isKindOfClass:NSString.class]) { return; }
    if (keyPath.length == 0) { return; }
    
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    NSMutableSet *observerPropertys = info[@"OBSERVER_PROPERTY"];
    NSString *setterMethodString = nil;
    _property_getAttributeList(self, keyPath, &setterMethodString, nil);
    [observerPropertys removeObject:setterMethodString];
    
    if (observerPropertys.count == 0) {
        object_setClass(self, [self class]);
    }
}


- (void)lil_removeObserverBlocks {
    if (!self.lil_isKVO) { return; }
    NSMutableDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    [info removeAllObjects];
    object_setClass(self, [self class]);
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


void _lilSetImplementation(id self, SEL _cmd, ...) {
    Class superClass = class_getSuperclass(object_getClass(self));
    void (*superMethod)(struct objc_super *, SEL, ...) = (void *)objc_msgSendSuper;
    struct objc_super *superObjc = &(struct objc_super){self, superClass};
    
    char type[256];
    Method t_method = class_getInstanceMethod(superClass, _cmd);
    method_getArgumentType(t_method, 0x2, type, 256);
    
    NSDictionary *info = objc_getAssociatedObject(self, @selector(lil_addObserverBlockForPath:block:));
    NSString *ivarName = info[[NSString stringWithFormat:@"%@_ivarName", NSStringFromSelector(_cmd)]];
    id oldVal = [self valueForKey:ivarName];
    
    int index = 0;
    while (type[index] == 'r' || // const
           type[index] == 'n' || // in
           type[index] == 'N' || // inout
           type[index] == 'o' || // out
           type[index] == 'O' || // bycopy
           type[index] == 'R' || // byref
           type[index] == 'V') { // oneway
        index++;// 截取无用前缀
    }
    
    va_list args;
    va_start(args, _cmd);
    
    BOOL unsupportedType = NO;
    id newVal = nil;
    switch (type[index]) {
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
        
        case '{': // struct
        {
            if (strcmp(type, @encode(CGPoint)) == 0) {
                CGPoint arg = va_arg(args, CGPoint);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithCGPoint:arg];
            } else if (strcmp(type, @encode(CGSize)) == 0) {
                CGSize arg = va_arg(args, CGSize);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithCGSize:arg];
            } else if (strcmp(type, @encode(CGRect)) == 0) {
                CGRect arg = va_arg(args, CGRect);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithCGRect:arg];
            } else if (strcmp(type, @encode(CGVector)) == 0) {
                CGVector arg = va_arg(args, CGVector);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithCGVector:arg];
            } else if (strcmp(type, @encode(CGAffineTransform)) == 0) {
                CGAffineTransform arg = va_arg(args, CGAffineTransform);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithCGAffineTransform:arg];
            } else if (strcmp(type, @encode(NSRange)) == 0) {
                NSRange arg = va_arg(args, NSRange);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithRange:arg];
            } else if (strcmp(type, @encode(UIOffset)) == 0) {
                UIOffset arg = va_arg(args, UIOffset);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithUIOffset:arg];
            } else if (strcmp(type, @encode(UIEdgeInsets)) == 0) {
                UIEdgeInsets arg = va_arg(args, UIEdgeInsets);
                superMethod(superObjc, _cmd, arg);
                newVal = [NSValue valueWithUIEdgeInsets:arg];
            } else {
                unsupportedType = YES;
            }
        } break;
        
        case '(': // union
        case '[': // array
        default: unsupportedType = YES;
    }
    
    if (unsupportedType) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(type, &size, NULL);
        
#define case_size(_size_) \
else if (size <= 4 * _size_ ) { \
    struct dummy { char tmp[4 * _size_]; }; \
    struct dummy arg = va_arg(args, struct dummy); \
    superMethod(superObjc, _cmd, arg);\
    newVal = [NSValue valueWithBytes:&arg objCType:type];\
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
                NSLog(@"参数(%s)是未知类型", type);
            }
#undef case_size
    }
    
    va_end(args);
    
    NSSet *observerPropertys = info[@"OBSERVER_PROPERTY"];
    if (![observerPropertys containsObject:NSStringFromSelector(_cmd)]) { return; }
    
    NSArray *blocks = info[NSStringFromSelector(_cmd)];
    for (void (^block)(id, id, id) in blocks) {
        block(self, oldVal, newVal);
    }
}


Class _lilClass(id self, SEL _cmd) {
    Class superClass = class_getSuperclass(object_getClass(self));
    Class (*superMethod)(struct objc_super *, SEL, ...) = (void *)objc_msgSendSuper;
    return superMethod(&(struct objc_super){self, superClass}, _cmd);
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
