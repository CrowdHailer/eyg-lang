package expo.modules.eyg;
import java.nio.charset.StandardCharsets;
class EygNative {
  static native byte[] pure(byte[] request);
  public static void main(String[] args) {
    System.load(args[0]);
    for (int i = 0; i < 1000; i++) {
      String request = "{\"source\":\"(args) -> { !int_add(args, 1) }\",\"argument\":{\"integer\":" + i + "},\"max_steps\":100}";
      String result = new String(pure(request.getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
      if (!result.contains("\"integer\":" + (i + 1) + "}")) throw new AssertionError(result);
    }
    String denied = "{\"source\":\"(args) -> { perform Expo(args) }\",\"argument\":{\"integer\":1}}";
    String result = new String(pure(denied.getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
    if (!result.contains("PureEffectsNotAllowed")) throw new AssertionError(result);
    System.out.println("{\"synchronousJniPureCallbacks\":1000,\"forbiddenEffects\":\"passed\"}");
  }
}
