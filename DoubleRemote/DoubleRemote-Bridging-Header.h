//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <CameraKitSDK/CameraKitSDK.h>

#import <DoubleControlSDK/DoubleControlSDK.h>

void camHigh() {
    [[DRCameraKit sharedCameraKit] setCameraSettingsWithArray:(cameraSetting *)kCameraSettingsFullRes_15FPS];
}

void camMedium() {
    [[DRCameraKit sharedCameraKit] setCameraSettingsWithArray:(cameraSetting *)kCameraSettings1280x960_30FPS];
}

void camLow() {
    [[DRCameraKit sharedCameraKit] setCameraSettingsWithArray:(cameraSetting *)kCameraSettings640x480_15FPS_ISP];
}

void camNight() {
    [[DRCameraKit sharedCameraKit] setCameraSettingsWithArray:(cameraSetting *)kCameraSettingsFullRes_15FPS_low ];
}
