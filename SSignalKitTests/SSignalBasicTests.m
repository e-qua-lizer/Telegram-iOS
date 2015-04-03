#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

@import SSignalKit;

#import "DeallocatingObject.h"

@interface SSignalBasicTests : XCTestCase

@end

@implementation SSignalBasicTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testSignalGenerated
{
    __block bool deallocated = false;
    __block bool disposed = false;
    __block bool generated = false;
    
    {
        DeallocatingObject *object = [[DeallocatingObject alloc] initWithDeallocated:&deallocated];
        SSignal *signal = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@1];
            [object description];
            
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                [object description];
                disposed = true;
            }];
        }];
        id<SDisposable> disposable = [signal startWithNext:^(__unused id next)
        {
            generated = true;
            [object description];
        } error:nil completed:nil];
        [disposable dispose];
    }
    
    XCTAssertTrue(deallocated);
    XCTAssertTrue(disposed);
    XCTAssertTrue(generated);
}

- (void)testSignalGeneratedCompleted
{
    __block bool deallocated = false;
    __block bool disposed = false;
    __block bool generated = false;
    __block bool completed = false;
    
    {
        DeallocatingObject *object = [[DeallocatingObject alloc] initWithDeallocated:&deallocated];
        SSignal *signal = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@1];
            [subscriber putCompletion];
            [object description];
            
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                [object description];
                disposed = true;
            }];
        }];
        id<SDisposable> disposable = [signal startWithNext:^(__unused id next)
        {
            [object description];
            generated = true;
        } error:nil completed:^
        {
            [object description];
            completed = true;
        }];
        [disposable dispose];
    }
    
    XCTAssertTrue(deallocated);
    XCTAssertTrue(disposed);
    XCTAssertTrue(generated);
    XCTAssertTrue(completed);
}

- (void)testSignalGeneratedError
{
    __block bool deallocated = false;
    __block bool disposed = false;
    __block bool generated = false;
    __block bool error = false;
    
    {
        DeallocatingObject *object = [[DeallocatingObject alloc] initWithDeallocated:&deallocated];
        SSignal *signal = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@1];
            [subscriber putError:@1];
            [object description];
            
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                [object description];
                disposed = true;
            }];
        }];
        id<SDisposable> disposable = [signal startWithNext:^(__unused id next)
        {
            generated = true;
        } error:^(__unused id value)
        {
            error = true;
        } completed:nil];
        [disposable dispose];
    }
    
    XCTAssertTrue(deallocated);
    XCTAssertTrue(disposed);
    XCTAssertTrue(generated);
    XCTAssertTrue(error);
}

- (void)testMap
{
    bool deallocated = false;
    __block bool disposed = false;
    __block bool generated = false;
    
    {
        @autoreleasepool
        {
            DeallocatingObject *object = [[DeallocatingObject alloc] initWithDeallocated:&deallocated];
            SSignal *signal = [[[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
            {
                [subscriber putNext:@1];
                [object description];
                return [[SBlockDisposable alloc] initWithBlock:^
                {
                    [object description];
                    disposed = true;
                }];
            }] map:^id(id value)
            {
                [object description];
                return @([value intValue] * 2);
            }];
            
            id<SDisposable> disposable = [signal startWithNext:^(id value)
            {
                generated = [value isEqual:@2];
            } error:nil completed:nil];
            [disposable dispose];
        }
    }
    
    XCTAssertTrue(deallocated);
    XCTAssertTrue(disposed);
    XCTAssertTrue(generated);
}

- (void)testInplaceMap
{
    bool deallocated = false;
    __block bool disposed = false;
    __block bool generated = false;
    
    @autoreleasepool
    {
        DeallocatingObject *object = [[DeallocatingObject alloc] initWithDeallocated:&deallocated];
        SSignal *signal = [[[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@1];
            __unused id a0 = [object description];
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                __unused id a1 = [object description];
                disposed = true;
            }];
        }] _mapInplace:^id(id value)
        {
            __unused id a1 = [object description];
            return @([value intValue] * 2);
        }];
        
        id<SDisposable> disposable = [signal startWithNext:^(id value)
        {
            generated = [value isEqual:@2];
        } error:nil completed:nil];
        [disposable dispose];
    }
    
    XCTAssertTrue(deallocated);
    XCTAssertTrue(disposed);
    XCTAssertTrue(generated);
}

