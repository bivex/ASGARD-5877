#ifndef _JNI_H_
#define _JNI_H_

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t  jboolean;
typedef int8_t   jbyte;
typedef uint16_t jchar;
typedef int16_t  jshort;
typedef int32_t  jint;
typedef int64_t  jlong;
typedef float    jfloat;
typedef double   jdouble;
typedef jint     jsize;

typedef void* jobject;
typedef jobject jclass;
typedef jobject jstring;
typedef jobject jarray;

struct JNINativeInterface;
typedef const struct JNINativeInterface* JNIEnv;

struct JNIInvokeInterface;
typedef const struct JNIInvokeInterface* JavaVM;

#define JNIEXPORT __attribute__((visibility("default")))
#define JNICALL

#ifdef __cplusplus
}
#endif

#endif // _JNI_H_
