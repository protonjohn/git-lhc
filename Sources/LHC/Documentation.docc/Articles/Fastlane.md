# Building with Fastlane

This document covers the different variables used in the shared lanes defined in the LHC project. For each shared lane, your build configuration file will be evaluated according to the build train and release channel.

This means that, for each build train defined by your project, you should use the `git lhc config eval` command to see if the values defined in your configuration file appear sane for use with each of the fastlane actions mentioned below.

<!-- Note: the information below is auto-generated. Do not remove the next line. -->
<!-- >8 -->
