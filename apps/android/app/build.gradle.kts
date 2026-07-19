import groovy.json.JsonSlurper
import java.net.URI

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.compose)
}

val generatedSkillAssets = layout.buildDirectory.dir("generated/skillAssets/main")
val packagedAgentAppRoot = providers.environmentVariable("AGENTWEAVE_APP_ROOT")
  .orElse(rootProject.projectDir.resolve("../../examples/secretary-agent").absolutePath)
val oidcRedirectScheme = providers.provider {
  val manifest = file(packagedAgentAppRoot.get()).resolve("agent-app.json")
  if (!manifest.isFile) return@provider "agentweave.mobile"
  @Suppress("UNCHECKED_CAST")
  val document = JsonSlurper().parse(manifest) as Map<String, Any?>
  val identity = document["identity"] as? Map<*, *>
  if (identity?.get("mode") != "required") return@provider "agentweave.mobile"
  val provider = identity["provider"] as? Map<*, *>
  val publicConfig = provider?.get("publicConfig") as? Map<*, *>
  val redirect = publicConfig?.get("redirectUri") as? String
    ?: error("Required Android identity is missing redirectUri")
  val uri = URI(redirect)
  require(
    uri.scheme?.contains('.') == true &&
      uri.rawAuthority == null &&
      !uri.path.isNullOrBlank() &&
      uri.rawQuery == null &&
      uri.rawFragment == null
  ) {
    "Android OIDC redirectUri must use a private reverse-domain scheme and callback path"
  }
  uri.scheme
}

android {
  namespace = "com.agentweave.mobile"
  compileSdk = 37

  defaultConfig {
    applicationId = "com.agentweave.mobile"
    minSdk = 31
    targetSdk = 36
    versionCode = 1
    versionName = "0.1.0"
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    manifestPlaceholders["oidcRedirectScheme"] = oidcRedirectScheme.get()
  }

  buildFeatures {
    compose = true
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  testOptions {
    unitTests.isIncludeAndroidResources = true
  }

  sourceSets.named("debug") {
    jniLibs.directories.add("build/generated/rustJniLibs/debug")
  }

  sourceSets.named("main") {
    assets.directories.add("build/generated/skillAssets/main")
    assets.directories.add(rootProject.projectDir.resolve("../../catalog").absolutePath)
    assets.directories.add(rootProject.projectDir.resolve("../../resources").absolutePath)
  }

  sourceSets.named("release") {
    jniLibs.directories.add("build/generated/rustJniLibs/release")
  }
}

dependencies {
  val composeBom = platform(libs.androidx.compose.bom)
  implementation(composeBom)
  implementation(libs.androidx.activity.compose)
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.work.runtime)
  implementation(libs.androidx.compose.material3)
  implementation(libs.androidx.compose.material.icons.extended)
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.tooling.preview)
  debugImplementation(libs.androidx.compose.ui.tooling)

  testImplementation(libs.junit)
  testImplementation(libs.robolectric)
  androidTestImplementation(libs.androidx.test.core)
  androidTestImplementation(libs.androidx.test.runner)
  androidTestImplementation(libs.junit)
}

val makeGeneratedAndroidAssetsWritable by tasks.registering(Exec::class) {
  workingDir(rootProject.projectDir.resolve("../.."))
  commandLine(
    "node",
    "scripts/build-android-rust.mjs",
    "--make-generated-assets-writable",
  )
  inputs.file(rootProject.projectDir.resolve("../../scripts/build-android-rust.mjs"))
  outputs.upToDateWhen { false }
}

val prepareAndroidSkillAssets by tasks.registering(Exec::class) {
  workingDir(rootProject.projectDir.resolve("../.."))
  commandLine("node", "scripts/build-android-rust.mjs", "--skills-only")
  inputs.dir(rootProject.projectDir.resolve("../../skills"))
  inputs.dir(packagedAgentAppRoot)
  inputs.property(
    "agentAppLocales",
    providers.environmentVariable("AGENTWEAVE_APP_LOCALES").orElse(""),
  )
  inputs.property(
    "agentAppDefaultLocale",
    providers.environmentVariable("AGENTWEAVE_APP_DEFAULT_LOCALE").orElse(""),
  )
  inputs.file(rootProject.projectDir.resolve("../../scripts/build-android-rust.mjs"))
  outputs.dir(generatedSkillAssets)
  outputs.upToDateWhen { false }
  dependsOn(makeGeneratedAndroidAssetsWritable)
}

val buildRustNativeDebug by tasks.registering(Exec::class) {
  workingDir(rootProject.projectDir.resolve("../.."))
  commandLine("node", "scripts/build-android-rust.mjs", "--rust-only")
  environment("AGENTWEAVE_ANDROID_RUST_PROFILE", "debug")
  dependsOn(prepareAndroidSkillAssets)
}

val buildRustNativeRelease by tasks.registering(Exec::class) {
  workingDir(rootProject.projectDir.resolve("../.."))
  commandLine("node", "scripts/build-android-rust.mjs", "--rust-only")
  environment("AGENTWEAVE_ANDROID_RUST_PROFILE", "release")
  dependsOn(prepareAndroidSkillAssets)
}

tasks.named("preBuild") {
  dependsOn(prepareAndroidSkillAssets)
}

tasks.matching { it.name == "preDebugBuild" }.configureEach {
  dependsOn(buildRustNativeDebug)
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
  dependsOn(buildRustNativeRelease)
}
