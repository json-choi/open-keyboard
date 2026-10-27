plugins { kotlin("jvm") version "2.2.21" }
kotlin { jvmToolchain(17) }
sourceSets {
    // Compile the app's pure Kotlin core and its tests together; no Android plugin or SDK is needed.
    test {
        kotlin.srcDir("../app/src/main/java/io/github/jsonchoi/openkeyboard/core"); kotlin.srcDir("../app/src/test/java")
        resources.srcDir("../app/src/test/resources")
    }
}
dependencies { testImplementation("junit:junit:4.13.2") }
tasks.test { useJUnit() }
