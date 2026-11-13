package expo.modules.eyg;
import java.nio.charset.StandardCharsets;
public final class EygNative {
  static native long create();
  static native byte[] evaluate(long session, byte[] input);
  static native byte[] resume(long session, byte[] reply);
  static native void destroy(long session);
  static native void cancel(long session);
  public static void main(String[] args) {
    System.load(args[0]);
    long session = create();
    if (session == 0) throw new AssertionError("Native allocation failed");
    try {
      for (int i = 0; i < 1000; i++) {
        String request = "{\"source\":\"let n = perform Expo(20) !int_add(n, 22)\"}";
        String effect = new String(evaluate(session, request.getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
        if (!effect.contains("\"status\":\"effect\"")) throw new AssertionError(effect);
        String result = new String(resume(session, "{\"integer\":20}".getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
        if (!result.equals("{\"status\":\"done\",\"result\":{\"value\":{\"integer\":42}}}")) throw new AssertionError(result);
      }
      String request = "{\"program\":{\"0\":\"s\",\"v\":\"héllo\\u0000🌱\"}}";
      String result = new String(evaluate(session, request.getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
      if (!result.contains("héllo\\u0000🌱")) throw new AssertionError(result);
      cancel(session);
      result = new String(evaluate(session, request.getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
      if (!result.equals("{\"status\":\"error\",\"error\":\"Cancelled\"}")) throw new AssertionError(result);
      System.out.println("{\"jniEffectResumeCases\":1000,\"utf8AndNul\":\"passed\"}");
    } finally { destroy(session); }
  }
}
