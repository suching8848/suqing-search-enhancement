import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.Function;

/** Reads only explicit mod files through the installed game's parsers. */
public final class SandboxNativeProbe {
    private static int assertions;
    private static void check(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        Path root = Paths.get(args[0]).toAbsolutePath();
        Class<?> customType = Class.forName("zombie.sandbox.CustomSandboxOptions");
        Object custom = customType.getConstructor().newInstance();
        Method read = customType.getDeclaredMethod("readFile", String.class);
        read.setAccessible(true);
        check(Boolean.TRUE.equals(read.invoke(custom, root.resolve("media/sandbox-options.txt").toString())), "native readFile");
        Field optionsField = customType.getDeclaredField("options");
        optionsField.setAccessible(true);
        List<?> options = (List<?>)optionsField.get(custom);
        check(options.size() == 1, "one option");
        Object option = options.get(0);
        Class<?> optionType = option.getClass();
        String id = (String)optionType.getField("id").get(option);
        check("SuQingSearchEnhancement.SearchHandling".equals(id), "option id");
        check("zombie.sandbox.CustomEnumSandboxOption".equals(optionType.getName()), "enum type");
        check(optionType.getField("numValues").getInt(option) == 2, "two enum values");
        check(optionType.getField("defaultValue").getInt(option) == 1, "default all");
        check("SuQingSearchEnhancement".equals(optionType.getField("page").get(option)), "page");
        check("SuQingSearchEnhancement_SearchHandling".equals(optionType.getField("translation").get(option)), "translation key");
        System.out.println("NATIVE_SANDBOX id=" + id + " enumValues=2 default=1 page=" + optionType.getField("page").get(option));

        Class<?> languageType = Class.forName("zombie.core.Language");
        Constructor<?> languageCtor = languageType.getDeclaredConstructor(String.class, String.class, String.class, boolean.class);
        languageCtor.setAccessible(true);
        Class<?> translatorType = Class.forName("zombie.core.Translator");
        Method fill = translatorType.getDeclaredMethod("tryFillMapFromFile", String.class, String.class, Map.class, languageType, Function.class);
        fill.setAccessible(true);
        Set<String> expected = new LinkedHashSet<String>(Arrays.asList(
            "Sandbox_SuQingSearchEnhancement", "Sandbox_SuQingSearchEnhancement_SearchHandling",
            "Sandbox_SuQingSearchEnhancement_SearchHandling_tooltip",
            "Sandbox_SuQingSearchEnhancement_SearchHandling_option1", "Sandbox_SuQingSearchEnhancement_SearchHandling_option2"));
        for (String name : Arrays.asList("CN", "EN")) {
            Object language = languageCtor.newInstance(name, name, "UTF-8", false);
            Map<String, String> map = new LinkedHashMap<String, String>();
            fill.invoke(null, root.toString(), "Sandbox", map, language, Function.identity());
            check(map.keySet().equals(expected), name + " exact expected keys");
            for (String key : expected) check(map.get(key) != null && !map.get(key).trim().isEmpty(), name + " nonempty " + key);
            if ("CN".equals(name)) check(map.get("Sandbox_SuQingSearchEnhancement").contains("\u641c\u7d22"), "Chinese UTF-8 retained");
            System.out.println("NATIVE_TRANSLATION language=" + name + " keys=" + map.size() + " title=" + map.get("Sandbox_SuQingSearchEnhancement"));
        }
        Class<?> coreType = Class.forName("zombie.core.Core");
        Object core = coreType.getMethod("getInstance").invoke(null);
        System.out.println("NATIVE_GAME version=" + coreType.getMethod("getVersion").invoke(core));
        System.out.println("SQSEARCH_SANDBOX_NATIVE assertions=" + assertions + " failures=0 game_started=false");
    }
}
