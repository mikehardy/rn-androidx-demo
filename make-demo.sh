#!/bin/bash
set -e 

# If we're in CI let's get in a clean directory
if [ "${CI}" == "true" ]; then 
  cd $HOME

  # Let's also make sure we have enough file handles
  if [ "${TRAVIS_OS_NAME}" == "linux" ]; then
    sudo sysctl fs.inotify.max_user_watches=524288
  fi
  if [ "${TRAVIS_OS_NAME}" == "osx" ]; then
    sudo launchctl limit maxfiles 1000000 1000000 || true
    ulimit -n 1000000 || true
    npm i yarn -g # on Travis macOS yarn isn't installed?
  fi
fi

# Basic template create, rnfb install, link
\rm -fr rnandroidxdemo

# Which version of react-native to use? We test forward and reverse on RN59, only forward on RN60
echo "Testing react-native 0.$RNVERSION AndroidX and non-AndroidX compatibility"
react-native init rnandroidxdemo --version react-native@0.$RNVERSION
cd rnandroidxdemo

# Install a bunch of native modules that might use support libraries
MODULE_LIST="@react-native-community/slider react-native-camera react-native-fs react-native-push-notification"
MODULE_LIST="$MODULE_LIST react-native-securerandom react-native-sqlite-storage react-native-vector-icons"
MODULE_LIST="$MODULE_LIST react-navigation react-native-gesture-handler react-native-bottomsheet"
MODULE_LIST="$MODULE_LIST @react-native-community/blur react-native-maps rn-android-prompt"

yarn add $MODULE_LIST

if [ "${RNVERSION}" == "59" ]; then
  for MODULE in $MODULE_LIST; do
    react-native link $MODULE
  done
fi

# Camera is special - you have to choose a missingDimensionStrategy
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n        missingDimensionStrategy "react-native-camera", "general"/' android/app/build.gradle

# renderscript in general need some special gradle sauce - react-native-blur is the showcase
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n       renderscriptTargetApi 28/' android/app/build.gradle
sed -i -e $'s/defaultConfig {/defaultConfig {\\\n       renderscriptSupportModeEnabled true/' android/app/build.gradle

# We need MultiDex if we don't go to 21 shouldn't affect AndroidX demonstration so we'll go with it
sed -i -e $'s/minSdkVersion = 16/minSdkVersion = 21/' android/build.gradle

# Assuming your code uses AndroidX, this is all the AndroidStudio AndroidX migration does besides transform
# your app source and app libraries
echo "android.useAndroidX=true" >> android/gradle.properties
echo "android.enableJetifier=true" >> android/gradle.properties

# For RN60 Pin our AndroidX dependencies, including full library overrides (like for react-native-maps)
# For RN59, new templates already come out with supportLibVersion set to 28, or we'd set it here
if [ "${RNVERSION}" != "59" ]; then
  sed -i -e $'s/supportLibVersion = "28.0.0"/supportLibVersion = "1.2.0-rc01"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        coreLibVersion = "1.3.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        compatLibVersion = "1.2.0-rc01"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        supportLibVersion = "1.2.0-rc01"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        coreLibName = "androidx.core:core"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        playServicesVersion = "17.0.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVersion = "17.0.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVisionVersion = "20.0.0"/' android/build.gradle
fi

# If we are in CI, we are being used as a test-suite for jetify, copy in the version under test
if [ "${CI}" == "true" ]; then 
  yarn add ${TRAVIS_BUILD_DIR}
else
  yarn add jetifier
fi

# Not sure why, but on macOS + node.js v12.x, this is needed as a manual install step
#yarn add node-pre-gyp

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
#./gradlew assembleDebug
./gradlew assembleRelease
cd ..

# If we are on RN0.59 it should be possible to go backwards. Try to reverse the process
if [ "${RNVERSION}" == "59" ]; then

  # Pin some dependencies back to pre-AndroidX
  sed -i -e $'s/ext {/ext {\\\n        playServicesVersion = "16.1.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVersion = "16.1.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        googlePlayServicesVisionVersion = "16.2.0"/' android/build.gradle
  sed -i -e $'s/ext {/ext {\\\n        firebaseMessagingVersion = "18.0.0"/' android/build.gradle


  # react-native-camera specifically is having some sort of reverse-jetify problem.
  # gradle refuses to resolve the support library dependencies correctly and I'm out of time
  # to figure out why, given reverse-jetify is a niche case anyway. You can use the older version
  # of react-native-camera in the meanwhile
  yarn add react-native-camera@2.11.1

  time npx jetify -r
  rm -f android/gradle.properties
  cd android/
  ./gradlew clean
  #./gradlew assembleDebug
  ./gradlew assembleRelease
  cd ..
fi
