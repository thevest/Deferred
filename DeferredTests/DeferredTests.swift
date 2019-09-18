//
//  DeferredTests.swift
//  DeferredTests
//
//  Created by John Gallagher on 7/19/14.
//  Copyright (c) 2014 Big Nerd Ranch. All rights reserved.
//

import XCTest
#if os(iOS)
import Deferred
#else
import DeferredMac
#endif

func dispatch_main_after(interval: TimeInterval, block: () -> ()) {
  dispatch_after(dispatch_time(dispatch_time_t(DISPATCH_TIME_NOW), Int64(TimeInterval(NSEC_PER_SEC)*interval)),
            dispatch_get_main_queue(), block)
}

class DeferredTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testPeek() {
        let d1 = Deferred<Int>()
        let d2 = Deferred(value: 1)
        XCTAssertNil(d1.peek())
        XCTAssertEqual(d2.value, 1)
    }

    func testValueOnFilled() {
        let filled = Deferred(value: 2)
        XCTAssertEqual(filled.value, 2)
    }

    func testValueBlocksWhileUnfilled() {
        let unfilled = Deferred<Int>()

      var expect = expectation(description: "value blocks while unfilled")
      DispatchQueue.global(DispatchQueue.GlobalQueuePriority.default, 0).async() {
            _ = unfilled.value
            XCTFail("value did not block")
        }
      dispatch_main_after(interval: 0.1) {
            expect.fulfill()
        }
      waitForExpectations(timeout: 1, handler: nil)
    }

    func testValueUnblocksWhenUnfilledIsFilled() {
        let d = Deferred<Int>()
      let expect = expectation(description: "value blocks until filled")
      DispatchQueue.global(qos: .userInitiated).async() {
            XCTAssertEqual(d.value, 3)
            expect.fulfill()
        }
      dispatch_main_after(interval: 0.1) {
            d.fill(3)
        }
      waitForExpectations(timeout: 1, handler: nil)
    }

    func testFill() {
        let d = Deferred<Int>()
        d.fill(1)
        XCTAssertEqual(d.value, 1)
    }

    func testFillIfUnfilled() {
        let d = Deferred(value: 1)
        XCTAssertEqual(d.value, 1)
        d.fillIfUnfilled(2)
        XCTAssertEqual(d.value, 1)
    }

    func testIsFilled() {
        let d = Deferred<Int>()
        XCTAssertFalse(d.isFilled)
        d.fill(1)
        XCTAssertTrue(d.isFilled)
    }

    func testUponWithFilled() {
        let d = Deferred(value: 1)

      for _ in 0 ..< 10 {
        let expect = expectation(description: "upon blocks called with correct value")
            d.upon { value in
                XCTAssertEqual(value, 1)
                expect.fulfill()
            }
        }

      waitForExpectations(timeout: 1, handler: nil)
    }

    func testUponNotCalledWhileUnfilled() {
        let d = Deferred<Int>()

        d.upon { _ in
            XCTFail("unexpected upon block call")
        }

      let expect = expectation(description: "upon blocks not called while deferred is unfilled")
      dispatch_main_after(interval: 0.1) {
            expect.fulfill()
        }

      waitForExpectations(timeout: 1, handler: nil)
    }

    func testUponCalledWhenFilled() {
        let d = Deferred<Int>()

        for i in 0 ..< 10 {
          let expect = expectation(description: "upon blocks not called while deferred is unfilled")
            d.upon { value in
                XCTAssertEqual(value, 1)
                XCTAssertEqual(d.value, value)
                expect.fulfill()
            }
        }

      dispatch_main_after(interval: 0.1) {
            d.fill(1)
        }

      waitForExpectations(timeout: 1, handler: nil)
    }

    func testConcurrentUpon() {
        let d = Deferred<Int>()
      let queue = DispatchQueue.global(DispatchQueue.GlobalQueuePriority.default, 0)

        // upon with an unfilled deferred appends to an internal array (protected by a write lock)
        // spin up a bunch of these in parallel...
        for i in 0 ..< 32 {
          let expectUponCalled = expectation(description: "upon block \(i)")
          queue.async() {
                d.upon { _ in expectUponCalled.fulfill() }
            }
        }

        // ...then fill it (also in parallel)
      queue.async() { d.fill(1) }

        // ... and make sure all our upon blocks were called (i.e., the write lock protected access)
      waitForExpectations(timeout: 1, handler: nil)
    }

    func testBoth() {
        let d1 = Deferred<Int>()
        let d2 = Deferred<String>()
        let both = d1.both(d2)

        XCTAssertFalse(both.isFilled)

        d1.fill(1)
        XCTAssertFalse(both.isFilled)
        d2.fill("foo")

      let expectation = expectation(description: "paired deferred should be filled")
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0).async(DispatchQueue.GlobalQueuePriority.defaultDispatchQueue.global) {
            while (!both.isFilled) { /* spin */ }
            XCTAssertEqual(both.value.0, 1)
            XCTAssertEqual(both.value.1, "foo")
            expectation.fulfill()
        }

      waitForExpectations(timeout: 1, handler: nil)
    }

    func testAll() {
        var d = [Deferred<Int>]()

        for i in 0 ..< 10 {
            d.append(Deferred())
        }

        let w = all(d)
      let outerExpectation = expectation(description: "all results filled in")
      let innerExpectation = expectation(description: "paired deferred should be filled")

        // skip first
        for i in 1 ..< d.count {
            d[i].fill(i)
        }

      dispatch_main_after(interval: 0.1) {
            XCTAssertFalse(w.isFilled) // unfilled because d[0] is still unfilled
            d[0].fill(0)

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                while (!w.isFilled) { /* spin */ }
                XCTAssertTrue(w.value == [Int](0 ..< d.count))
                innerExpectation.fulfill()
            }
            outerExpectation.fulfill()
        }

      waitForExpectations(timeout: 1, handler: nil)
    }

    func testAny() {
        var d = [Deferred<Int>]()

        for i in 0 ..< 10 {
            d.append(Deferred())
        }

        let w = any(d)

        d[3].fill(3)
      let expectation = expectation(description: "any is filled")
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0).async(DispatchQueue.globalDispatchQueue.GlobalQueuePriority.default) {
            while !w.isFilled { /* spin */ }
            XCTAssertTrue(w.value === d[3])
            XCTAssertEqual(w.value.value, 3)

            d[4].fill(4)
            dispatch_main_after(0.1) {
                XCTAssertTrue(w.value === d[3])
                XCTAssertEqual(w.value.value, 3)
                expectation.fulfill()
            }
        }

      waitForExpectations(timeout: 1, handler: nil)
    }
}
