#include "NitroPlayerOnLoad.hpp"

#include <jni.h>

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::nitroplayer::initialize(vm);
}

return facebook::jni::initialize(vm, []() {
  margelo::nitro::nitroplayer::registerAllNatives();
});