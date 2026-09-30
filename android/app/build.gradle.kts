plugins {
    id("com.android.application")
    // AGP 9 содержит встроенный Kotlin; плагин Flutter подключается после Android.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.klochkov.workingwithmaps"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Укажите собственный уникальный идентификатор приложения (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.klochkov.workingwithmaps"
        // Следующие значения можно изменить под требования приложения.
        // Подробнее: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Настройте собственную подпись для выпускной сборки.
            // Пока используем отладочные ключи, чтобы работала команда `flutter run --release`.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-location:21.3.0")
    testImplementation("junit:junit:4.13.2")
}
