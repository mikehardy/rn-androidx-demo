#!/bin/bash
set -e 

# Basic template create, rnfb install, link
\rm -fr rnandroidxdemo
react-native init rnandroidxdemo
cd rnandroidxdemo

# Install a bunch of native modules that might use support libraries
npm i @react-native-community/slider
react-native link @react-native-community/slider
npm i react-native-camera
react-native link react-native-camera

# Camera is special - you have to choose a missingDimensionStrategy
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n        missingDimensionStrategy "react-native-camera", "general"/' android/app/build.gradle

npm i react-native-fs
react-native link react-native-fs
npm i "git+https://github.com/laurent22/react-native-push-notification.git"
\rm -fr node_modules/react-native-push-notification/.git
react-native link react-native-push-notification
npm i react-native-securerandom
react-native link react-native-securerandom
npm i react-native-sqlite-storage
react-native link react-native-sqlite-storage
npm i react-native-vector-icons
react-native link react-native-vector-icons
npm i react-navigation
npm i react-native-gesture-handler
react-native link react-native-gesture-handler
npm i rn-fetch-blob
react-native link rn-fetch-blob
npm i react-native-bottomsheet
react-native link react-native-bottomsheet
npm i react-native-fbsdk
react-native link react-native-fbsdk

# FBSDK is special - you have to create and register a Callbackmanager
sed -i -e $'s/import com.facebook.reactnative.androidsdk.FBSDKPackage/import com.facebook.CallbackManager;\\\nimport com.facebook.reactnative.androidsdk.FBSDKPackage/' android/app/src/main/java/com/rnandroidxdemo/MainApplication.java
sed -i -e $'s/new FBSDKPackage()/new FBSDKPackage(CallbackManager.Factory.create())/' android/app/src/main/java/com/rnandroidxdemo/MainApplication.java

npm i react-native-maps
react-native link react-native-maps

# react-native-razorpay does not allow version overrides so compileSdk is 26 - that breaks.
# I made an upstream PR to patch it so you can override, and default to 28 which works with AndroidX
npm i "git+https://github.com/mikehardy/react-native-razorpay.git#allow-version-overrides"
react-native link react-native-razorpay

# Razorpay requires minSdk 19 - and this is so big now we need MultiDex if we don't go to 21
# shouldn't affect AndroidX demonstration so we'll go with it
sed -i -e $'s/minSdkVersion = 16/minSdkVersion = 21/' android/build.gradle

# react-native-blur is special because renderscript isn't handled by normal Google jetifier. But we do it 8-)
npm i @react-native-community/blur
react-native link @react-native-community/blur

# react-native-blur is a little special though, it needs some special gradle sauce
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n       renderscriptTargetApi 28/' android/app/build.gradle
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n       renderscriptSupportModeEnabled true/' android/app/build.gradle

# This is a kotlin repo, so will test kotlin transform
npm i "git+https://github.com/mikehardy/rn-android-prompt.git"
react-native link rn-android-prompt

# Set up AndroidX for RN0.59.9 which is still using support libraries
echo "android.useAndroidX=true" >> android/gradle.properties
echo "android.enableJetifier=true" >> android/gradle.properties
npm i jetifier && npx jetify

# Copy our demonstration App.js into place (so it is persistent across rebuilds)
rm -f App.js && cp ../App.js .

# Run it for Android (assumes you have an android emulator running)
if [ "$(uname)" == "Darwin" ]; then # this works around env var problems in mac
  USER=`whoami`
  echo "sdk.dir=/Users/$USER/Library/Android/sdk" > android/local.properties
fi

# If you don't try assembleRelease you might miss some resource errors
cd android/
./gradlew assembleDebug
./gradlew assembleRelease
cd ..

npx react-native run-android
