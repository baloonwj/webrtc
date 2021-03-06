/*
 *  Copyright 2018 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include "sdk/objc/Framework/Native/src/objc_video_track_source.h"

#import "Video/RTCI420Buffer+Private.h"
#import "WebRTC/RTCVideoFrame.h"
#import "WebRTC/RTCVideoFrameBuffer.h"
#include "common_video/libyuv/include/webrtc_libyuv.h"
#include "media/base/fakevideorenderer.h"
#include "rtc_base/refcountedobject.h"
#include "rtc_base/scoped_ref_ptr.h"
#include "sdk/objc/Framework/Native/api/video_frame.h"
#import "sdk/objc/Framework/UnitTests/frame_buffer_helpers.h"

typedef void (^VideoSinkCallback)(RTCVideoFrame *);

namespace {

class ObjCCallbackVideoSink : public rtc::VideoSinkInterface<webrtc::VideoFrame> {
 public:
  ObjCCallbackVideoSink(VideoSinkCallback callback) : callback_(callback) {}

  virtual void OnFrame(const webrtc::VideoFrame &frame) {
    callback_(NativeToObjCVideoFrame(frame));
  }

 private:
  VideoSinkCallback callback_;
};

}  // namespace

@interface ObjCVideoTrackSourceTests : XCTestCase
@end

@implementation ObjCVideoTrackSourceTests {
  rtc::scoped_refptr<webrtc::ObjCVideoTrackSource> _video_source;
}

- (void)setUp {
  _video_source = new rtc::RefCountedObject<webrtc::ObjCVideoTrackSource>();
}

- (void)tearDown {
  _video_source = NULL;
}

- (void)testOnCapturedFrameAdaptsFrame {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 720, 1280, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef];

  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  cricket::FakeVideoRenderer *video_renderer = new cricket::FakeVideoRenderer();
  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(video_renderer, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  XCTAssertEqual(video_renderer->num_rendered_frames(), 1);
  XCTAssertEqual(video_renderer->width(), 360);
  XCTAssertEqual(video_renderer->height(), 640);

  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFrameWithoutAdaptation {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 360, 640, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(frame.width, outputFrame.width);
    XCTAssertEqual(frame.height, outputFrame.height);

    RTCCVPixelBuffer *outputBuffer = outputFrame.buffer;
    XCTAssertEqual(buffer.cropX, outputBuffer.cropX);
    XCTAssertEqual(buffer.cropY, outputBuffer.cropY);
    XCTAssertEqual(buffer.pixelBuffer, outputBuffer.pixelBuffer);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFrameCVPixelBufferNeedsAdaptation {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 720, 1280, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 360);
    XCTAssertEqual(outputFrame.height, 640);

    RTCCVPixelBuffer *outputBuffer = outputFrame.buffer;
    XCTAssertEqual(outputBuffer.cropX, 0);
    XCTAssertEqual(outputBuffer.cropY, 0);
    XCTAssertEqual(buffer.pixelBuffer, outputBuffer.pixelBuffer);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFrameCVPixelBufferNeedsCropping {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 380, 640, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 360);
    XCTAssertEqual(outputFrame.height, 640);

    RTCCVPixelBuffer *outputBuffer = outputFrame.buffer;
    XCTAssertEqual(outputBuffer.cropX, 10);
    XCTAssertEqual(outputBuffer.cropY, 0);
    XCTAssertEqual(buffer.pixelBuffer, outputBuffer.pixelBuffer);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFramePreAdaptedCVPixelBufferNeedsAdaptation {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 720, 1280, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef
                                                              adaptedWidth:700
                                                             adaptedHeight:700
                                                                 cropWidth:720
                                                                cropHeight:1280
                                                                     cropX:0
                                                                     cropY:0];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 297);
    XCTAssertEqual(outputFrame.height, 525);

    RTCCVPixelBuffer *outputBuffer = outputFrame.buffer;
    XCTAssertEqual(outputBuffer.cropX, 152);
    XCTAssertEqual(outputBuffer.cropY, 0);
    XCTAssertEqual(outputBuffer.cropWidth, 396);
    XCTAssertEqual(outputBuffer.cropHeight, 700);
    XCTAssertEqual(buffer.pixelBuffer, outputBuffer.pixelBuffer);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFramePreCroppedCVPixelBufferNeedsCropping {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 380, 640, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef
                                                              adaptedWidth:370
                                                             adaptedHeight:640
                                                                 cropWidth:370
                                                                cropHeight:640
                                                                     cropX:10
                                                                     cropY:0];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 360);
    XCTAssertEqual(outputFrame.height, 640);

    RTCCVPixelBuffer *outputBuffer = outputFrame.buffer;
    XCTAssertEqual(outputBuffer.cropX, 14);
    XCTAssertEqual(outputBuffer.cropY, 0);
    XCTAssertEqual(outputBuffer.cropWidth, 360);
    XCTAssertEqual(outputBuffer.cropHeight, 640);
    XCTAssertEqual(buffer.pixelBuffer, outputBuffer.pixelBuffer);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFrameSmallerPreCroppedCVPixelBufferNeedsCropping {
  CVPixelBufferRef pixelBufferRef = NULL;
  CVPixelBufferCreate(
      NULL, 380, 640, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pixelBufferRef);

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBufferRef
                                                              adaptedWidth:300
                                                             adaptedHeight:640
                                                                 cropWidth:300
                                                                cropHeight:640
                                                                     cropX:40
                                                                     cropY:0];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 300);
    XCTAssertEqual(outputFrame.height, 533);

    RTCCVPixelBuffer *outputBuffer = outputFrame.buffer;
    XCTAssertEqual(outputBuffer.cropX, 40);
    XCTAssertEqual(outputBuffer.cropY, 52);
    XCTAssertEqual(outputBuffer.cropWidth, 300);
    XCTAssertEqual(outputBuffer.cropHeight, 533);
    XCTAssertEqual(buffer.pixelBuffer, outputBuffer.pixelBuffer);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
  CVBufferRelease(pixelBufferRef);
}

- (void)testOnCapturedFrameI420BufferNeedsAdaptation {
  rtc::scoped_refptr<webrtc::I420Buffer> i420Buffer = CreateI420Gradient(720, 1280);
  RTCI420Buffer *buffer = [[RTCI420Buffer alloc] initWithFrameBuffer:i420Buffer];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 360);
    XCTAssertEqual(outputFrame.height, 640);

    RTCI420Buffer *outputBuffer = (RTCI420Buffer *)outputFrame.buffer;

    double psnr = I420PSNR(*[buffer nativeI420Buffer], *[outputBuffer nativeI420Buffer]);
    XCTAssertEqual(psnr, webrtc::kPerfectPSNR);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
}

- (void)testOnCapturedFrameI420BufferNeedsCropping {
  rtc::scoped_refptr<webrtc::I420Buffer> i420Buffer = CreateI420Gradient(380, 640);
  RTCI420Buffer *buffer = [[RTCI420Buffer alloc] initWithFrameBuffer:i420Buffer];
  RTCVideoFrame *frame =
      [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];

  XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"videoSinkCallback"];
  ObjCCallbackVideoSink callback_video_sink(^void(RTCVideoFrame *outputFrame) {
    XCTAssertEqual(outputFrame.width, 360);
    XCTAssertEqual(outputFrame.height, 640);

    RTCI420Buffer *outputBuffer = (RTCI420Buffer *)outputFrame.buffer;

    double psnr = I420PSNR(*[buffer nativeI420Buffer], *[outputBuffer nativeI420Buffer]);
    XCTAssertGreaterThanOrEqual(psnr, 40);

    [callbackExpectation fulfill];
  });

  const rtc::VideoSinkWants video_sink_wants;
  rtc::VideoSourceInterface<webrtc::VideoFrame> *video_source_interface = _video_source;
  video_source_interface->AddOrUpdateSink(&callback_video_sink, video_sink_wants);

  _video_source->OnOutputFormatRequest(640, 360, 30);
  _video_source->OnCapturedFrame(frame);

  [self waitForExpectations:@[ callbackExpectation ] timeout:10.0];
}

@end
