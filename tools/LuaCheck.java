import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;

/** Compiles or runs supplied Lua in a standalone Kahlua environment only. */
public final class LuaCheck {
    public static void main(String[] args) throws Exception {
        boolean compileOnly = args.length > 0 && args[0].equals("--compile");
        Class<?> platformType = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Class<?> tableType = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> threadType = Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object platform = platformType.getConstructor().newInstance();
        Object environment = platformType.getMethod("newEnvironment").invoke(platform);
        Object thread = threadType.getConstructor(Class.forName("se.krka.kahlua.vm.Platform"), tableType)
                .newInstance(platform, environment);
        threadType.getField("debugOwnerThread").set(thread, Thread.currentThread());
        Method compile = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                .getMethod("loadstring", String.class, String.class, tableType);
        Method execute = threadType.getMethod("pcall", Object.class, Object[].class);
        int start = compileOnly ? 1 : 0;
        for (int index = start; index < args.length; index++) {
            String path = args[index];
            String text = new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
            Object closure = compile.invoke(null, text, path, environment);
            if (!compileOnly) {
                Object[] result = (Object[]) execute.invoke(thread, closure, new Object[0]);
                if (!Boolean.TRUE.equals(result[0])) {
                    throw new AssertionError(path + ": " + Arrays.toString(result));
                }
                if (result.length > 1) System.out.println(result[1]);
            }
        }
        System.out.println((compileOnly ? "COMPILE" : "EXECUTE") + " PASS files=" + (args.length - start));
    }
}
