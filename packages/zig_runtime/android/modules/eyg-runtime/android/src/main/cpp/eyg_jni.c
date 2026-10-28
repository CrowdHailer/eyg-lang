#include <jni.h>
#include <stdint.h>
#include <stddef.h>

extern void *eyg_android_create(void);
extern const uint8_t *eyg_android_evaluate(void *, const uint8_t *, size_t);
extern const uint8_t *eyg_android_resume(void *, const uint8_t *, size_t);
extern const uint8_t *eyg_android_pure(void *, const uint8_t *, size_t);
extern size_t eyg_android_result_len(void *);
extern void eyg_android_destroy(void *);
extern void eyg_android_cancel(void *);

JNIEXPORT jlong JNICALL Java_expo_modules_eyg_EygNative_create(JNIEnv *env, jobject self) {
  (void)env; (void)self;
  return (jlong)(intptr_t)eyg_android_create();
}

static jbyteArray evaluate(JNIEnv *env, jlong session, jbyteArray input, int resume) {
  if (!input || !session) return NULL;
  jsize length = (*env)->GetArrayLength(env, input);
  jbyte *bytes = (*env)->GetByteArrayElements(env, input, NULL);
  if (!bytes) return NULL;
  void *state = (void *)(intptr_t)session;
  const uint8_t *result = resume == 2
    ? eyg_android_pure(state, (const uint8_t *)bytes, (size_t)length)
    : resume
    ? eyg_android_resume(state, (const uint8_t *)bytes, (size_t)length)
    : eyg_android_evaluate(state, (const uint8_t *)bytes, (size_t)length);
  (*env)->ReleaseByteArrayElements(env, input, bytes, JNI_ABORT);
  size_t result_len = eyg_android_result_len(state);
  if (!result || result_len > INT32_MAX) return NULL;
  jbyteArray output = (*env)->NewByteArray(env, (jsize)result_len);
  if (output) (*env)->SetByteArrayRegion(env, output, 0, (jsize)result_len, (const jbyte *)result);
  return output;
}

JNIEXPORT jbyteArray JNICALL Java_expo_modules_eyg_EygNative_evaluate(JNIEnv *env, jobject self, jlong session, jbyteArray input) {
  (void)self; return evaluate(env, session, input, 0);
}
JNIEXPORT jbyteArray JNICALL Java_expo_modules_eyg_EygNative_resume(JNIEnv *env, jobject self, jlong session, jbyteArray input) {
  (void)self; return evaluate(env, session, input, 1);
}
JNIEXPORT jbyteArray JNICALL Java_expo_modules_eyg_EygNative_pure(JNIEnv *env, jobject self, jbyteArray input) {
  (void)self;
  void *session = eyg_android_create();
  if (!session) return NULL;
  jbyteArray result = evaluate(env, (jlong)(intptr_t)session, input, 2);
  eyg_android_destroy(session);
  return result;
}
JNIEXPORT void JNICALL Java_expo_modules_eyg_EygNative_destroy(JNIEnv *env, jobject self, jlong session) {
  (void)env; (void)self; eyg_android_destroy((void *)(intptr_t)session);
}
JNIEXPORT void JNICALL Java_expo_modules_eyg_EygNative_cancel(JNIEnv *env, jobject self, jlong session) {
  (void)env; (void)self; eyg_android_cancel((void *)(intptr_t)session);
}