- (void)testSubscriberDisposal
{
    __block bool disposed = false;
    __block bool generated = false;
    
    dispatch_queue_t queue = dispatch_queue_create(NULL, 0);
    
    @autoreleasepool
    {
        SSignal *signal = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            dispatch_async(queue, ^
            {
                usleep(100);
                [subscriber putNext:@1];
            });
            
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                disposed = true;
            }];
        }];
        
        id<SDisposable> disposable = [signal startWithNext:^(id value)
        {
            generated = true;
        } error:nil completed:nil];
        NSLog(@"dispose");
        [disposable dispose];
    }
    
    dispatch_barrier_sync(queue, ^
    {
    });
    
    XCTAssertTrue(disposed);
    XCTAssertFalse(generated);
}

- (void)testThen
{
    __block bool generatedFirst = false;
    __block bool disposedFirst = false;
    __block bool generatedSecond = false;
    __block bool disposedSecond = false;
    __block int result = 0;
    
    SSignal *signal = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
    {
        generatedFirst = true;
        [subscriber putNext:@(1)];
        [subscriber putCompletion];
        return [[SBlockDisposable alloc] initWithBlock:^
        {
            disposedFirst = true;
        }];
    }];
    
    signal = [signal then:[[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
    {
        generatedSecond = true;
        [subscriber putNext:@(2)];
        [subscriber putCompletion];
        return [[SBlockDisposable alloc] initWithBlock:^
        {
            disposedSecond = true;
        }];
    }]];
    
    [signal startWithNext:^(id next)
    {
        result += [next intValue];
    }];
    
    XCTAssertTrue(generatedFirst);
    XCTAssertTrue(disposedFirst);
    XCTAssertTrue(generatedSecond);
    XCTAssertTrue(disposedSecond);
    XCTAssert(result == 3);
}

- (void)testSwitchToLatest
{
    __block int result = 0;
    __block bool disposedOne = false;
    __block bool disposedTwo = false;
    __block bool disposedThree = false;
    __block bool completedAll = false;
    
    bool deallocatedOne = false;
    bool deallocatedTwo = false;
    bool deallocatedThree = false;
    
    @autoreleasepool
    {
        DeallocatingObject *objectOne = [[DeallocatingObject alloc] initWithDeallocated:&deallocatedOne];
        DeallocatingObject *objectTwo = [[DeallocatingObject alloc] initWithDeallocated:&deallocatedTwo];
        DeallocatingObject *objectThree = [[DeallocatingObject alloc] initWithDeallocated:&deallocatedThree];

        SSignal *one = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@(1)];
            [subscriber putCompletion];
            __unused id a0 = [objectOne description];
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                __unused id a0 = [objectOne description];
                disposedOne = true;
            }];
        }];
        SSignal *two = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@(2)];
            [subscriber putCompletion];
            __unused id a1 = [objectTwo description];
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                __unused id a1 = [objectOne description];
                disposedTwo = true;
            }];
        }];
        SSignal *three = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
        {
            [subscriber putNext:@(3)];
            [subscriber putCompletion];
            __unused id a0 = [objectThree description];
            return [[SBlockDisposable alloc] initWithBlock:^
            {
                __unused id a1 = [objectOne description];
                disposedThree = true;
            }];
        }];
        
        SSignal *signal = [[[[SSignal single:one] then:[SSignal single:two]] then:[SSignal single:three]] switchToLatest];
        [signal startWithNext:^(id next)
        {
            result += [next intValue];
        } error:nil completed:^
        {
            completedAll = true;
        }];
    }
    
    XCTAssert(result == 6);
    XCTAssertTrue(disposedOne);
    XCTAssertTrue(disposedTwo);
    XCTAssertTrue(disposedThree);
    XCTAssertTrue(deallocatedOne);
    XCTAssertTrue(deallocatedTwo);
    XCTAssertTrue(deallocatedThree);
    XCTAssertTrue(completedAll);
}

- (void)testSwitchToLatestError
{
    __block bool errorGenerated = false;
    
    SSignal *one = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
    {
        [subscriber putError:nil];
        return nil;
    }];
    
    [one startWithNext:^(__unused id next)
    {
        
    } error:^(__unused id error)
    {
        errorGenerated = true;
    } completed:^
    {
        
    }];
    
    XCTAssertTrue(errorGenerated);
}

- (void)testSwitchToLatestCompleted
{
    __block bool completedAll = false;
    
    SSignal *one = [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
    {
        [subscriber putCompletion];
        return nil;
    }];
    
    [one startWithNext:^(__unused id next)
    {
        
    } error:^(__unused id error)
    {
    } completed:^
    {
        completedAll = true;
    }];
    
    XCTAssertTrue(completedAll);
}

@end
