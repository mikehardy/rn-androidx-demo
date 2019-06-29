#!/bin/bash
set -e 


# If we're in CI let's get in a clean directory
if [ "${CI}" == "true" ]; then 
  cd $HOME
fi

# Basic template create, rnfb install, link
\rm -fr rnandroidxdemo

# Which version of react-native to use? We test forward and reverse on RN59, only forward on RN60
if [ "${RNVERSION}" == "60" ]; then
  echo "Testing react-native 0.60 AndroidX app compatibility with AndroidX and non-AndroidX libraries"
  react-native init rnandroidxdemo --version react-native@0.60.0-rc.3
else
  # In the absence of overrides, we will work on RNVersion 59
  RNVERSION=59
  echo "Testing react-native 0.59 AndroidX and non-AndroidX app compatibility with AndroidX and non-AndroidX libraries"
  react-native init rnandroidxdemo --version react-native@0.59.9
fi
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
npm i react-native-bottomsheet
react-native link react-native-bottomsheet

# It appears RN0.60 will have androidx library collisions if you specify a current one
# in your dependencies, but gradle-plugin-jetifier auto-translates to 1.0.0 "strictly"
# Unreleased patch here allows the *entire library name* to be changed so you can move the whole dependency
# That was a special PR just for this project. If it works, other libraries might need it:
# https://github.com/react-native-community/react-native-maps/commit/0c76619e8b4d591265348beb83f315ad05311670
npm i 'git+https://github.com/react-native-community/react-native-maps.git#mikehardy-patch-1'
react-native link react-native-maps

# react-native-razorpay does not allow version overrides so compileSdk is 26 - that breaks. 28 is jetify-able
# master has an unreleased upstream PR to patch it so you can override, w/default to 28 for AndroidX
#npm i "git+https://github.com/razorpay/react-native-razorpay.git"
#react-native link react-native-razorpay

# Razorpay requires minSdk 19 - and this is so big now we need MultiDex if we don't go to 21
# shouldn't affect AndroidX demonstration so we'll go with it
sed -i -e $'s/minSdkVersion = 16/minSdkVersion = 21/' android/build.gradle

# react-native-blur is special because renderscript isn't handled by normal Google jetifier. But we do it 8-)
npm i @react-native-community/blur
react-native link @react-native-community/blur

# renderscript in general need some special gradle sauce
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n       renderscriptTargetApi 28/' android/app/build.gradle
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n       renderscriptSupportModeEnabled true/' android/app/build.gradle

# This is a kotlin repo, so will test kotlin transform
# This one also needed to override the entire appcompat library name for RN60
# https://github.com/mikehardy/rn-android-prompt/blob/patch-1/android/build.gradle#L56
npm i 'git+https://github.com/mikehardy/rn-android-prompt.git#patch-1'
react-native link rn-android-prompt

# Assuming your code uses AndroidX, this is all the AndroidStudio AndroidX migration does besides transform
# your app source and app libraries
echo "android.useAndroidX=true" >> android/gradle.properties
echo "android.enableJetifier=true" >> android/gradle.properties

# For RN60 Pin our AndroidX dependencies, including full library overrides (like for react-native-maps)
# For RN59, new templates already come out with supportLibVersion set to 28, or we'd set it here
if [ "${RNVERSION}" == "60" ]; then
  sed -i -e $'s/supportLibVersion = "28.0.0"/supportLibVersion = "1.0.2"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        coreLibVersion = "1.0.2"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        compatLibVersion = "1.0.2"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        coreLibName = "androidx.core:core"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        playServicesVersion = "17.0.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVersion = "17.0.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVisionVersion = "18.0.0"/' android/build.gradle
fi

# If we are in CI, we are being used as a test-suite for jetify, copy in the version under test
if [ "${CI}" == "true" ]; then 
  npm i ${TRAVIS_BUILD_DIR}
else
  npm i jetifier
fi

# Not sure why, but on macOS + node.js v12.x, this is needed as a manual install step
#npm i node-pre-gyp

time npx jetify

# Copy our demonstration App.js into place (so it is persistent across rebuilds)
if [ "${CI}" == "true" ]; then 
  rm -f App.js && cp ${TRAVIS_BUILD_DIR}/rn-androidx-demo/App.js .
else
  rm -f App.js && cp ../App.js .
fi

# Run it for Android (assumes you have an android emulator running)
if [ "$(uname)" == "Darwin" ]; then # this works around env var problems in mac
  if [ "${CI}" == true ]; then
    echo "ANDROID_SDK is $ANDROID_SDK"
  else
    USER=`whoami`
    echo "sdk.dir=/Users/$USER/Library/Android/sdk" > android/local.properties
  fi
fi

# If you don't try assembleRelease you might miss some resource errors
cd android/
./gradlew assembleDebug
./gradlew assembleRelease
cd ..

# If we are on RN0.59 it should be possible to go backwards. Try to reverse the process
if [ "${RNVERSION}" == "59" ]; then

  # Pin some dependencies back to pre-AndroidX
  sed -i -e $'s/ext {/ext {\\\n        playServicesVersion = "16.1.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVersion = "16.1.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVisionVersion = "16.2.0"/' android/build.gradle

  time npx jetify -r
  rm -f android/gradle.properties
  cd android/
  ./gradlew clean
  ./gradlew assembleDebug
  ./gradlew assembleRelease
  cd ..
fi
