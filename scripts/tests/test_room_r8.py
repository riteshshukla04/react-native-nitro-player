"""Run with python3 scripts/tests/test_room_r8.py (JDK and Android SDK required)."""

import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


class RoomConstructorShrinkingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="nitro-room-r8-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.java = shutil.which("java")
        cls.javac = shutil.which("javac")
        if not cls.java or not cls.javac:
            raise RuntimeError("Install a JDK to run the R8 regression test")
        configured = os.environ.get("R8_JAR")
        sdk = Path(os.environ.get("ANDROID_HOME", os.environ.get("ANDROID_SDK_ROOT", Path.home() / "Library/Android/sdk")))
        candidates = [Path(configured)] if configured else sorted(sdk.glob("build-tools/*/lib/d8.jar"), reverse=True)
        cls.r8 = next((p for p in candidates if p.is_file() and "com/android/tools/r8/R8.class" in zipfile.ZipFile(p).namelist()), None)
        if cls.r8 is None:
            raise RuntimeError("Set ANDROID_HOME to an SDK with build-tools, or R8_JAR to an R8 jar")
        cls.dexdump = cls.r8.parent.parent / "dexdump"
        if not cls.dexdump.is_file():
            raise RuntimeError("The SDK build-tools dexdump executable is required")
        java_home = subprocess.run([cls.java, "-XshowSettings:properties", "-version"], capture_output=True, text=True, check=True)
        cls.java_home = next(line.split("=", 1)[1].strip() for line in java_home.stderr.splitlines() if "java.home =" in line)
        sources = {
            "androidx/room/RoomDatabase.java": "package androidx.room; public abstract class RoomDatabase {}",
            "fixture/WorkDatabase_Impl.java": "package fixture; public final class WorkDatabase_Impl extends androidx.room.RoomDatabase { public WorkDatabase_Impl() {} }",
            "fixture/Main.java": """package fixture;
public final class Main {
  public static void main(String[] args) throws Exception {
    Object database = Class.forName(args[0]).getDeclaredConstructor().newInstance();
    if (!(database instanceof androidx.room.RoomDatabase)) throw new AssertionError();
    System.out.println("constructed");
  }
}""",
        }
        source_paths = []
        for name, source in sources.items():
            path = cls.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
            source_paths.append(str(path))
        classes = cls.root / "classes"
        classes.mkdir()
        subprocess.run([cls.javac, "--release", "11", "-d", str(classes), *source_paths], capture_output=True, text=True, check=True)
        cls.input_jar = cls.root / "input.jar"
        with zipfile.ZipFile(cls.input_jar, "w") as archive:
            for path in classes.rglob("*.class"):
                archive.write(path, path.relative_to(classes))
        driver = cls.root / "FullModeR8.java"
        driver.write_text("""import com.android.tools.r8.*;
import java.nio.file.*;
public final class FullModeR8 {
  public static void main(String[] args) throws Exception {
    R8Command.Builder builder = R8Command.builder()
      .addProgramFiles(Paths.get(args[0]))
      .addLibraryResourceProvider(JdkClassFileProvider.fromJdkHome(Paths.get(args[1])))
      .addProguardConfigurationFiles(Paths.get(args[2]))
      .setMode(CompilationMode.RELEASE)
      .setProguardCompatibility(false)
      .setOutput(Paths.get(args[3]), OutputMode.DexIndexed);
    try {
      builder.getClass().getMethod("enableLegacyFullModeForKeepRules", boolean.class).invoke(builder, false);
    } catch (NoSuchMethodException olderR8) {
      builder.getClass().getMethod("setEnableEmptyMemberRulesToDefaultInitRuleConversion", boolean.class).invoke(builder, false);
    }
    R8.run(builder.build());
  }
}""")
        subprocess.run([cls.javac, "-cp", str(cls.r8), "-d", str(cls.root), str(driver)], capture_output=True, text=True, check=True)
        cls.rules = (Path(__file__).resolve().parents[2] / "react-native-nitro-player/android/consumer-rules.pro").read_text()

    def shrink_and_inspect(self, rules, name):
        config = self.root / f"{name}.pro"
        # Room 2.6 keeps generated database classes. Strict full mode removes the implicit constructor keep.
        config.write_text("""-keep class fixture.Main { public static void main(java.lang.String[]); }
-keep class androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.RoomDatabase
""" + rules)
        output = self.root / f"{name}.jar"
        shrink = subprocess.run([
            self.java, "-cp", os.pathsep.join([str(self.r8), str(self.root)]), "FullModeR8",
            str(self.input_jar), self.java_home, str(config), str(output),
        ], capture_output=True, text=True)
        self.assertEqual(shrink.returncode, 0, shrink.stdout + shrink.stderr)
        with zipfile.ZipFile(output) as archive:
            dex = self.root / f"{name}.dex"
            dex.write_bytes(archive.read("classes.dex"))
        dump = subprocess.run([str(self.dexdump), str(dex)], capture_output=True, text=True, check=True).stdout
        blocks = re.split(r"Class #\d+\s+-", dump)
        return next(block for block in blocks if "Lfixture/WorkDatabase_Impl;" in block.split("Direct methods", 1)[0])

    def test_consumer_rules_preserve_reflective_database_construction(self):
        result = self.shrink_and_inspect(self.rules, "with-consumer-rules")
        self.assertRegex(result, r"name\s*:\s*'<init>'")

    def test_control_reproduces_the_constructor_failure_without_the_fix(self):
        constructor_rule = "-keep class * extends androidx.room.RoomDatabase { void <init>(); }"
        rules = self.rules.replace(constructor_rule, "")
        result = self.shrink_and_inspect(rules, "without-constructor-rule")
        self.assertNotRegex(result, r"name\s*:\s*'<init>'", "negative control must strip the reflected constructor")


if __name__ == "__main__":
    unittest.main(verbosity=2)
