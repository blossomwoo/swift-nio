//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A `ChannelInboundHandler` used to decode length-delimited frames.
///
/// This is a protocol that has messages prefixed with an encoding of their length.
/// Such a protocol would look like this:
/// ````
///     <fixed width integer n in network byte order><n bytes>
/// ````
/// ````
///  BEFORE DECODE (14 bytes)         AFTER DECODE (12 bytes)
/// +--------+----------------+      +----------------+
/// | Length | Actual Content |----->| Actual Content |
/// | 0x000C | "HELLO, WORLD" |      | "HELLO, WORLD" |
/// +--------+----------------+      +----------------+
/// ````
public final class LengthFieldBasedFrameDecoder<T: FixedWidthInteger>: ByteToMessageDecoder {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    
    public var cumulationBuffer: ByteBuffer?

    private var upperBound: T
    private var state: State = .waitingForLength
    
    /// Errors thrown by the NIO LengthFieldBasedFrameDecoder module.
    public enum NIOLengthFieldBasedFrameDecoderError: Error {
        /// The frame being sent is negative length or larger than the configured maximum
        /// acceptable frame size
        case invalidFrameLength
        
        /// when the handler is removed and buffer is non-empty
        case bytesLeftOver
    }
    
    private enum State {
        case waitingForLength
        case waitingForPayload(Int)
    }
    
    public init(upperBound: T) {
        self.upperBound = upperBound
    }
    
    public func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        switch self.state {
        case .waitingForLength:
            guard let integer = buffer.readInteger(as: T.self) else {
                return .needMoreData
            }
            guard integer > 0 && integer <= self.upperBound else {
                throw NIOLengthFieldBasedFrameDecoderError.invalidFrameLength
            }
            self.state = .waitingForPayload(Int(integer))
            return .continue
        case .waitingForPayload(let dataLength):
            guard let bytes = buffer.readSlice(length: dataLength) else {
                return .needMoreData
            }
            self.state = .waitingForLength
            ctx.fireChannelRead(self.wrapInboundOut(bytes))
            return .continue
        }
    }
    
    public func handlerRemoved(ctx: ChannelHandlerContext) {
        guard let buffer = cumulationBuffer, buffer.readableBytes > 0 else {
            return
        }
        
        ctx.fireErrorCaught(NIOLengthFieldBasedFrameDecoderError.bytesLeftOver)
    }
}
